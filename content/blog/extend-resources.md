+++
author = "fanux"
date = "2119-01-10T10:54:24+02:00"
draft = false
title = "kubernetes扩展资源类型"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
banner = "img/banner-1.png"
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

# TODO

# [kubernetes集群三步安装](https://sealyun.com/pro/products/)

# 概述
除了CPU 内存之外还有一些其它的资源类型，如GPU，一些特殊的硬件设备等，有些资源类型k8s原生并不支持，那么如何能扩展这些资源，让调度器调度时

把扩展资源作一个维度进行调度
<!--more-->

# 应用场景
我们的一个应用场景是本地磁盘资源，虽然更推荐用分布式存储，不过某些苛刻场景下为了性能还是绕不开本地存储，本地存储维护的成本会更大，不过稳定性和性能会更好一些。

使用project quota对文件大小进行隔离，使多租户可以实现相互不影响。

那么问题来了，假设用户需要500G资源，那么调度器就需要知道各个节点是否还具备那么多资源

# 注册资源

QQ群：98488045

