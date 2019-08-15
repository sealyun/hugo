+++
title = "从CNI到ovn"
date = "2019-07-08T13:50:46+02:00"
tags = ["network"]
categories = ["starting"]
description = ""
banner = "/img/kube-ovn-vpc.png"
+++

诸如calico flannel等CNI实现，通过牺牲一些功能让网络复杂度得以大幅度降低是我极其推崇的，在云原生时代应用不再关心基础设施的场景下是一个明智之举，给网络调错带来了极大方便。

openstack与k8s放一起比较意义不大，openstack还是着重与基础设施，所以对上接口还是机器设施，网络设施，存储设施等，着重与资源的抽象。

然鹅k8s不仅需要资源抽象，还需要关心应用的管理，其基于容器的设计理念已经改变了传统三层的云计算架构，而更像一个云内核，对上不再关心基础设施的接口了，反正把用户应用管好了就行。

对比早起的操作系统很发现历史是惊人的相似，早期分层式操作系统到现代的宏内核与微内核操作系统，系统设计更为内聚了。目测云操作系统也会朝着这个路子发展吧（openstack粉太多，亡openstack之心不死不敢直说）

但是！

openstack底层一些技术还是非常值得学习与应用的，如qemu kvm ovs ovn ceph DPDK等。。。

本文重点讲网络这块,ovn ovs怎么与kubernetes擦出火花
<!--more--> 

