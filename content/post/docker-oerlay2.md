+++
author = "fanux"
date = "2019-03-23T10:54:24+02:00"
draft = false
title = "关于overlay2存储驱动的磁盘配额问题"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

> [kubernetes集群三步安装](https://sealyun.com/pro/products/)

# 概述
这篇短文向大家介绍一下正确使用存储驱动的姿势，非常有用。

## 为啥要用overlay2
* docker centos（内核3.10）上默认存储驱动是devicemapper 的loop-lvm模式，这种模式是用文件模拟块设备，不推荐生产使用
* direct lvm又不是一个开箱即用的模式，懒得配置
* 最关键的是 docker in docker的情况下 device mapper是行不通的，典型的场景就是用drone时，构建docker镜像就不能正常工作
* overlay存储驱动层数过多时会导致文件链接数过多可能会耗尽inode

所以当前overlay2是个比较好的选择

## 内核
你需要一个高版本的内核推荐4.9以上，我们用的是4.14，如果使用低内核可能你一些FROM别的基础镜像就跑不了，如用overlay2在centos系统上跑FROM ubuntu的镜像（不是必现）

我们这里提供了一个免费的[内核rpm包](https://github.com/sealyun/kernel/releases/tag/v4.14.49) 这个在我们生产环境跑了将近一年没出任何问题

# 使用xfs文件系统
不使用xfs就无法做到给每个容器限制10G的大小，就可能出现一个容器的误操作导致把机器盘全占完

我们使用了lvm去弄个分区出来做xfs文件系统，当然你也可以不用lvm

```
if which lvs &>/dev/null; then
  echo ""; echo -e "Remove last docker lv and mount ......"
  lvremove k8s/docker -y
  lvcreate -y -n docker k8s -L 100G
  mkfs.xfs -n ftype=1 -f /dev/mapper/k8s-docker
  mkdir -p /var/lib/docker
  mount -o pquota,uqnoenforce /dev/mapper/k8s-docker /var/lib/docker
  echo -e "/dev/mapper/k8s-docker                                  /var/lib/docker         xfs     defaults,pquota        0 0" >> /etc/fstab
fi
```

# 配置使用overlay2
```
# cat /etc/docker/daemon.json
{
  "storage-opts": [
    "overlay2.override_kernel_check=true",
    "overlay2.size=10G"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m"
  }
}
```
systemctl daemon-reload
systemctl restart docker

这样就可以把每个容器磁盘大小限制在10G了


探讨可加QQ群：98488045

# 公众号：
![sealyun](https://sealyun.com/kubernetes-qrcode.jpg)

### 微信群：
![](/wechatgroup1.png)
