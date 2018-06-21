+++
author = "fanux"
date = "2018-06-20T10:54:24+02:00"
draft = false
title = "kube-proxy源码解析"
#slug = "dotscale-2014-as-a-sketch" #链接地址
tags = ["event","dotScale","sketchnote"]
image = "images/2014/Jul/titledotscale.png"
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

# kube-proxy源码解析
ipvs相对于iptables模式具备较高的性能与稳定性, 本文讲以此模式的源码解析为主，如果想去了解iptables模式的原理，可以去参考其实现，架构上无差别。

kube-proxy主要功能是监听service和endpoint的事件，然后下放代理策略到机器上。 底层调用[docker/libnetwork](https://github.com/docker/libnetwork), 而libnetwork最终调用了[netlink](https://github.com/vishvananda/netlink) 与netns来实现ipvs的创建等动作

## 初始化配置
代码入口：`cmd/kube-proxy/app/server.go` Run() 函数

通过命令行参数去初始化proxyServer的配置
```
proxyServer, err := NewProxyServer(o)
```
```
type ProxyServer struct {
    // k8s client
	Client                 clientset.Interface
	EventClient            v1core.EventsGetter

    // ipvs 相关接口
	IptInterface           utiliptables.Interface
	IpvsInterface          utilipvs.Interface
	IpsetInterface         utilipset.Interface

    // 处理同步时的处理器
	Proxier                proxy.ProxyProvider

    // 代理模式，ipvs iptables 
	ProxyMode              string
	NodeRef                *v1.ObjectReference
	ConfigSyncPeriod       time.Duration

    // service 与 endpoint 事件处理器
	ServiceEventHandler    config.ServiceHandler
	EndpointsEventHandler  config.EndpointsHandler
}
```
ipvs 的interface 这个很重要：
```
type Interface interface {
	// 删除所有规则
	Flush() error
	// 增加一个virtual server
	AddVirtualServer(*VirtualServer) error

	UpdateVirtualServer(*VirtualServer) error
	DeleteVirtualServer(*VirtualServer) error
	GetVirtualServer(*VirtualServer) (*VirtualServer, error)
	GetVirtualServers() ([]*VirtualServer, error)

    // 给virtual server加个realserver, 如 VirtualServer就是一个clusterip realServer就是pod(或者自定义的endpoint)
	AddRealServer(*VirtualServer, *RealServer) error
	GetRealServers(*VirtualServer) ([]*RealServer, error)
	DeleteRealServer(*VirtualServer, *RealServer) error
}
```
我们在下文再详细看ipvs_linux是如何实现上面接口的

virtual server与realserver, 最重要的是ip:port，然后就是一些代理的模式如sessionAffinity等:
```
type VirtualServer struct {
	Address   net.IP
	Protocol  string
	Port      uint16
	Scheduler string
	Flags     ServiceFlags
	Timeout   uint32
}

type RealServer struct {
	Address net.IP
	Port    uint16
	Weight  int
}
```

## 监听apiserver service事件
## ipvs实现
## 用户态给内核