# CNI原理简述
CNI不是本文的重点，这里仅做一下简单的介绍[更多详情](https://github.com/containernetworking/cni/blob/master/SPEC.md)

CNI很简单，本质就是你实现一个命令行工具，kubelet初始化网络时会去调用这个工具，传入一些环境变量，然后根据环境变量工具去做网络配置：

配置完成后标准输出一个CNI规定的json格式，告诉k8s你的IP地址啥的

命令包含三个部分

* ADD 创建网络
* DEL 删除网络
* CHECK 检查网络

这里对ADD做一个介绍：
```
EnvCNIPath        = "CNI_PATH"
EnvNetDir         = "NETCONFPATH"
EnvCapabilityArgs = "CAP_ARGS"
EnvCNIArgs        = "CNI_ARGS"
EnvCNIIfname      = "CNI_IFNAME" # 网卡名

DefaultNetDir = "/etc/cni/net.d"

CmdAdd   = "add"
CmdCheck = "check"
CmdDel   = "del"
```

入参：
```
容器ID
网络namespace目录
网络配置 - 定义哪些容器可以join到此网络
容器内网卡名
额外参数
```

标准输出类似这样一个json：
```
{
  "cniVersion": "0.4.0",
  "interfaces": [                                            (this key omitted by IPAM plugins)
      {
          "name": "<name>",
          "mac": "<MAC address>",                            (required if L2 addresses are meaningful)
          "sandbox": "<netns path or hypervisor identifier>" (required for container/hypervisor interfaces, empty/omitted for host interfaces)
      }
  ],
  "ips": [
      {
          "version": "<4-or-6>",
          "address": "<ip-and-prefix-in-CIDR>",
          "gateway": "<ip-address-of-the-gateway>",          (optional)
          "interface": <numeric index into 'interfaces' list>
      }
...
```

那比如想拿到pod的一些元数据怎么办，典型场景是比如pod yaml里定义了属于哪个子网啥的，对不起CNI不传给你，你得拿着podid去apiserver里查，这是一个非常不爽的地方，所以现在ovn的CNI都有一个CNI server的东西去和apiserver交互。

我去实现的话会考虑把信息写到容器的label里，这样CNI工具直接去容器元数据里查找一些信息,少用一个server

# OVS与OVN安装与配置
## 编译安装
(吐槽一下ovn写的shit一般的文档)

推荐用源码安装[地址](http://www.openvswitch.org//download/)
```
wget https://www.openvswitch.org/releases/openvswitch-2.11.1.tar.gz
tar zxvf openvswitch-2.11.1.tar.gz
cd openvswitch-2.11.1
./boot.sh && ./configure && make && make install
```
有个ovn的[sandbox](http://docs.openvswitch.org/en/latest/tutorials/ovn-sandbox/) 可以这样make : `make sandbox SANDBOXFLAGS="--ovn"` 太低级咱不玩

如果编译内核模块：
```
$ make modules_install
$ config_file="/etc/depmod.d/openvswitch.conf"
$ for module in datapath/linux/*.ko; do
  modname="$(basename ${module})"
  echo "override ${modname%.ko} * extra" >> "$config_file"
  echo "override ${modname%.ko} * weak-updates" >> "$config_file"
  done
$ depmod -a
$ /sbin/modprobe openvswitch
$ /sbin/lsmod | grep openvswitch
```

## 启动ovs
```
$ export PATH=$PATH:/usr/local/share/openvswitch/scripts
$ ovs-ctl start --system-id="random"
$ ovs-appctl -t ovsdb-server ovsdb-server/add-remote ptcp:6640:IP_ADDRESS # 开启远程数据库
```
IP_ADDRESS 是控制节点管理网地址

## 验证ovs
```
$ ovs-vsctl add-br br0
$ ovs-vsctl add-port br0 eth0
$ ovs-vsctl add-port br0 vif1.0
$ ovs-vsctl show
```

## 启动ovn
```
$ /usr/share/openvswitch/scripts/ovn-ctl start_northd # 启动北向数据库
$ /usr/share/openvswitch/scripts/ovn-ctl start_controller # 启动ovn controller
$ ovn-sbctl show # 验证
$ ovn-nbctl show # 验证
```

## 配置ovs与ovn相连接
```
# ovn-nbctl set-connection ptcp:6641:0.0.0.0 -- \
            set connection . inactivity_probe=60000
# ovn-sbctl set-connection ptcp:6642:0.0.0.0 -- \
            set connection . inactivity_probe=60000
# if using the VTEP functionality:
#   ovs-appctl -t ovsdb-server ovsdb-server/add-remote ptcp:6640:0.0.0.0
```
配置ovsdb-server模块，默认ovsdb-server只允许本地访问，ovn服务需要这个权限。

## 配置ovs
controller节点使用ovs databases
```
ovs-vsctl set open . external-ids:ovn-remote=tcp:IP_ADDRESS:6642
ovs-vsctl set open . external-ids:ovn-encap-type=geneve,vxlan # 配置封装类型，geneve比较吊
ovs-vsctl set open . external-ids:ovn-encap-ip=IP_ADDRESS # 配置overlay endpoint地址
```


# OVS与容器
![](/ovn-cni.png)
## ovs单机连通性

创建容器, 设置net=none可以防止docker0默认网桥影响连通性测试
```sh
docker run -itd --name con6 --net=none ubuntu:14.04 /bin/bash
docker run -itd --name con7 --net=none ubuntu:14.04 /bin/bash
docker run -itd --name con8 --net=none ubuntu:14.04 /bin/bash
```
创建网桥
```sh
ovs-vsctl add-br ovs0
```
使用ovs-docker给容器添加网卡，并挂到ovs0网桥上
```sh
ovs-docker add-port ovs0 eth0 con6 --ipaddress=192.168.1.2/24
ovs-docker add-port ovs0 eth0 con7 --ipaddress=192.168.1.3/24
ovs-docker add-port ovs0 eth0 con8 --ipaddress=192.168.1.4/24
```
查看网桥
```sh
[root@controller /]# ovs-vsctl show
21e4d4c5-cadd-4dac-b025-c20b8108ad09
    Bridge "ovs0"
        Port "b167e3dcf8db4_l"
            Interface "b167e3dcf8db4_l"
        Port "f1c0a9d0994d4_l"
            Interface "f1c0a9d0994d4_l"
        Port "121c6b2f221c4_l"
            Interface "121c6b2f221c4_l"
        Port "ovs0"
            Interface "ovs0"
                type: internal
    ovs_version: "2.8.2"
```
测试连通性
```sh
[root@controller /]# docker exec -it con8 sh
# ping 192.168.1.2      
PING 192.168.1.2 (192.168.1.2) 56(84) bytes of data.
64 bytes from 192.168.1.2: icmp_seq=1 ttl=64 time=0.886 ms
^C
--- 192.168.1.2 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 0.886/0.886/0.886/0.000 ms
# 
# ping 192.168.1.3  
PING 192.168.1.3 (192.168.1.3) 56(84) bytes of data.
64 bytes from 192.168.1.3: icmp_seq=1 ttl=64 time=0.712 ms
^C
--- 192.168.1.3 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 0.712/0.712/0.712/0.000 ms
# 
```

### 设置VLAN tag
查看网桥
```sh
[root@controller /]# ovs-vsctl show
21e4d4c5-cadd-4dac-b025-c20b8108ad09
    Bridge "ovs0"
        Port "b167e3dcf8db4_l"
            Interface "b167e3dcf8db4_l"
        Port "f1c0a9d0994d4_l"
            Interface "f1c0a9d0994d4_l"
        Port "121c6b2f221c4_l"
            Interface "121c6b2f221c4_l"
        Port "ovs0"
            Interface "ovs0"
                type: internal
    ovs_version: "2.8.2"
```

Interface是openvswitch核心概念之一，对应模拟的是交换机中插入port的网卡设备。一个Port通常只能有一个interface，但也可以有多个interfaces(Bond).

interface type

* system(如eth0),比如想把系统上的网卡挂在网桥上
* internal(模拟网络设备，名字如果是和bridge的名字一样则叫local interface)
* tap(一个tun/tap设备)
* patch(一对虚拟设备，用来模拟插线电缆) 容器场景用的多
* geneve(以太网通过geneve隧道)
* gre(RFC2890)，ipsec_gre(RFC2890 over ipsec tunnel)
* vxlan(基于以UDP为基础的VXLAN协议上的以太网隧道)
* lisp(一个3层的隧道，还在实验阶段)
* stt（Stateless TCP Tunnel，）

查看interface
```sh
[root@controller /]# ovs-vsctl list interface f1c0a9d0994d4_l
_uuid               : cf400e7c-d2d6-4e0a-ad02-663dd63d1751
admin_state         : up
duplex              : full
error               : []
external_ids        : {container_id="con6", container_iface="eth0"}
ifindex             : 239
ingress_policing_burst: 0
ingress_policing_rate: 0
lacp_current        : []
link_resets         : 1
link_speed          : 10000000000
link_state          : up
mac_in_use          : "96:91:0a:c9:02:d6"
mtu                 : 1500
mtu_request         : []
name                : "f1c0a9d0994d4_l"
ofport              : 3
other_config        : {}
statistics          : {collisions=0, rx_bytes=1328, rx_crc_err=0, rx_dropped=0, rx_errors=0, rx_frame_err=0, rx_over_err=0, rx_packets=18, tx_bytes=3032, tx_dropped=0, tx_errors=0, tx_packets=40}
status              : {driver_name=veth, driver_version="1.0", firmware_version=""}
type                : ""
```
设置vlan tag
```sh
ovs-vsctl set port   f1c0a9d0994d4_l tag=100  //con6
ovs-vsctl set port   b167e3dcf8db4_l tag=100  //con8
ovs-vsctl set port   121c6b2f221c4_l tag=200  //con7
```

测试连通性
```sh
[root@controller /]# docker exec -it con8 sh
# 
# ping 192.168.1.2 -c 3
PING 192.168.1.2 (192.168.1.2) 56(84) bytes of data.
64 bytes from 192.168.1.2: icmp_seq=1 ttl=64 time=0.413 ms
64 bytes from 192.168.1.2: icmp_seq=2 ttl=64 time=0.061 ms
64 bytes from 192.168.1.2: icmp_seq=3 ttl=64 time=0.057 ms
--- 192.168.1.2 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2044ms
rtt min/avg/max/mdev = 0.057/0.177/0.413/0.166 ms
# 
# ping 192.168.1.3 -c 3
PING 192.168.1.3 (192.168.1.3) 56(84) bytes of data.
From 192.168.1.4 icmp_seq=1 Destination Host Unreachable
From 192.168.1.4 icmp_seq=2 Destination Host Unreachable
--- 192.168.1.3 ping statistics ---
3 packets transmitted, 0 received, +3 errors, 100% packet loss, time 2068ms
pipe 3
# 
```

## 跨主机连通性
### 环境
##### host1 172.29.101.123  
```
网桥:  ovs0      

容器:    
con6  192.168.1.2   
con7  192.168.1.3   
con8  192.168.1.4   
```
创建方式依上

##### host2 172.29.101.82
```
网桥: ovs1

容器: con11
```
准备环境
```sh
创建网桥
ovs-vsctl add-br ovs1

创建容器
docker run -itd --name con11 --net=none ubuntu:14.04 /bin/bash

挂到ovs0网桥
ovs-docker add-port ovs1 eth0 con11 --ipaddress=192.168.1.6/24
```

查看网桥ovs1
```sh
[root@compute82 /]# ovs-vsctl show
380ce027-8edf-4844-8e89-a6b9c1adaff3
    Bridge "ovs1"
        Port "0384251973e64_l"
            Interface "0384251973e64_l"
        Port "ovs1"
            Interface "ovs1"
                type: internal
    ovs_version: "2.8.2"
```

### 设置vxlan
在host1上
```sh
[root@controller /]# ovs-vsctl add-port ovs0 vxlan1 -- set interface vxlan1 type=vxlan options:remote_ip=172.29.101.82 options:key=flow
[root@controller /]# 
[root@controller /]# ovs-vsctl show
21e4d4c5-cadd-4dac-b025-c20b8108ad09
    Bridge "ovs0"
        Port "b167e3dcf8db4_l"
            tag: 100
            Interface "b167e3dcf8db4_l"
        Port "f1c0a9d0994d4_l"
            tag: 100
            Interface "f1c0a9d0994d4_l"
        Port "121c6b2f221c4_l"
            tag: 200
            Interface "121c6b2f221c4_l"
        Port "ovs0"
            Interface "ovs0"
                type: internal
        Port "vxlan1"
            Interface "vxlan1"
                type: vxlan
                options: {key=flow, remote_ip="172.29.101.82"}
    ovs_version: "2.8.2"
```
在host2上
```sh
[root@compute82 /]# ovs-vsctl add-port ovs1 vxlan1 -- set interface vxlan1 type=vxlan options:remote_ip=172.29.101.123 options:key=flow
[root@compute82 /]# 
[root@compute82 /]# ovs-vsctl show
380ce027-8edf-4844-8e89-a6b9c1adaff3
    Bridge "ovs1"
        Port "0384251973e64_l"
            Interface "0384251973e64_l"
        Port "vxlan1"
            Interface "vxlan1"
                type: vxlan
                options: {key=flow, remote_ip="172.29.101.123"}
        Port "ovs1"
            Interface "ovs1"
                type: internal
    ovs_version: "2.8.2"
```


### 设置vlan tag 

```sh
ovs-vsctl set port 0384251973e64_l tag=100
```

### 连通性测试
```sh
[root@compute82 /]# docker exec -ti con11 bash
root@c82da61bf925:/# ping 192.168.1.2
PING 192.168.1.2 (192.168.1.2) 56(84) bytes of data.
64 bytes from 192.168.1.2: icmp_seq=1 ttl=64 time=0.161 ms
64 bytes from 192.168.1.2: icmp_seq=2 ttl=64 time=0.206 ms
^C
--- 192.168.1.2 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1000ms
root@c82da61bf925:/# 
root@c82da61bf925:/# ping 192.168.1.3
PING 192.168.1.3 (192.168.1.3) 56(84) bytes of data.
^C
--- 192.168.1.3 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss, time 2027ms
root@c82da61bf925:/# 
root@c82da61bf925:/# exit
```

### 结论
vxlan只能连通两台机器的ovs上同一个网段的容器，无法连通ovs上不同网段的容器。如果需要连通不同网段的容器，接下来我们尝试通过ovs的流表来解决这个问题。

# OpenFlow
### flow table
支持openflow的交换机中可能包含多个flow table。每个flow table包含多条规则，每条规则包含匹配条件和执行动作。flow table中的每条规则有优先级，优先级高的优先匹配，匹配到规则以后，执行action，如果匹配失败，按优先级高低，继续匹配下一条。如果都不匹配，每张表会有默认的动作，一般为drop或者转给下一张流表。

### 实践
#### 环境
 host1 172.29.101.123  
```sh
网桥:  ovs0      

容器:    
con6  192.168.1.2     tag=100
con7  192.168.1.3     tag=100
```
 host2 172.29.101.82
```sh
网桥: ovs1

容器:  
con9:  192.168.2.2    tag=100
con10：192.168.2.3    tag=100
con11: 192.168.1.5    tag=100
```
### 查看默认流表
在host1上查看默认流表
```sh
[root@controller msxu]# ovs-ofctl dump-flows ovs0
 cookie=0x0, duration=27858.050s, table=0, n_packets=5253660876, n_bytes=371729202788, priority=0 actions=NORMAL
```
在容器con6中ping con7，网络连通
```sh
[root@controller /]# docker exec -ti con6 bash
root@9ccc5c5664f9:/# 
root@9ccc5c5664f9:/# ping 192.168.1.3
PING 192.168.1.3 (192.168.1.3) 56(84) bytes of data.
64 bytes from 192.168.1.3: icmp_seq=1 ttl=64 time=0.613 ms
64 bytes from 192.168.1.3: icmp_seq=2 ttl=64 time=0.066 ms
--- 192.168.1.3 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1058ms
rtt min/avg/max/mdev = 0.066/0.339/0.613/0.274 ms
root@9ccc5c5664f9:/# 
```
删除默认流表
```sh
[root@controller /]# ovs-ofctl del-flows ovs0
[root@controller /]# 
[root@controller /]# ovs-ofctl dump-flows ovs0
[root@controller /]# 
```
测试网络连通性，发现网络已经不通
```sh
[root@controller /]# docker exec -ti con6 bash
root@9ccc5c5664f9:/# 
root@9ccc5c5664f9:/# ping 192.168.1.3
PING 192.168.1.3 (192.168.1.3) 56(84) bytes of data.
^C
--- 192.168.1.3 ping statistics ---
2 packets transmitted, 0 received, 100% packet loss, time 1025ms
root@9ccc5c5664f9:/# 
```

### 添加流表
如果要con6和con7能够通信，需要建立规则，让ovs转发对应的数据

查看con6和con7在ovs上的网络端口
```sh
[root@controller /]# ovs-vsctl show
21e4d4c5-cadd-4dac-b025-c20b8108ad09
    Bridge "ovs0"
        Port "f1c0a9d0994d4_l"
            tag: 100
            Interface "f1c0a9d0994d4_l"
        Port "121c6b2f221c4_l"
            tag: 100
            Interface "121c6b2f221c4_l"
        Port "ovs0"
            Interface "ovs0"
                type: internal
        Port "vxlan1"
            Interface "vxlan1"
                type: vxlan
                options: {key=flow, remote_ip="172.29.101.82"}
    ovs_version: "2.8.2"
[root@controller /]# ovs-vsctl list interface f1c0a9d0994d4_l |grep ofport
ofport              : 3
ofport_request      : []
[root@controller /]# 
[root@controller /]# ovs-vsctl list interface 121c6b2f221c4_l |grep ofport
ofport              : 4
ofport_request      : []
```
添加规则：
```sh
[root@controller /]#ovs-ofctl add-flow ovs0 "priority=1,in_port=3,actions=output:4"
[root@controller /]#ovs-ofctl add-flow ovs0 "priority=2,in_port=4,actions=output:3"
[root@controller /]# ovs-ofctl dump-flows ovs0
 cookie=0x0, duration=60.440s, table=0, n_packets=0, n_bytes=0, priority=1,in_port="f1c0a9d0994d4_l" actions=output:"121c6b2f221c4_l"
 cookie=0x0, duration=50.791s, table=0, n_packets=0, n_bytes=0, priority=1,in_port="121c6b2f221c4_l" actions=output:"f1c0a9d0994d4_l"
[root@controller /]#
```
测试连通性：con6和con7已通
```sh
[root@controller msxu]# docker exec -ti con6 bash
root@9ccc5c5664f9:/# ping 192.168.1.3
PING 192.168.1.3 (192.168.1.3) 56(84) bytes of data.
64 bytes from 192.168.1.3: icmp_seq=1 ttl=64 time=0.924 ms
64 bytes from 192.168.1.3: icmp_seq=2 ttl=64 time=0.058 ms
^C
--- 192.168.1.3 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1057ms
rtt min/avg/max/mdev = 0.058/0.491/0.924/0.433 ms
root@9ccc5c5664f9:/# 
```
设置一条优先级高的规则：
```sh
[root@controller /]# ovs-ofctl add-flow ovs0 "priority=2,in_port=4,actions=drop"
[root@controller /]# 
[root@controller /]# docker exec -ti con6 bash
root@9ccc5c5664f9:/# 
root@9ccc5c5664f9:/# ping  192.168.1.3
PING 192.168.1.3 (192.168.1.3) 56(84) bytes of data.
^C
--- 192.168.1.3 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss, time 2087ms
root@9ccc5c5664f9:/# 
root@9ccc5c5664f9:/# 
```
流表中的规则是有优先级的，priority数值越大，优先级越高。流表中，优先级高的优先匹配，并执行匹配规则的actions。如果不匹配，继续匹配优先级低的下一条。

### 跨网段连通
在上一个vxlan的实践中，通过设置vxlan可以打通两个机器上的ovs，但我们提到两个机器ovs上的容器得在同一个网段上才能通信。

在ip为192.168.2.2的con9上ping另一台机上的con6 192.168.1.2
```sh
[root@compute82 /]# docker exec -ti con9 bash
root@b55602aad0ac:/# 
root@b55602aad0ac:/# ping 192.168.1.2
connect: Network is unreachable
root@b55602aad0ac:/# 
```
#### 添加流表规则：  
在host1上：
```sh
[root@controller /]# ovs-ofctl add-flow ovs0 "priority=4,in_port=6,actions=output:3"
[root@controller /]# 
[root@controller /]# ovs-ofctl add-flow ovs0 "priority=4,in_port=3,actions=output:6"
[root@controller /]# ovs-ofctl dump-flows ovs0
 cookie=0x0, duration=3228.737s, table=0, n_packets=7, n_bytes=490, priority=1,in_port="f1c0a9d0994d4_l" actions=output:"121c6b2f221c4_l"
 cookie=0x0, duration=3215.544s, table=0, n_packets=0, n_bytes=0, priority=1,in_port="121c6b2f221c4_l" actions=output:"f1c0a9d0994d4_l"
 cookie=0x0, duration=3168.297s, table=0, n_packets=9, n_bytes=546, priority=2,in_port="121c6b2f221c4_l" actions=drop
 cookie=0x0, duration=12.024s, table=0, n_packets=0, n_bytes=0, priority=4,in_port=vxlan1 actions=output:"f1c0a9d0994d4_l"
 cookie=0x0, duration=3.168s, table=0, n_packets=0, n_bytes=0, priority=4,in_port="f1c0a9d0994d4_l" actions=output:vxlan1

```
在host2上
```sh
[root@compute82 /]# ovs-ofctl add-flow ovs1 "priority=1,in_port=1,actions=output:6"
[root@compute82 /]# 
[root@compute82 /]# ovs-ofctl add-flow ovs1 "priority=1,in_port=6,actions=output:1"
[root@compute82 /]# ovs-ofctl dump-flows ovs1
 cookie=0x0, duration=1076.522s, table=0, n_packets=27, n_bytes=1134, priority=1,in_port="0384251973e64_l" actions=output:vxlan1
 cookie=0x0, duration=936.403s, table=0, n_packets=0, n_bytes=0, priority=1,in_port=vxlan1 actions=output:"0384251973e64_l"
 cookie=0x0, duration=70205.443s, table=0, n_packets=7325, n_bytes=740137, priority=0 actions=NORMAL

```
#### 测试连通性
在host2 con9上ping 192.168.1.2
```sh
[root@compute82 /]# docker exec -ti con9 bash
root@b55602aad0ac:/# 
root@b55602aad0ac:/# ping 192.168.1.2
connect: Network is unreachable
root@b55602aad0ac:/# 
```
发现网络并不通，查看发现路由规则有问题，添加默认路由规则，注意这里需要已privileged权限进入容器
```sh
[root@compute82 /]# docker exec --privileged -ti con9 bash
root@b55602aad0ac:/# 
root@b55602aad0ac:/# route -n
Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
192.168.2.0     0.0.0.0         255.255.255.0   U     0      0        0 eth0
root@b55602aad0ac:/# route add default dev eth0
root@b55602aad0ac:/# 
root@b55602aad0ac:/# route -n
Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
0.0.0.0         0.0.0.0         0.0.0.0         U     0      0        0 eth0
192.168.2.0     0.0.0.0         255.255.255.0   U     0      0        0 eth0
root@b55602aad0ac:/# 
```
在host1和host2的容器中都添加好路由规则后，测试连通性
```sh
[root@compute82 /]# docker exec --privileged -ti con9 bash
root@b55602aad0ac:/# 
root@b55602aad0ac:/# ping 192.168.1.2
PING 192.168.1.2 (192.168.1.2) 56(84) bytes of data.
64 bytes from 192.168.1.2: icmp_seq=1 ttl=64 time=1.16 ms
64 bytes from 192.168.1.2: icmp_seq=2 ttl=64 time=0.314 ms
^C
--- 192.168.1.2 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1002ms
rtt min/avg/max/mdev = 0.314/0.739/1.165/0.426 ms
```
已成功通过ovs，vxlan打通两台机器上不同网段容器


# OVN实践
有了ovs相关的实践，就具备了一定的基础，下面就可以进一步去了解ovn，ovn很重要的一点就是理解逻辑交换机,ovn是管控层面的，比如每台机器上都起了一个ovs交换机（软交换机，或者相对于逻辑交换机称之为物理交换机) 分布在不同机器上的虚拟机想要在一个子网下，那么我们创建一个逻辑交换机，把机器interface与之逻辑上关联在一起即可，最终ovn会下发流表使其在一个子网下。

## 基本使用
### 逻辑面（控制面）
创建俩逻辑交换机
```
$ ovn-nbctl ls-add sw0
$ ovn-nbctl lsp-add sw0 sw0-port1
$ ovn-nbctl lsp-set-addresses sw0-port1 "50:54:00:00:00:01 192.168.0.2"

$ ovn-nbctl ls-add sw1
$ ovn-nbctl lsp-add sw1 sw1-port1
$ ovn-nbctl lsp-set-addresses sw1-port1 "50:54:00:00:00:03 11.0.0.2"
```

创建一个逻辑路由器，并把两个交换机连接到路由器上
```
$ ovn-nbctl lr-add lr0
$ ovn-nbctl lrp-add lr0 lrp0 00:00:00:00:ff:01 192.168.0.1/24
$ ovn-nbctl lsp-add sw0 lrp0-attachment
$ ovn-nbctl lsp-set-type lrp0-attachment router
$ ovn-nbctl lsp-set-addresses lrp0-attachment 00:00:00:00:ff:01
$ ovn-nbctl lsp-set-options lrp0-attachment router-port=lrp0
$ ovn-nbctl lrp-add lr0 lrp1 00:00:00:00:ff:02 11.0.0.1/24

$ ovn-nbctl lsp-add sw1 lrp1-attachment
$ ovn-nbctl lsp-set-type lrp1-attachment router
$ ovn-nbctl lsp-set-addresses lrp1-attachment 00:00:00:00:ff:02
$ ovn-nbctl lsp-set-options lrp1-attachment router-port=lrp1
```

查看逻辑配置：
```
$ ovn-nbctl show
    switch 1396cf55-d176-4082-9a55-1c06cef626e4 (sw1)
        port lrp1-attachment
            addresses: ["00:00:00:00:ff:02"]
        port sw1-port1
            addresses: ["50:54:00:00:00:03 11.0.0.2"]
    switch 2c9d6d03-09fc-4e32-8da6-305f129b0d53 (sw0)
        port lrp0-attachment
            addresses: ["00:00:00:00:ff:01"]
        port sw0-port1
            addresses: ["50:54:00:00:00:01 192.168.0.2"]
    router f8377e8c-f75e-4fc8-8751-f3ea03c6dd98 (lr0)
        port lrp0
            mac: "00:00:00:00:ff:01"
            networks: ["192.168.0.1/24"]
        port lrp1
            mac: "00:00:00:00:ff:02"
            networks: ["11.0.0.1/24"]
```

使用ovn-trace:
```
$ ovn-trace --minimal sw0 'inport == "sw0-port1" \
> && eth.src == 50:54:00:00:00:01 && ip4.src == 192.168.0.2 \
> && eth.dst == 00:00:00:00:ff:01 && ip4.dst == 11.0.0.2 \
> && ip.ttl == 64'

# ip,reg14=0x1,vlan_tci=0x0000,dl_src=50:54:00:00:00:01,dl_dst=00:00:00:00:ff:01,nw_src=192.168.0.2,nw_dst=11.0.0.2,nw_proto=0,nw_tos=0,nw_ecn=0,nw_ttl=64
ip.ttl--;
eth.src = 00:00:00:00:ff:02;
eth.dst = 50:54:00:00:00:03;
output("sw1-port1");
```
这里我们指定了源地址与源端口，再指定目的ip，最后会输出告诉我们从交换机哪个端口发出去了。

### 重点: 把容器挂到逻辑交换机上
ovs-docker这个工具里有这样一句：
```
ip link add "${PORTNAME}_l" type veth peer name "${PORTNAME}_c"

# Add one end of veth to OVS bridge.
if ovs_vsctl --may-exist add-port "$BRIDGE" "${PORTNAME}_l" \
       -- set interface "${PORTNAME}_l" \
```
先创建了一个设备对，然后把设备对一端设置成ovs上的一个interface, 这样容器与ovs就关联上了，再把这个ovs上的port与ovn逻辑子网进行关联即可，请看具体例子：


启动容器后是先要把容器设备对的一端挂在物理交换机上，然后通过设置iface-id来与逻辑交换机进行关联。

```
ovs-vsctl --may-exist add-port sw0 port0 -- set interface port0 # 把docker挂到ovs上
ovs-vsctl set Interface port0 external_ids:iface-id=lpor0       # 通过iface-id关联到逻辑端口上
```

具体代码可以查看[这里](https://github.com/fanux/ops/blob/master/ovs/ovn/lib/ovn.sh) 这封装了一些基操作

一些具体实现：[使用教程](https://github.com/fanux/ops/blob/master/ovs/ovn/l2_basic.sh)

## 逻辑子网
这里创建四个端口，都挂在ovs br-int网桥上，但是分别属于不同的逻辑交换机，这样不同的逻辑交换机没有连接路由器的情况下是不通的，同一个逻辑子网下端口可以互通。
```
ls-create sw0
ls-add-port sw0 sw0-port1 00:00:00:00:00:01 192.168.33.10/24
ls-add-port sw0 sw0-port2 00:00:00:00:00:02 192.168.33.20/24

ls-create sw1
ls-add-port sw1 sw1-port1 00:00:00:00:00:03 192.168.33.30/24
ls-add-port sw1 sw1-port2 00:00:00:00:00:04 192.168.33.40/24

ovs-add-port br-int lport1 sw0-port1 192.168.33.1
ovs-add-port br-int lport2 sw0-port2 192.168.33.1
ovs-add-port br-int lport3 sw1-port1 192.168.33.1
ovs-add-port br-int lport4 sw1-port2 192.168.33.1

ip netns exec lport1-ns ip addr
ip netns exec lport2-ns ip addr
ip netns exec lport3-ns ip addr
ip netns exec lport4-ns ip addr

ip netns exec lport1-ns ping -c3 192.168.33.20
ofport=$(ovs-vsctl list interface lport1 | awk '/ofport /{print $3}')
ovs-appctl ofproto/trace br-int in_port=$ofport,dl_src=00:00:00:00:00:01,dl_dst=00:00:00:00:00:02 -generate

ip netns exec lport1-ns ping -c3 192.168.33.30
ovs-appctl ofproto/trace br-int in_port=$ofport,dl_src=00:00:00:00:00:01,dl_dst=00:00:00:00:00:03 -generate
```

这里ls-create ls-add-port和ovs-add-port是简单封装了一下命令：

ls-create ls-add-port:
```
ls-create() {
    ovn-nbctl --may-exist ls-add $switch
}

ls-add-port() {
    switch=$1
    port=$2
    mac=$3
    cidr=$4

    # 逻辑交换机上创建逻辑端口
    ovn-nbctl --may-exist lsp-add $switch $port

    # 给逻辑端口设置mac地址
    ovn-nbctl lsp-set-addresses $port $mac

    # 仅允许该端口源或目的mac为对应地址
    ovn-nbctl lsp-set-port-security $port $mac $cidr
}
```

穿件网络ns，把interface塞到ns中，再与物理端口相关联，然后给interface配置IP
```
ovs-add-port() {
    bridge=$1
    port=$2
    lport=$3
    gateway=$4

    # 创建一个网络ns
    ip netns add $port-ns
    # set interface 很重要，要不然就会只有端口没有interface,所以无法把它塞到ns中
    ovs-vsctl --may-exist add-port $bridge $port -- set interface $port type=internal
    if [ ! -z "$lport" ]; then
        # 把逻辑端口与ovs端口进行关联
        ovs-vsctl set Interface $port external_ids:iface-id=$lport
    fi

    pscount=$(ovn-nbctl lsp-get-port-security $lport | wc -l)
    if [ $pscount = 2 ]; then
        mac=$(ovn-nbctl lsp-get-port-security $lport | head -n 1)
        cidr=$(ovn-nbctl lsp-get-port-security $lport | tail -n 1)
        ip link set $port netns $port-ns
        # ip netns exec $port-ns ip link set dev $port name eth0
        ip netns exec $port-ns ip link set $port address $mac
        ip netns exec $port-ns ip addr add $cidr dev $port
        ip netns exec $port-ns ip link set $port up
        if [ ! -z "$gateway" ]; then
            ip netns exec $port-ns ip route add default via $gateway
        fi
    fi
}
```
所以在实现专有网络时只需要创建不同的逻辑交换机即可，不通过路由相连专有网络之间就会相互隔离。

## IP管理（DHCP）
## 静态IP配置
这里给ovn逻辑端口配置一个静态的IP，然后ovn会模拟DHCP协议给端口响应完成地址配置
```
ovn-nbctl lr-add user1
ovn-nbctl ls-add vpc1

#创建路由连接到vpc1端口，并分配mac 02:ac:10:ff:34:01 IP 172.66.1.10
ovn-nbctl lrp-add user1 user1-vpc1 02:ac:10:ff:34:01 172.66.1.10/24

ovn-nbctl lsp-add vpc1 vpc1-user1
ovn-nbctl lsp-set-type vpc1-user1 router
ovn-nbctl lsp-set-addresses vpc1-user1 02:ac:10:ff:34:01
ovn-nbctl lsp-set-options vpc1-user1 router-port=user1-vpc1

#创建路由连接到vpc2端口，并分配mac 02:ac:10:ff:34:02 IP 172.77.1.10
ovn-nbctl lrp-add user1 user1-vpc2 02:ac:10:ff:34:02 172.77.1.10/24

ovn-nbctl lsp-add vpc1 vpc1-vm1
# 这里给逻辑端口配置IP地址
ovn-nbctl lsp-set-addresses vpc1-vm1 "02:ac:10:ff:01:30 172.66.1.107" 
# ovn-nbctl lsp-set-port-security vpc1-vm1 "02:ac:10:ff:01:30 172.66.1.101"

options=$(ovn-nbctl create DHCP_Options cidr=172.66.1.0/24 \
options="\"server_id\"=\"172.66.1.10\" \"server_mac\"=\"02:ac:10:ff:34:01\" \
\"lease_time\"=\"3600\" \"router\"=\"172.66.1.10\"")

echo "DHCP options is: " $options
ovn-nbctl lsp-set-dhcpv4-options vpc1-vm1 $options
ovn-nbctl lsp-get-dhcpv4-options vpc1-vm1

ip netns add vm1
ovs-vsctl add-port br-int vm1 -- set interface vm1 type=internal
ip link set vm1 address 02:ac:10:ff:01:30
ip link set vm1 netns vm1
ovs-vsctl set Interface vm1 external_ids:iface-id=vpc1-vm1
# 通过DHCP即可拿到地址
ip netns exec vm1 dhclient vm1
ip netns exec vm1 ip addr show vm1
ip netns exec vm1 ip route show

clean() {
    ip netns del vm1
    ovn-nbctl ls-del vpc1
    ovs-vsctl del-port br-int vm1
}
```

## 动态获取IP地址
[参考文章](https://developers.redhat.com/blog/2018/09/03/ovn-dynamic-ip-address-management/)

ovn支持管理你的IP地址，只需要指定一个子网，就会给借口分配未被占用的IP地址：

大部分操作与静态IP一样，注意下面几个重点注释地方：
```
ovn-nbctl lr-add user1
ovn-nbctl ls-add vpc1
# [重点] 需要other_config，否则不会分配地址
ovn-nbctl set Logical_Switch vpc1 other_config:subnet=172.66.1.10/24

#创建路由连接到vpc1端口，并分配mac 02:ac:10:ff:34:01 IP 172.66.1.10
ovn-nbctl lrp-add user1 user1-vpc1 02:ac:10:ff:34:01 172.66.1.10/24

ovn-nbctl lsp-add vpc1 vpc1-user1
ovn-nbctl lsp-set-type vpc1-user1 router
ovn-nbctl lsp-set-addresses vpc1-user1 02:ac:10:ff:34:01
ovn-nbctl lsp-set-options vpc1-user1 router-port=user1-vpc1

ovn-nbctl lsp-add vpc1 vpc1-vm1
# 【重点】这里不指定具体地址，而使用dynamic
ovn-nbctl lsp-set-addresses vpc1-vm1 "02:ac:10:ff:01:30 dynamic"
# ovn-nbctl lsp-set-addresses vpc1-vm1 "dynamic"
# ovn-nbctl lsp-set-port-security vpc1-vm1 "02:ac:10:ff:01:30 172.66.1.106"

options=$(ovn-nbctl create DHCP_Options cidr=172.66.1.0/24 \
options="\"server_id\"=\"172.66.1.10\" \"server_mac\"=\"02:ac:10:ff:34:01\" \
\"lease_time\"=\"3600\" \"router\"=\"172.66.1.10\"")

echo "DHCP options is: " $options
ovn-nbctl lsp-set-dhcpv4-options vpc1-vm1 $options
ovn-nbctl lsp-get-dhcpv4-options vpc1-vm1
# 这里可以看到分配到的地址
ovn-nbctl list logical_switch_port

ip netns add vm1
ovs-vsctl add-port br-int vm1 -- set interface vm1 type=internal
ip link set vm1 address 02:ac:10:ff:01:30
ip link set vm1 netns vm1
ovs-vsctl set Interface vm1 external_ids:iface-id=vpc1-vm1
# 通过dhclient就可以获取到地址了
ip netns exec vm1 dhclient vm1
ip netns exec vm1 ip addr show vm1
ip netns exec vm1 ip route show
```

可以查看到已分配的地址：
```
$ ovn-nbctl list logical_switch_port
_uuid : 2d1fe408-f119-48d6-88c9-dff237c92856
addresses : [dynamic]
dhcpv4_options : []
dhcpv6_options : []
dynamic_addresses : "0a:00:00:00:00:01 192.168.0.2 fdd6:8cf5:9dc2:c30a:800:ff:fe00:1"
enabled : []
external_ids : {}
name : "port1"
options : {}
parent_name : []
port_security : []
tag : []
tag_request : []
type : ""
up : false

_uuid : 43867394-8d3b-4e36-a90d-5f635d6a084c
addresses : ["00:ac:00:ff:01:01 dynamic"]
dhcpv4_options : []
dhcpv6_options : []
dynamic_addresses : "00:ac:00:ff:01:01 192.168.0.3 fdd6:8cf5:9dc2:c30a:2ac:ff:feff:101"
enabled : []
external_ids : {}
name : "port2"
options : {}
parent_name : []
port_security : []
tag : []
tag_request : []
type : ""
up : false
```

## 经典网络实现
![](/kube-ovn-classics.jpg)
```
ovn-nbctl lsp-add out outs-wan
ovn-nbctl lsp-set-addresses outs-wan unknown
ovn-nbctl lsp-set-type outs-wan localnet # 连接物理网络端口类型
ovn-nbctl lsp-set-options outs-wan network_name=wanNet # 做bridge mapping时需要
```

```
ovs-vsctl add-br br-eth
ovs-vsctl set Open_vSwitch . external-ids:ovn-bridge-mappings=wanNet:br-eth
ovs-vsctl add-port br-eth eth0

#配置网桥IP
ip link set br-eth up
ip addr add 192.168.66.111/23 dev br-eth
```

把虚拟机关联到逻辑网桥上，这样物理网卡与虚拟机就在一个网桥上了
```
ovs-vsctl set Interface vm1 external_ids:iface-id=vm1
```

## FIP实现
![](/img/kube-ovn-vpc.png)
其它部分的链接参考上文，这里主要是路由相关的操作

vm想要出网那么必须要进行源地址转换，就和我们访问google一样，那我们机器的192.168.x.x的地址就会在路由器上被转化
```
#对vpc1
ovn-nbctl -- --id=@nat create nat type="snat" logical_ip=172.66.1.0/24 \
external_ip=192.168.66.45 -- add logical_router gateway_route nat @nat
#会返回uuid
56ad6c5b-8417-4314-95c4-a0d780b5ef0b
```
这里66.45是我们链接物理网络的一个地址，告诉路由器使用该地址进行转换

实现FIP其实就是snat dnat都做：
```
#对vm3 172.66.1.103  绑定外网 192.168.66.46 
ovn-nbctl -- --id=@nat create nat type="dnat_and_snat" logical_ip=172.66.1.103 \
external_ip=192.168.66.46 -- add logical_router gateway_route nat @nat
```

# ovn ovs与CNI对接
ovn ovs与CNI对接包含两个部分，CNI插件仅需要把容器的设备对一端挂载到ovs网桥上然后配置好地址,与逻辑端口做好映射. 主要是物理面的功能，逻辑管控层面就可以通过CRD进行创建，所以重点是对ovn ovs CNI本身的掌握。
