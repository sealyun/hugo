+++
author = "fanux"
date = "2019-04-01T10:54:24+02:00"
draft = false
title = "k8s高可用一个kubeadm搞定,无依赖keepalived haproxy ansible"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
banner = "img/banner-1.png"
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++
探讨可加QQ群：98488045

# 概述
地址[sealos](https://github.com/fanux/sealos), 让kubernetes高可用不再需要keepalived haproxy和ansible, 

sealyun定制超级版kubeadm通过ipvs代理多个master，优雅解决k8s高可用问题。
<!--more-->

# 使用教程
## 环境介绍
|ip | role|
| --- | --- |
| 10.103.97.200 | master0|
| 10.103.97.201 | master0|
| 10.103.97.202 | master0|
| 10.103.97.2 | virtulIP|
| apiserver.cluster.local | apiserver解析名|

## 下载超级[kubeadm](https://github.com/fanux/kube/releases/tag/v0.0.30-kubeadm-lvscare)
## 下载[kubernetes1.14.0+离线包](http://store.lameleg.com)
在每个节点上初始化
```
tar zxvf kube1.14.0.tar.gz && cd kube/shell && sh init.sh
```
用下载的kubeadm替换掉包内的kubeadm:
```
cp kubeadm /usr/bin/kubeadm
```

## kubeadm配置文件 
cat kubeadm-config.yaml :

```
apiVersion: kubeadm.k8s.io/v1beta1
kind: ClusterConfiguration
kubernetesVersion: v1.14.0
controlPlaneEndpoint: "apiserver.cluster.local:6443" # 使用解析名去访问APIserver
apiServer:
        certSANs:
        - 127.0.0.1
        - apiserver.cluster.local
        - 172.20.241.205
        - 172.20.241.206
        - 172.20.241.207
        - 172.20.241.208
        - 10.103.97.2          # 虚拟IP等都加入到证书中
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "ipvs"
ipvs:
        excludeCIDRs: 
        - "10.103.97.2/32" # 如果不加这个k8s会定时清理用户创建的IPVS规则，导致代理失败
```
## 在 master0 10.103.97.200 上
```
echo "10.103.97.200 apiserver.cluster.local" >> /etc/hosts
kubeadm init --config=kubeadm-config.yaml --experimental-upload-certs  
mkdir ~/.kube && cp /etc/kubernetes/admin.conf ~/.kube/config
kubectl apply -f https://docs.projectcalico.org/v3.6/getting-started/kubernetes/installation/hosted/kubernetes-datastore/calico-networking/1.7/calico.yaml # 安装calico
```
执行完会输出一些日志，里面包含join需要用的命令

## 在 master1 10.103.97.201 上
```
# 注意，在安装之前解析到master0, 安装成功后解析改成自己,因为kubelet kube-proxy配置的都是这个解析名,如果不改解析master0宕机整个集群就不可用了
echo "10.103.97.200 apiserver.cluster.local" >> /etc/hosts 
kubeadm join 10.103.97.200:6443 --token 9vr73a.a8uxyaju799qwdjv \
    --discovery-token-ca-cert-hash sha256:7c2e69131a36ae2a042a339b33381c6d0d43887e2de83720eff5359e26aec866 \
    --experimental-control-plane \
    --certificate-key f8902e114ef118304e561c3ecd4d0b543adc226b7a07f675f56564185ffe0c07 

sed "s/10.103.97.200/10.103.97.201/g" -i /etc/hosts  # 解析改也自己本机地址
```

## 在 master2 10.103.97.202 上，同master1
```
echo "10.103.97.200 apiserver.cluster.local" >> /etc/hosts
kubeadm join 10.103.97.200:6443 --token 9vr73a.a8uxyaju799qwdjv \
    --discovery-token-ca-cert-hash sha256:7c2e69131a36ae2a042a339b33381c6d0d43887e2de83720eff5359e26aec866 \
    --experimental-control-plane \
    --certificate-key f8902e114ef118304e561c3ecd4d0b543adc226b7a07f675f56564185ffe0c07  

sed "s/10.103.97.200/10.103.97.201/g" -i /etc/hosts
```

## 在Node节点上
通过虚拟IP join到master上, 这个命令会在node节点上创建一条ipvs规则，virturl server就是虚拟IP， realserver就是三个master。
然后再以一个static pod起一个守护进程守护这些规则，一旦哪个apiserver不可访问了就清除realserver, apiserver通了之后再次添加回来
```
echo "10.103.97.2 apiserver.cluster.local" >> /etc/hosts   # using vip
kubeadm join 10.103.97.2:6443 --token 9vr73a.a8uxyaju799qwdjv \
    --master 10.103.97.200:6443 \
    --master 10.103.97.201:6443 \
    --master 10.103.97.202:6443 \
    --discovery-token-ca-cert-hash sha256:7c2e69131a36ae2a042a339b33381c6d0d43887e2de83720eff5359e26aec866 
```

# Architecture
```
  +----------+                       +---------------+  virturl server: 10.103.97.2:6443
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

集群每个node节点都会创建一条ipvs规则用于代理所有的master节点。类似kube-proxy的ipvs实现.

然后起一个守护进程就健康检查apiservers `/etc/kubernetes/manifests/sealyun-lvscare.yaml`

# [LVScare](https://github.com/fanux/LVScare)
关于ipvs的创建与守护可见这个项目。


