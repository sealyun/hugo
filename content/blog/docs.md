+++
author = "fanux"
date = "2018-12-11T10:54:24+02:00"
draft = false
title = "sealyun kubernetes离线包文档"
tags = ["event","dotScale","sketchnote"]
image = "images/2014/Jul/titledotscale.png"
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

# 前言
* [kubernetes安装包store](http://store.lameleg.com/) 
* [官方销售市场](http://store.lameleg.com/  )：http://store.lameleg.com/  
* [阿里云市场购买下载地址列表](https://sealyun.com/pro/products/)：https://sealyun.com/pro/products/

# 商品介绍
安装包通过kubeadm安装kubernetes集群,包含：

* 核心基础组件 etcd apisver kubelet kube-proxy scheduler manager
* addon组件    dashboard calico promethus grafana alertmanager node-exporter coreDNS 

启用IPVS

可以内网环境进行安装，但是不包含docker
<!--more-->

部分版本定制过kubeadm证书过期时间调整到99年,默认是一年，一年后不更新证书集群就不可用

## 展示
官方dashboard
![](/show/dashboard.png)
![](/show/dashboard1.png)
![](/show/dashboard3.png)

集群监控
![](/show/prometheus.png)
![](/show/prometheus1.png)
![](/show/prometheus2.png)

ceph监控，依赖rook,包内暂时不包含
![](/show/moni-ceph.png)

# kubernetes安装文档 单master
安装包中不包含docker，如没装docker 请先安装之`yum install -y docker`

```
1. master上： cd shell && sh init.sh && sh master.sh
2. node上：cd shell && sh init.sh
3. 在node上执行master输出的join命令即可 (命令忘记了可以用这个查看，kubeadm token create --print-join-command)
```
> dashboard地址 https://masterip:32000

卸载：`kubeadm reset`

清理：
```
kubeadm reset -f
modprobe -r ipip
lsmod
rm -rf ~/.kube/
rm -rf /etc/kubernetes/
rm -rf /etc/systemd/system/kubelet.service.d
rm -rf /etc/systemd/system/kubelet.service
rm -rf /usr/bin/kube*
rm -rf /etc/cni
rm -rf /opt/cni
rm -rf /var/lib/etcd
rm -rf /var/etcd
```

# 证书延长版
kubernets默认证书一年过期，这里编译了一个99年证书的kubeadm，下载下来替换离线安装包里的即可
[kubeadm](https://github.com/fanux/kube/releases/tag/certv1.13.4)

# kubernetes高可用安装
基本此安装包我们开发了[sealos](https://github.com/fanux/sealos)用于构建生产环境高可用的kubernetes集群，[文档地址](https://sealyun.com/post/sealos/)

# 监控使用教程
监控使用prometheus operator构建，更多信息请[参考](https://sealyun.com/post/prometheus-operator-envoy/)

# sealyun公众号
这里你能看到

* kubernetes一些深入的分析如各块的源码解析
* 我们遇到的坑,大规模实践k8s时一些小细节 版本选择，各版本的坑，内核如何选择，存储与网络虚拟化方案等
* 短文介绍一些小知识,如一些偏门小命令，又如集群证书更新，kubeadm如何配置，scheduler如何做一些扩展等


QQ群：98488045

