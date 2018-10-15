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

# QQ群：98488045
# kubernetes离线包安装教程：
安装包中不包含docker，如没装docker 请先安装之`yum install -y docker`

```
1. master上： cd shell && sh init.sh && sh master.sh
2. node上：cd shell && sh init.sh
3. 在node上执行master输出的join命令即可 (命令忘记了可以用这个查看，kubeadm token create --print-join-command)
```
> dashboard地址 https://masterip:32000

# 安装包列表
## [kubernetes1.12.0离线安装包](https://market.aliyun.com/products/57742013/cmxz030981.html#sku=yuncode2498100001) | 售价 50元 

推荐指数：:star: :star: :star: :star: :star:

* v1.12.0大版本更新了不少有用的东西，如kubeadm证书更新，把node变成控制节点等特性
* RuntimeClass可以让node上运行多种不同的运行时
* 调度器性能的优化，DaemonSet调度规则优化，具备镜像的节点具有更高的调度优先级等特性
* CSI存储快照与恢复接口开放，等等
* 特性比较多不一一列举，对新特性无需求的可不升级此版本

已知问题：`/var/lib/kubelet/config.yaml: No such file or directory` 解决：`mkdir /var/lib/kubelet && sh init.sh`


## [kubernetes1.11.3离线安装包](https://market.aliyun.com/products/57742013/cmxz030730.html) | 售价 50元 

推荐指数：:star: :star: :star: :star: :star:

* v1.11.3版本是1.11中最稳定的一个，修复了很多bug,对PVC有更好支持
* 本包升级了calico到3.2.1版本，低版本calico我们在线上跑出出现过假死，高版本解决了这一bug,且高可用时此版本对证书安全支持更好
* dashboard升级到当前最新版本v1.10，主要也是修复dashboard的一些bug


## [kubernetes1.11.1离线安装包](https://market.aliyun.com/products/57742013/cmxz029676.html#sku=yuncode2367600001)  |  售价 50元 

推荐指数：:star: :star: :star: :star: :star:

* kubernetesv1.11.1离线包全网最快发布,修改calico ip段，再也不会地址冲突
* 修复kubernetes 1.11.0版本centos下ipvs ipset comment 的bug, kubernetes[65461](https://github.com/kubernetes/kubernetes/issues/65461)
* 将ipvs设置成默认的service模式,无需用户修改任何配置即可开启ipvs之旅

## [kubernetes1.11.0离线安装包](https://market.aliyun.com/products/57742013/cmxz029129.html) 推荐使用v1.11.1版本 |  售价 50元

推荐指数：:star: :star: 

* 此版本ipvs在centos下有[bug 65461](sealyun.com/post/k8s-ipvs/)，请谨慎选择使用
* 全网最快发布的kubernetes1.11.0离线包
* coreDNS ipvs走起，ipvs性能甩iptables好多条街，赶快行动吧
* 增加crictl cri命令行工具

## [kubernetes1.10.3离线安装包](https://market.aliyun.com/products/57742013/cmxz028521.html#sku=yuncode2252100000) | 售价 15元

推荐指数：:star: :star: :star: :star: :star:

* 强力推荐，1.10.3版本k8s优化了很多东西，如存储，大内存页等，比如你要对接ceph等，那一定不要用1.10以下版本的
* 全部使用当前最新版本组建
* Cgroup driver自动检测，99%以上一键安装成功，遇到任何问题远程协助解决
* 优化dashboard grafana等yaml配置
* DNS双副本高可用
* 1.10.3的功能我们进行过一个月的稳定性测试，大家可以放心使用


## [kubernetes1.9.2离线安装包](https://market.aliyun.com/products/57742013/cmxz025618.html?spm=5176.730005.productlist.dcmxz025618.r9c1J1#sku=yuncode1961800000)  |  售价 50元

推荐指数：:star: :star: 

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

推荐指数：:star: 

## master 节点 (录屏加载较慢，别焦躁。。。)
<script data-speed="3" src="https://asciinema.org/a/RZ3a74x8qE6DZy7jSjaDrLvYM.js" id="asciicast-RZ3a74x8qE6DZy7jSjaDrLvYM" async></script>

## node 节点
<script data-speed="3" src="https://asciinema.org/a/HwrKtAEJpguMfYMNEU7LDeFbQ.js?speed=40" id="asciicast-HwrKtAEJpguMfYMNEU7LDeFbQ" async></script>


