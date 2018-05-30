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
## [kubernetes1.10.3离线安装包](https://market.aliyun.com/products/57742013/cmxz028521.html#sku=yuncode2252100000)

* 全部使用当前最新版本组建
* Cgroup driver自动检测，99%以上一键安装成功，遇到任何问题远程协助解决
* 优化dashboard grafana等yaml配置
* DNS双副本高可用
* 1.10.3的功能我们进行过一个月的稳定性测试，大家可以放心使用


## [kubernetes1.9.2离线安装包](https://market.aliyun.com/products/57742013/cmxz025618.html?spm=5176.730005.productlist.dcmxz025618.r9c1J1#sku=yuncode1961800000)

## [kubernetes1.8.1离线安装包](https://market.aliyun.com/products/56014009/cmxz022571.html?spm=5176.730005.productlist.dcmxz022571.r9c1J1#sku=yuncode1657100000) 推荐使用1.9.2以上版本

# QQ群：98488045

# kubernetes离线包安装教程：
```
1. master上： cd shell && sh init.sh && sh master.sh
2. node上：cd shell && sh init.sh
3. 在node上执行master输出的join命令即可
```
## master 节点 (录屏加载较慢，别焦躁。。。)
<script data-speed="3" src="https://asciinema.org/a/RZ3a74x8qE6DZy7jSjaDrLvYM.js" id="asciicast-RZ3a74x8qE6DZy7jSjaDrLvYM" async></script>

## node 节点
<script data-speed="3" src="https://asciinema.org/a/HwrKtAEJpguMfYMNEU7LDeFbQ.js?speed=40" id="asciicast-HwrKtAEJpguMfYMNEU7LDeFbQ" async></script>


