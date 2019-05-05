+++
author = "fanux"
date = "2019-05-01T10:54:24+02:00"
draft = false
title = "kubernetes开发流程"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

> [kubernetes集群三步安装](https://sealyun.com/pro/products/)

# 概述
本文介绍如何对kubernetes进行二次开发，仓库如何管理，git分支如何管理，怎样利用CI去编译与发布以及如何给社区贡献代码等，结合实际例子，望对大家有所帮助。

# 开发环境构建
![](/k8s-repo.png)

## Fork
把github.com/kubernetes/kubernetes 项目fork到自己的仓库

## Clone到本地
```
git clone https://github.com/<your-username>/kubernetes 
```

## 设置remote
```
git remote add upstream https://github.com/kubernetes/kubernetes.git
git remote set-url --push upstream no-pushing
```
注意此时你的本地仓库就有了两个远程仓库，一个叫upstream(社区仓库) 一个叫origin(你fork的)

## 代码同步
当社区仓库代码更新时，我们希望与之同步，那么：
```
git pull upstream master  # 先同步到本地
git push                  # push 到origin
```
你修改了代码希望同步给社区，那么PR即可

# 分支管理
![](/k8s-git-flow.png)

   假设我们要定制一个功能，比如我之前做的对kubelet进行lxcfs增强，而我们线上又运行了多个版本的k8s，我们希望这个特性几个版本都可以加上，而且未来k8s发布新版本时同样能merge进去这功能。

   要做到这个git里的两个命令非常重要：
 
   * git cherry-pick 能指定merge特定的变更
   * git rebase      通常我用来合并多个commit, 虽然cherry-pick也支持多个commit，但是多了容易混乱

   首先从master分支HEAD切出一个分支，我们有所的功能开发在这个分支上进行，如我做了c1 c2两次commit。

   然后希望把这个功能merge到2.0版本中，我们先从2.0的tag切一个分支出来，然后在这个分之上去cherry-pick c1 c2即可，非常简单方便，其它版本需要此功能同理。  

   这里注意，如果不用cherry-pick 直接merge的话，因为2.0版本之后还有很多次变更，会产生大量冲突。

# CI编译与发布
   笔者比较喜欢drone，所以编译与发布都是用的drone，安利个[drone免费公有服务](https://cloud.drone.io/)非常好用

![](/build-k8s.png)

    由于k8s各个版本可能需要的golang版本都不太一样，所以最方便的还是在容器中进行构建，但并不是随便一个golang的镜像都可以进行构建，因为k8s还需要拷贝代码，生成代码等依赖了一些小工具，我这里提供了一个官方的编译镜像：fanux/kube-build:v1.12.1-2

    发布时用了drone一个非常方便的插件：plugins/github-release， 可以直接把二进制文件放到github的release pages里

.drone.yml 长这样：
```
kind: pipeline
name: default
workspace:
    base: /go
    path: src/k8s.io/kubernetes  # 要注意工作目录一定要写这个

steps:
- name: build                    # 编译，名字随便写
  image: fanux/kube-build:v1.12.1-2  
  environment: 
    GO111MODULE: on              # 启动go mod
  commands:
      - make generated_files UPDATE_API_KNOWN_VIOLATIONS=true   # 这个是一个known api校验，不加编译可能会报错
      - KUBE_GIT_TREE_STATE="clean" KUBE_GIT_VERSION=v1.14.0 KUBE_BUILD_PLATFORMS=linux/amd64 make all WHAT=cmd/kubelet GOFLAGS=-v  # 几个环境变量特别重要，如不加clean编译出来版本号就会加dirty后缀，需要加版本号不然很多时候无法正常工作，加构建平台，这样无需编译多个bin文件加快编译速度，WHAT里指定需要编译什么代码，大部分情况无需编译有所组件
      - ls  _output/bin/  # 这里能看到编译后的二进制文件

- name: publish
  image: plugins/github-release
  settings:
    api_key: 
        from_secret: git-release-token
    files: _output/bin/kubelet   # 把上一步二进制文件放到release page中
    title: ${DRONE_TAG}          # 使用你打的tag作为标题
    note: Note.md                # 指定一个文件说明你release中干了啥
    when:
        event: tag
```

这样提交代码后刷刷抖音等结果即可。。

# 实践案例
k8s kubeadm默认证书的时间是一年，我希望延长到99年，这样就需要定制化开发，那么问题来了，因为版本众多，是不是需要每个版本都去改一下，那太麻烦了，正确的做法如下：

## 从master切出一个分支
```
git checkout -b kubeadm
```
修改代码并commit
```
commit 6d16c60ca5ce8858feeabca7a3a18d59e642ac3f (HEAD -> kubeadm)
Author: fanux <fhtjob@hotmail.com>
Date:   Mon Mar 18 20:26:08 2019 +0800

    kubeadm with long cert

commit 364b18cb9ef1e8da2cf09f33d0fd8042de6b327e (upstream/master, origin/master, origin/HEAD, master)
```
可以看到我们commit了一次，现在只需要把6d16c60ca这个变化merge到各版本即可

## merge到1.13.4版本中
```
git checkout -b v1.13.4 v1.13.4
git cherry-pick 6d16c60ca5c
```
注意 这次commit如果修改了相同文件的行还是可能会冲突的，需要手动解决一下冲突

解决完冲突commit即可
```
➜  kubernetes git:(v1.13.4) ✗ git add .
➜  kubernetes git:(v1.13.4) ✗ git commit -m "v1.13.4-cert"
[v1.13.4 1bd2e627f5] v1.13.4-cert
 Date: Mon Mar 18 20:26:08 2019 +0800
 4 files changed, 42 insertions(+), 3 deletions(-)
 create mode 100644 .drone.yml
 create mode 100644 Note.md
➜  kubernetes git:(v1.13.4) git tag v1.13.4-cert
➜  kubernetes git:(v1.13.4) git push --tags
```

# 其它注意事项
   要PR给社区的话需要[CLA认证](https://github.com/kubernetes/community/blob/master/CLA.md)一下, 不然你的PR社区是不管的。

   CI加的一些文件如.drone.yml dockerfile等与实际功能的添加最好分开，方便PR时只PR实际需要的代码。

   其它组件与apiserver scheduler可以CI直接打成docker镜像，drone很灵活，不要用死了


探讨可加QQ群：98488045

# 公众号：
![sealyun](https://sealyun.com/kubernetes-qrcode.jpg)

### 微信群：
![](/wechatgroup1.png)
