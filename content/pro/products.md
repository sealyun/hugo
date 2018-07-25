+++
author = "fanux"
date = "2014-07-11T10:54:24+02:00"
draft = false
title = "kubernetes离线包安装教程"
tags = ["event","dotScale","sketchnote"]
image = "images/2014/Jul/titledotscale.png"
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

# 安装包列表
## [kubernetes1.11.1离线安装包]( )  |  售价 50元 云市场审核中，敬请期待

* 修复kubernetes 1.11.0版本centos下ipvs ipset comment 的bug, kubernetes[65461](https://github.com/kubernetes/kubernetes/issues/65461)
* 将ipvs设置成默认的service模式,无需用户修改任何配置即可开启ipvs之旅

## [kubernetes1.11.0离线安装包](https://market.aliyun.com/products/57742013/cmxz029129.html)  |  售价 50元

* 全网最快发布的kubernetes1.11.0离线包
* coreDNS ipvs走起，ipvs性能甩iptables好多条街，赶快行动吧
* 增加crictl cri命令行工具

## [kubernetes1.10.3离线安装包](https://market.aliyun.com/products/57742013/cmxz028521.html#sku=yuncode2252100000) | 售价 15元

* 强力推荐，1.10.3版本k8s优化了很多东西，如存储，大内存页等，比如你要对接ceph等，那一定不要用1.10以下版本的
* 全部使用当前最新版本组建
* Cgroup driver自动检测，99%以上一键安装成功，遇到任何问题远程协助解决
* 优化dashboard grafana等yaml配置
* DNS双副本高可用
* 1.10.3的功能我们进行过一个月的稳定性测试，大家可以放心使用


## [kubernetes1.9.2离线安装包](https://market.aliyun.com/products/57742013/cmxz025618.html?spm=5176.730005.productlist.dcmxz025618.r9c1J1#sku=yuncode1961800000)  |  售价 50元
```
1.9.2以及以下版本，kubelet服务启动不了？ 1.10.3 加了检测没此问题
cgroup driver配置要相同
查看docker cgroup driver:
docker info|grep Cgroup
有systemd和cgroupfs两种，把kubelet service配置改成与docker一致
vim /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
KUBELET_CGROUP_ARGS=–cgroup-driver=cgroupfs #这个配置与docker改成一致
```

## [kubernetes1.8.1离线安装包](https://market.aliyun.com/products/56014009/cmxz022571.html?spm=5176.730005.productlist.dcmxz022571.r9c1J1#sku=yuncode1657100000) 推荐使用1.9.2以上版本  |  售价 50元

# QQ群：98488045

# kubernetes离线包安装教程：
安装包中不包含docker，如没装docker 请先安装之`yum install -y docker`

```
1. master上： cd shell && sh init.sh && sh master.sh
2. node上：cd shell && sh init.sh
3. 在node上执行master输出的join命令即可 (命令忘记了可以用这个查看，kubeadm token create --print-join-command)
```
> dashboard地址 https://masterip:32000

## master 节点 (录屏加载较慢，别焦躁。。。)
<script data-speed="3" src="https://asciinema.org/a/RZ3a74x8qE6DZy7jSjaDrLvYM.js" id="asciicast-RZ3a74x8qE6DZy7jSjaDrLvYM" async></script>

## node 节点
<script data-speed="3" src="https://asciinema.org/a/HwrKtAEJpguMfYMNEU7LDeFbQ.js?speed=40" id="asciicast-HwrKtAEJpguMfYMNEU7LDeFbQ" async></script>


