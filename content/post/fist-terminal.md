+++
author = "fanux"
date = "2019-02-05T10:54:24+02:00"
draft = false
title = "属于极客的k8s管理工具fist, 强大的webterminal"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

> [kubernetes集群三步安装](https://sealyun.com/pro/products/)

# 介绍
fist是sealyun开发的精致的k8s管理工具，所有功能切入要害，而不追求多与重，接下来的介绍我相信有节操的k8s管理员一定会喜欢它。

# terminal功能安装
[安装地址](https://github.com/fanux/fist/blob/master/terminal/README.md)

[体验地址](http://47.52.202.240:30514/)

# 集成kubectl
terminal中可直接使用kubectl，用户就不需要登录到机器上或者自己装kubectl远程访问集群，当然这是基本功能

# 自动渲染kubeconfig文件
会根据传入的token去创建.kube/config 文件，如何给用户创建token [看这里](https://github.com/fanux/fist#auth)

# config文件高亮
![](/fist/config-highlight.png)

看起来是不是很舒服

# 权限管理
![](/fist/RBAC.png)

因为传进来的token是没有任何权限的，所以就可以进行权限管理，现在后台超级管理员想给fanux绑定什么权限

他有具备什么样的权限，可对接ldap为用户创建token

# 一键补全yaml!
![](/fist/auto-dep.png)

输入dep再按Ctrl g即可补全整个deployment

当然还支持其它对象的补全：
svc
job
ns
等等等等 [看这里](https://github.com/andrewstuart/vim-kubernetes/blob/master/UltiSnips/yaml.snippets)

像这样ns就是模板的昵称
```
snippet ns "Namespace" !b
apiVersion: v1
kind: Namespace
metadata:
```

![](/fist/vim-plugin.gif)

# 这居然是个完整的golang开发环境！
语法高亮

![](/fist/golang-dev.png)

自动补全

![](/fist/auto-complete.png)

装了一些列高大上的vim插件，如果你自己折腾会很恶心~

代码跳转，访问目录，访问函数 结构体列表等等应有尽有

几个简单的使用快捷键：
```
zm 或者 zi 折叠和打开折叠的代码
Ctrl n 打开左侧代码目录
,t 打开右边函数列表（逗号加t）
Ctrl h 切换光标窗口 (Ctrl h Ctrl J Ctrl K Ctrl L)
,dt 跳转到函数定义
```

# 总结
命令行是非常高效的管理工具，对于k8s新手我非常推荐多用命令行而少用界面。  这个terminal功能看似简单，不过做起来还是很恶心的,用了最新的vim和一些如YCM这种非常优秀的插件，和vim-go这样非常好的工具，帮您省事，都到这里的喜欢的话希望给个[star](https://github.com/fanux/fist)

后续会开发一个简单的UI界面，还有让安装更简单，以及集成ldap~ 

探讨可加QQ群：98488045

# 公众号：
![sealyun](https://sealyun.com/kubernetes-qrcode.jpg)

### 微信群：
![](/wechatgroup1.png)
