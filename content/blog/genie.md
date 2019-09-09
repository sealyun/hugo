+++
author = "fanux"
date = "2019-07-30T10:54:24+02:00"
draft = false
title = "CNI 小精灵 genie"
tags = ["network","dev"]
comments = true     # set false to hide Disqus comments
banner = "CNI.png"
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

想同时使用多个CNI? 想往容器里塞多张网卡？试试这款CNI插件 [CNI-Genie](https://github.com/cni-genie/CNI-Genie)

<!--more-->

genie可以引用CNI插件，包含默认CNI插件如（bridge macvlan ipvlan loopback）第三方插件如 calico,romana,weave-net

或者一些专用CNI插件如SR-IOV,DPDK等，可以调用在宿主机上的任意CNI插件.

甚至可以让容器一让网卡通过calico分配，另一张网卡走flannel走。

## 为什么要有genie

### 多网卡与CNI任意选择
现在，在node节点上运行的kubelet最多只连接一个CNI插件，即Canal或Romana或Weave。CNI-Genie可以在运行时选用在该特定节点上运行的任何现有CNI插件。

当前Kubernetes无法做到这一点的原因是，当您启动kubelet时，您需要将cni-plugin详细信息作为“kubelet”进程的一部分传递。在这种情况下，您只需选择一个现有的CNI插件，并将其传递给kubelet。如果我们想让某些pod使用Canal网络和其他一组pod来使用weave网络怎么办？这在Kubernetes目前是不可能的。对于任何多网络支持，我们需要对Kubernetes进行更改，这会导致向后兼容性问题。

因此，CNI-Genie“多个CNI插件”功能旨在解决此问题，而无更改及Kubernetes代码

![](https://github.com/cni-genie/CNI-Genie/raw/master/docs/multiple-cni-plugins/what-cni-genie.png)

* 用户可能不同场景对网络需求不同，如我们的一个场景，有些用户需要pod漂移保持ip不变，这样我们让其走ovn网络，有些云原生应用不关心地址变动就走calico
* 访问的网络不同，如一个业务处理业务走的是业务网（千兆），把数据存储到大数据平台走的存储网（25G），这样给容器同时分配两张网卡
* 不同的CNI插件在端口映射，NAT，隧道，中断主机端口/接口的需求方面是不同的

如下：

> 控制面数据面网卡分离

![](https://github.com/cni-genie/CNI-Genie/blob/master/docs/multiple-ips/multi-interface.PNG)

> 高速网络与低速分离

![](https://github.com/cni-genie/CNI-Genie/raw/master/docs/multiple-ips/multi-interface.PNG)

> 流媒体控制流与数据流分离

![](https://github.com/cni-genie/CNI-Genie/raw/master/docs/multiple-ips/multi-interface.PNG)


### Network Attachment Definitions

NetworkAttachmentDefinition 是一个用户可指定网络配置的CRD,然后pod选用该CRD. 这块一般人我不告诉他。

### Smart CNI

根据用户关注的性能指标自动选择CNI,例如占用率，子网数量，延迟，带宽这些“KPI” 去选择CNI

### 网络隔离

为租户提供专用的“物理”网络
在共享的“物理”网络上为不同租户隔离的“逻辑”网络

### 网络级ACL

用于网络级ACL的CNI-Genie网络策略引擎

### 针对给定workload在不同（物理或逻辑）网络之间进行实时切换

价格最小化：随着网络价格的变化，将工作负载动态切换到更便宜的网络
最大化网络利用率：在阈值时动态地将工作负载切换到较不拥挤的网络

![](https://github.com/cni-genie/CNI-Genie/raw/master/docs/network-switching.PNG)

## 使用介绍

安装略

下面针对几个主要功能对genie进行介绍：

### 多网卡与CNI选择
选择不同的CNI只需要在pod中加一个annotations即可
```
apiVersion: v1
kind: Pod
metadata:
  name: nginx-canal-master
  labels:
    app: web
  annotations:
    cni: "canal"
spec:
  containers:
    - name: key-value-store
      image: nginx:latest
      imagePullPolicy: IfNotPresent
      ports:
        - containerPort: 6379
```

![](https://github.com/cni-genie/CNI-Genie/raw/master/docs/CNIGenieDetailedWorkflow.png)

上图最重要的就是4，5，6三个步骤：

4. kubelet调用CNI Genie
5. CNI Genie调用apiserver根据pod名查询pod annotations
6. genie去调用真正的CNI
7. 返回结果给kubelet
8. 返回网络信息给apiserver写入etcd

多网卡不同CNI：

```
  annotations:
    cni: "weave,canal"
```
kubectl get pod只会显示一个ip, describe能看到两张网卡的ip：
```
annotations:     
    cni: canal,weave
    multi-ip-preferences: '{"multi_entry":2,"ips":{"":{},"ip1":{"ip":"10.244.0.201","interface":"eth0"},"ip2":{"ip":"10.32.0.4","interface":"eth1"}}}'                                    
```
进容器也可以看到两张网卡了：
```
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00                             
    inet 127.0.0.1/8 scope host lo                                                   
       valid_lft forever preferred_lft forever                                      
    inet6 ::1/128 scope host                                                       
       valid_lft forever preferred_lft forever                                    
3: eth0@if49589: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1400 qdisc noqueue state UP group default   
    link/ether 7e:99:f7:87:81:c6 brd ff:ff:ff:ff:ff:ff                                            
    inet 10.244.0.201/32 scope global eth0                                                       
       valid_lft forever preferred_lft forever                                                  
    inet6 fe80::7c99:f7ff:fe87:81c6/64 scope link                                              
       valid_lft forever preferred_lft forever                                                
49590: eth1@if49591: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1376 qdisc noqueue state UP group default  
    link/ether 36:b0:8c:f0:9f:58 brd ff:ff:ff:ff:ff:ff                                               
    inet 10.32.0.4/12 scope global eth1                                                             
       valid_lft forever preferred_lft forever                                                     
    inet6 fe80::34b0:8cff:fef0:9f58/64 scope link                                                 
       valid_lft forever preferred_lft forever 
```

### 通过CRD定义网卡

定义一个NAD(NetworkAttachmentDefinition)
```
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: weavenet
spec:
  config: '{
    "cniVersion": "0.3.0",
    "plugins": [
        {
            "name": "weave",
            "type": "weave-net",
            "hairpinMode": true
        },
        {
            "type": "portmap",
            "capabilities": {"portMappings": true},
            "snat": true
        }
    ]
}
'
```

pod使用该NAD,还可指定默认插件，没写annotation就走默认CNI
```
apiVersion: v1
kind: Pod
metadata:
  name: nginx-netattachdef-flannel-weave
  annotations:
    k8s.v1.cni.cncf.io/networks: flannel@eth1, network/weavenet@eth5
spec:
  containers:
    - name: key-value-store
      image: nginx:latest
      imagePullPolicy: IfNotPresent
      ports:
        - containerPort: 80
```

### 智能CNI选择

CNI-Genie可以与cAdvisor交互，收集每个容器的网络使用信息,以决定网络走哪个CNI

支持以下KPI：
 
* 网络延迟
* 网络带宽
* 端到端响应时间
* 使用的IP地址百分比，即（使用的IP地址数）/（IP地址总数）
* 入住率
* 用户填写问卷以查找用例优化的CNI插件

使用时直接不指定CNI即可
```
apiVersion: v1
kind: Pod
metadata:
  name: nginx-smart-pick
  labels:
    app: web
  annotations:
    cni: ""
```
你可以把一个CNI的流量打满，那么新创建的pod就会自动选择别的CNI

探讨可加QQ群：98488045
