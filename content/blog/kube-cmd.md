+++
author = "fanux"
date = "2018-10-24T10:54:24+02:00"
draft = true
title = "老夫k8s命令行賊6"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
banner = "img/banners/banner-1.png"
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

# [kubernetes集群三步安装](https://sealyun.com/pro/products/)

程序员十八层鄙视网络之终端用户鄙视界面点点点

# 自动补全
啥也不用装，配置一下即可：

bash用户：
```
echo "source <(kubectl completion bash)" >> ~/.bashrc
```
zsh用户：
```
echo "source <(kubectl completion zsh)" >> ~/.zshrc
```

然后 `source ~/.zshrc`

这样不仅可以帮助你补全describe service deployment这些关键字，还可以直接补全namespace名 pod名等，十分辛福。

# 交互式客户端
## kueb-prompt
[项目地址](https://github.com/c-bata/kube-prompt) golang开发的，二进制一扔就可以使用还跨平台
```
# Linux
$ wget https://github.com/c-bata/kube-prompt/releases/download/v1.0.3/kube-prompt_v1.0.3_linux_amd64.zip
$ unzip kube-prompt_v1.0.3_linux_amd64.zip

# macOS (darwin)
$ wget https://github.com/c-bata/kube-prompt/releases/download/v1.0.3/kube-prompt_v1.0.3_darwin_amd64.zip
$ unzip kube-prompt_v1.0.3_darwin_amd64.zip

# 给 kube-prompt 加上执行权限并移动常用的可搜索路径。
$ chmod +x kube-prompt
$ sudo mv ./kube-prompt /usr/local/bin/kube-prompt
```

# 终端界面
