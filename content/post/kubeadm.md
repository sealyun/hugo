+++
author = "fanux"
date = "2018-12-04T10:54:24+02:00"
draft = false
title = "kubeadm杂谈"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

> [kubernetes集群三步安装](https://sealyun.com/pro/products/)

# kubeadm 1.13版本
此版本更新了不少东西，以前老的配置不再适用
```
W1205 19:10:23.541054   58540 strict.go:54] error unmarshaling configuration schema.GroupVersionKind{Group:"kubeadm.k8s.io", Version:"v1beta1", Kind:"InitConfiguration"}: error unmarshaling JSON: while decoding JSON: json: unknown field

```

```
your configuration file uses an old API spec: "kubeadm.k8s.io/v1alpha2". Please use kubeadm v1.12 instead and run 'kubeadm config migrate --old-config old.yaml --new-config new.yaml', which will write the new, similar spec using a newer API version.
```
诸如此类茫茫多的报错

需要使用新的kubeadm配置如：

kubeadm.yaml:
```
apiVersion: kubeadm.k8s.io/v1beta1
kind: ClusterConfiguration
networking:
  podSubnet: 100.64.0.0/10
kubernetesVersion: v1.13.0
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "ipvs"
```

kubeadm init --config kubeadm.yaml 才行

可以用下面命令来查看默认配置长什么样,可以用--component-configs来查看具体哪个组件的配置：

```
kubeadm config print init-defaults --component-configs KubeProxyConfiguration
```
