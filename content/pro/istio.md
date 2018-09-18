+++
author = "fanux"
date = "2014-07-11T10:54:24+02:00"
draft = false
title = "istio离线包&安装教程"
slug = "istio"
tags = ["event","dotScale","sketchnote"]
image = "images/2014/Jul/titledotscale.png"
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

## 安装教程
1. 已经安装[sealyun k8s](https://sealyun.com/pro/products/)
2. 安装socat(脚本里使用yum安装的，所以如果是离线环境自行搞定socat, ubuntu等也请自己装)
3. 确保环境之前没装过istio helm，如已经装过请清理干净
4. 解压后执行install.sh即可

bookinfo的事例地址: http://ip:31380/productpage

## Istio离线安装包
### [istio1.0.2 离线安装包](https://sealyun.com) 阿里云审核中| 售价30元
推荐指数：:star: :star: :star: :star: :star:

* 包含helm
* 包含istio
* 包含使用事例 bookinfo app
