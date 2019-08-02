+++
author = "fanux"
date = "2019-07-30T10:54:24+02:00"
draft = false
title = "彻底理解 kubernetes CNI"
tags = ["network","dev"]
comments = true     # set false to hide Disqus comments
banner = "CNI.png"
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

CNI接口很简单，特别一些新手一定有克服恐惧心里，和我一探究竟，本文结合原理与实践，认真读下来一定会对原理理解非常透彻。
<!--more-->

![](https://sealyun.com/CNI.png)

## 环境介绍
我们安装kubernetes时先不安装CNI. 如果使用了[sealyun离线包](https://store.lameleg.com) 那么修改下 `kube/conf/master.sh` 

只留如下内容即可：
```
[root@helix105 shell]# cat master.sh 
kubeadm init --config ../conf/kubeadm.yaml
mkdir ~/.kube
cp /etc/kubernetes/admin.conf ~/.kube/config

kubectl taint nodes --all node-role.kubernetes.io/master-
```

清空CNI相关目录：
```
rm -rf /opt/cni/bin/*
rm -rf /etc/cni/net.d/*
```

启动kubernetes, 如果已经装过那么kubeadm reset一下:
```
cd kube/shell && sh init.sh && sh master.sh
```

此时你的节点是notready的，你的coredns也没有办法分配到地址：
```
[root@helix105 shell]# kubectl get pod -n kube-system -o wide
NAME                                            READY   STATUS    RESTARTS   AGE   IP              NODE                    NOMINATED NODE   READINESS GATES
coredns-5c98db65d4-5fh6c                        0/1     Pending   0          54s   <none>          <none>                  <none>           <none>
coredns-5c98db65d4-dbwmq                        0/1     Pending   0          54s   <none>          <none>                  <none>           <none>
kube-controller-manager-helix105.hfa.chenqian   1/1     Running   0          19s   172.16.60.105   helix105.hfa.chenqian   <none>           <none>
kube-proxy-k74ld                                1/1     Running   0          54s   172.16.60.105   helix105.hfa.chenqian   <none>           <none>
kube-scheduler-helix105.hfa.chenqian            1/1     Running   0          14s   172.16.60.105   helix105.hfa.chenqian   <none>           <none>
[root@helix105 shell]# kubectl get node
NAME                    STATUS     ROLES    AGE   VERSION
helix105.hfa.chenqian   NotReady   master   86s   v1.15.0
```

## 安装CNI
> 创建CNI配置文件

```
$ mkdir -p /etc/cni/net.d
$ cat >/etc/cni/net.d/10-mynet.conf <<EOF
{
	"cniVersion": "0.2.0",
	"name": "mynet",
	"type": "bridge",
	"bridge": "cni0",
	"isGateway": true,
	"ipMasq": true,
	"ipam": {
		"type": "host-local",
		"subnet": "10.22.0.0/16",
		"routes": [
			{ "dst": "0.0.0.0/0" }
		]
	}
}
EOF
$ cat >/etc/cni/net.d/99-loopback.conf <<EOF
{
	"cniVersion": "0.2.0",
	"name": "lo",
	"type": "loopback"
}
EOF
```
这里两个配置一个是给容器塞一个网卡挂在网桥上的，另外一个配置负责撸(本地回环)。。

配置完后会发现节点ready:
```
[root@helix105 shell]# kubectl get node
NAME                    STATUS   ROLES    AGE   VERSION
helix105.hfa.chenqian   Ready    master   15m   v1.15.0
```

但是coredns会一直处于ContainerCreating状态,是因为bin文件还没有:
```
failed to find plugin "bridge" in path [/opt/cni/bin]
```

[plugins](https://github.com/containernetworking/plugins)里实现了很多的CNI,如我们上面配置的bridge.
```
$ cd $GOPATH/src/github.com/containernetworking/plugins
$ ./build_linux.sh
$ cp bin/* /opt/cni/bin
$ ls bin/
bandwidth  dhcp      flannel      host-local  loopback  portmap  sbr     tuning
bridge     firewall  host-device  ipvlan      macvlan   ptp      static  vlan
```
这里有很多二进制，我们学习的话不需要关注所有的，就看ptp(就简单的创建了设备对)或者bridge

再看coredns已经能分配到地址了：
```
[root@helix105 plugins]# kubectl get pod -n kube-system -o wide
NAME                                            READY   STATUS    RESTARTS   AGE     IP              NODE                    NOMINATED NODE   READINESS GATES
coredns-5c98db65d4-5fh6c                        1/1     Running   0          3h10m   10.22.0.8       helix105.hfa.chenqian   <none>           <none>
coredns-5c98db65d4-dbwmq                        1/1     Running   0          3h10m   10.22.0.9
```

看一下网桥,cni0上挂了两个设备,与我们上面的cni配置里配置的一样，type字段指定用哪个bin文件，bridge字段指定网桥名：
```
[root@helix105 plugins]# brctl show
bridge name	bridge id		STP enabled	interfaces
cni0		8000.8ef6ac49c2f7	no		veth1b28b06f
            							veth1c093940
```

## 原理
为了更好理解kubelet干嘛了，我们可以找一个脚本来解释 [script](https://github.com/containernetworking/cni/tree/master/scripts) 这个脚本也可以用来测试你的CNI：

为了易读，我删除一些不重要的东西,原版脚本可以在连接中去拿

```
# 先创建一个容器，这里只为了拿到一个net namespace
contid=$(docker run -d --net=none golang:1.12.7 /bin/sleep 10000000) 
pid=$(docker inspect -f '{{ .State.Pid }}' $contid)
netnspath=/proc/$pid/ns/net # 这个我们需要

kubelet启动pod时也是创建好容器就有了pod的network namespaces，再去把ns传给cni 让cni去配置

./exec-plugins.sh add $contid $netnspath # 传入两个参数给下一个脚本，containerid和net namespace路径

docker run --net=container:$contid $@
```

```
NETCONFPATH=${NETCONFPATH-/etc/cni/net.d}

function exec_plugins() {
        i=0
        # 获取容器id和网络ns
        contid=$2 
        netns=$3

        # 这里设置了几个环境变量，CNI命令行工具就可以获取到这些参数
        export CNI_COMMAND=$(echo $1 | tr '[:lower:]' '[:upper:]')
        export PATH=$CNI_PATH:$PATH # 这个指定CNI bin文件的路径
        export CNI_CONTAINERID=$contid 
        export CNI_NETNS=$netns

        for netconf in $(echo $NETCONFPATH/10-mynet.conf | sort); do
                name=$(jq -r '.name' <$netconf)
                plugin=$(jq -r '.type' <$netconf) # CNI配置文件的type字段对应二进制程序名
                export CNI_IFNAME=$(printf eth%d $i) # 容器内网卡名

                # 这里执行了命令行工具
                res=$($plugin <$netconf) # 这里把CNI的配置文件通过标准输入也传给CNI命令行工具
                if [ $? -ne 0 ]; then
                        # 把结果输出到标准输出，这样kubelet就可以拿到容器地址等一些信息
                        errmsg=$(echo $res | jq -r '.msg')
                        if [ -z "$errmsg" ]; then
                                errmsg=$res
                        fi

                        echo "${name} : error executing $CNI_COMMAND: $errmsg"
                        exit 1
                let "i=i+1"
        done
}
```

总结一下：
```
         CNI配置文件
         容器ID
         网络ns
kubelet -------------->  CNI command
   ^                        |
   |                        |
   +------------------------+
       结果标准输出
```

### bridge CNI实现
既然这么简单，那么就可以去看看实现了：

[bridge CNI代码](https://github.com/containernetworking/plugins/tree/master/plugins/main/bridge)

```
//cmdAdd 负责创建网络
func cmdAdd(args *skel.CmdArgs) error 

//入参数都已经写到这里面了，前面的参数从环境变量读取的，CNI配置从stdin读取的
type CmdArgs struct {
	ContainerID string
	Netns       string
	IfName      string
	Args        string
	Path        string
	StdinData   []byte
}
```
所以CNI配置文件除了name type这些特定字段，你自己也可以加自己的一些字段.然后自己去解析

然后啥事都得靠自己了

```
//这里创建了设备对，并挂载到cni0王桥上
hostInterface, containerInterface, err := setupVeth(netns, br, args.IfName, n.MTU, n.HairpinMode, n.Vlan)
```
具体怎么挂的就是调用了[netlink](github.com/vishvananda/netlink) 这个库，sealos在做内核负载时同样用了该库。
```
err := netns.Do(func(hostNS ns.NetNS) error { //创建设备对
	hostVeth, containerVeth, err := ip.SetupVeth(ifName, mtu, hostNS)
    ...
    //配置容器内的网卡名mac地址等
	contIface.Name = containerVeth.Name
	contIface.Mac = containerVeth.HardwareAddr.String()
	contIface.Sandbox = netns.Path()
	hostIface.Name = hostVeth.Name
	return nil
})
...

// 根据index找到宿主机设备对名
hostVeth, err := netlink.LinkByName(hostIface.Name)
...
hostIface.Mac = hostVeth.Attrs().HardwareAddr.String()

// 把宿主机端设备对挂给网桥
if err := netlink.LinkSetMaster(hostVeth, br); err != nil {}

// 设置hairpin mode
if err = netlink.LinkSetHairpin(hostVeth, hairpinMode); err != nil {
}

// 设置vlanid
if vlanID != 0 {
	err = netlink.BridgeVlanAdd(hostVeth, uint16(vlanID), true, true, false, true)
}

return hostIface, contIface, nil
```

最后把结果返回：
```
type Result struct {
	CNIVersion string         `json:"cniVersion,omitempty"`
	Interfaces []*Interface   `json:"interfaces,omitempty"`
	IPs        []*IPConfig    `json:"ips,omitempty"`
	Routes     []*types.Route `json:"routes,omitempty"`
	DNS        types.DNS      `json:"dns,omitempty"`
}

// 这样kubelet就收到返回信息了
func (r *Result) PrintTo(writer io.Writer) error {
	data, err := json.MarshalIndent(r, "", "    ")
	if err != nil {
		return err
	}
	_, err = writer.Write(data)
	return err
}
```
如：
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
      },
      ...
  ],
  "routes": [                                                (optional)
      {
          "dst": "<ip-and-prefix-in-cidr>",
          "gw": "<ip-of-next-hop>"                           (optional)
      },
      ...
  ],
  "dns": {                                                   (optional)
    "nameservers": <list-of-nameservers>                     (optional)
    "domain": <name-of-local-domain>                         (optional)
    "search": <list-of-additional-search-domains>            (optional)
    "options": <list-of-options>                             (optional)
  }
}
```

## 总结
CNI接口层面是非常简单的，所以更多的就是在CNI本身的实现了，懂了上文这些就可以自己去实现一个CNI了,是不是很酷，也会让大家更熟悉网络以更从容的姿态排查网络问题了。

探讨可加QQ群：98488045
