+++
author = "fanux"
date = "2019-04-15T10:54:24+02:00"
draft = false
title = "最简单的kubernetes HA安装方式-sealos详解"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

> [kubernetes集群三步安装](https://sealyun.com/pro/products/)

# 概述
本文教你如何用一条命令构建k8s高可用集群且不依赖haproxy和keepalived，也无需ansible。通过内核ipvs对apiserver进行负载均衡，并且带apiserver健康检测。

# 快速入门
[sealos项目地址](https://github.com/fanux/sealos) 
## 准备条件
* 装好docker并启动docker
* 把[离线安装包](http://store.lameleg.com) 下载好拷贝到所有节点的/root目录下, 不需要解压，如果有文件服务器更好，sealos支持从一个服务器上wget到所有节点上

## 安装
sealos已经放在离线包中，解压后在kube/bin目录下(可以解压一个，获取sealos bin文件)
```
sealos init \
    --master 192.168.0.2 \
    --master 192.168.0.3 \
    --master 192.168.0.4 \          # master地址列表
    --node 192.168.0.5 \            # node地址列表
    --user root \                   # 服务用户名
    --passwd your-server-password \ # 服务器密码，用于远程执行命令
    --pkg kube1.14.1.tar.gz  \      # 离线安装包名称
    --version v1.14.1               # kubernetes 离线安装包版本，这渲染kubeadm配置时需要使用
```
然后，就没有然后了


其它参数:

```
 --kubeadm-config string   kubeadm-config.yaml local # 自定义kubeadm配置文件，如有这个sealos就不去渲染kubeadm配置
 --pkg-url string          http://store.lameleg.com/kube1.14.1.tar.gz download offline pakage url # 支持从远程拉取离线包，省的每个机器拷贝，前提你得有个http服务器放离线包
 --vip string              virtual ip (default "10.103.97.2") # 代理master的虚拟IP，只要与你地址不冲突请不要改
```


## 清理
```
sealos clean \
    --master 192.168.0.2 \
    --master 192.168.0.3 \
    --master 192.168.0.4 \          # master地址列表
    --node 192.168.0.5 \            # node地址列表
    --user root \                   # 服务用户名
    --passwd your-server-password
```

## 增加节点
新增节点可直接使用kubeadm， 到新节点上解压 
```
cd kube/shell && init.sh
echo "10.103.97.2 apiserver.cluster.local" >> /etc/hosts   # using vip
kubeadm join 10.103.97.2:6443 --token 9vr73a.a8uxyaju799qwdjv \
    --master 10.103.97.100:6443 \
    --master 10.103.97.101:6443 \
    --master 10.103.97.102:6443 \
    --discovery-token-ca-cert-hash sha256:7c2e69131a36ae2a042a339b33381c6d0d43887e2de83720eff5359e26aec866
```

## 安装dashboard prometheus等
离线包里包含了yaml配置和镜像，用户按需安装。
```
cd /root/kube/conf
kubectl taint nodes --all node-role.kubernetes.io/master-  # 去污点，根据需求看情况，去了后master允许调度
kubectl apply -f heapster/ # 安装heapster, 不安装dashboard上没监控数据
kubectl apply -f heapster/rbac 
kubectl apply -f dashboard  # 装dashboard
kubectl apply -f prometheus # 装监控
```

是不是很神奇，到底是如何做到这点的？那就需要去看下面两个东西

# 关于超级kubeadm
我们定制了kubeadm，做了两个事情：

1. 在每个node节点上增加了一条ipvs规则，其后端代理了三个master
2. 在node上起了一个lvscare的static pod去守护这个 ipvs, 一旦apiserver不可访问了，会自动清理掉所有node上对应的ipvs规则， master恢复正常时添加回来。

通过这样的方式实现每个node上通过本地内核负载均衡访问masters：
```
  +----------+                       +---------------+  virturl server: 127.0.0.1:6443
  | mater0   |<----------------------| ipvs nodes    |    real servers:
  +----------+                      |+---------------+            10.103.97.200:6443
                                    |                             10.103.97.201:6443
  +----------+                      |                             10.103.97.202:6443
  | mater1   |<---------------------+
  +----------+                      |
                                    |
  +----------+                      |
  | mater2   |<---------------------+
  +----------+
```
这是一个非常优雅的方案

其实sealos就是帮你执行了如下命令：
[super-kubeadm](https://sealyun.com/post/super-kubeadm/)

在你的node上增加了三个东西：
```
cat /etc/kubernetes/manifests   # 这下面增加了lvscare的static pod
ipvsadm -Ln                     # 可以看到创建的ipvs规则
cat /etc/hosts                  # 增加了虚拟IP的地址解析
```

# 关于[lvscare](https://github.com/fanux/LVScare)
这是一个超级简单轻量级的lvs创建与守护进程，支持健康检查，底层与kube-proxy使用的是相同的库，支持HTTP的健康检测。

清理机器上的IPVS规则
```
ipvsadm -C
```

启动几个nginx作为ipvs代理后端的realserver
```
docker run -p 8081:80 --name nginx1 -d nginx
docker run -p 8082:80 --name nginx2 -d nginx
docker run -p 8083:80 --name nginx3 -d nginx
```

启动lvscare守护它们
```
lvscare care --vs 10.103.97.12:6443 --rs 127.0.0.1:8081 --rs 127.0.0.1:8082 --rs 127.0.0.1:8083 \
--health-path / --health-schem http
```

可以看到规则已经被创建
```
ipvsadm -Ln
[root@iZj6c9fiza9orwscdhate4Z ~]# ipvsadm -Ln
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
TCP  10.103.97.12:6443 rr
  -> 127.0.0.1:8081               Masq    1      0          0         
  -> 127.0.0.1:8082               Masq    1      0          0         
  -> 127.0.0.1:8083               Masq    1      0          0 
```

curl vip:
```
[root@iZj6c9fiza9orwscdhate4Z ~]# curl 10.103.97.12:6443 
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
```

删除一个nginx,规则就少了一条
```
[root@iZj6c9fiza9orwscdhate4Z ~]# docker stop nginx1
nginx1
[root@iZj6c9fiza9orwscdhate4Z ~]# ipvsadm -Ln
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
TCP  10.103.97.12:6443 rr
  -> 127.0.0.1:8082               Masq    1      0          0         
  -> 127.0.0.1:8083               Masq    1      0          1 
```

再删除一个:
```
[root@iZj6c9fiza9orwscdhate4Z ~]# docker stop nginx2
nginx2
[root@iZj6c9fiza9orwscdhate4Z ~]# ipvsadm -Ln
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
TCP  10.103.97.12:6443 rr
  -> 127.0.0.1:8083               Masq    1      0          0 
```

此时VIP任然可以访问:
```
[root@iZj6c9fiza9orwscdhate4Z ~]# curl 10.103.97.12:6443 
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
```

全部删除, 规则就自动被清除光了, curl也curl不通了，因为没realserver可用了
```
[root@iZj6c9fiza9orwscdhate4Z ~]# docker stop nginx3
nginx3
[root@iZj6c9fiza9orwscdhate4Z ~]# ipvsadm -Ln
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
TCP  10.103.97.12:6443 rr
[root@iZj6c9fiza9orwscdhate4Z ~]# curl 10.103.97.12:6443 
curl: (7) Failed connect to 10.103.97.12:6443; 拒绝连接
```

再把nginx都启动起来,规则就自动被加回来
```
[root@iZj6c9fiza9orwscdhate4Z ~]# docker start nginx1 nginx2 nginx3
nginx1
nginx2
nginx3
[root@iZj6c9fiza9orwscdhate4Z ~]# ipvsadm -Ln
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
TCP  10.103.97.12:6443 rr
  -> 127.0.0.1:8081               Masq    1      0          0         
  -> 127.0.0.1:8082               Masq    1      0          0         
  -> 127.0.0.1:8083               Masq    1      0          0 
```

所以sealos中，上面apiserver就是上面三个nginx，lvscare会对其进行健康检测。

当然你也可以把lvscare用于一些其它场景，比如代理自己的TCP服务等


探讨可加QQ群：98488045

# 公众号：
![sealyun](https://sealyun.com/kubernetes-qrcode.jpg)

### 微信群：
![](/wechatgroup1.png)
