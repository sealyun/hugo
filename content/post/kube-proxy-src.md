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

    // 代理模式，ipvs iptables userspace kernelspace(windows)四种
	ProxyMode              string
    // 配置同步周期
	ConfigSyncPeriod       time.Duration

    // service 与 endpoint 事件处理器
	ServiceEventHandler    config.ServiceHandler
	EndpointsEventHandler  config.EndpointsHandler
}
```
Proxier是主要入口，抽象了两个函数：
```
type ProxyProvider interface {
	// Sync immediately synchronizes the ProxyProvider's current state to iptables.
	Sync()
	// 定期执行
	SyncLoop()
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

> 创建apiserver client

```
client, eventClient, err := createClients(config.ClientConnection, master)
```

> 创建Proxier 这是仅仅关注ipvs模式的proxier

```
else if proxyMode == proxyModeIPVS {
		glog.V(0).Info("Using ipvs Proxier.")
		proxierIPVS, err := ipvs.NewProxier(
			iptInterface,
			ipvsInterface,
			ipsetInterface,
			utilsysctl.New(),
			execer,
			config.IPVS.SyncPeriod.Duration,
			config.IPVS.MinSyncPeriod.Duration,
			config.IPTables.MasqueradeAll,
			int(*config.IPTables.MasqueradeBit),
			config.ClusterCIDR,
			hostname,
			getNodeIP(client, hostname),
			recorder,
			healthzServer,
			config.IPVS.Scheduler,
		)
...
		proxier = proxierIPVS
		serviceEventHandler = proxierIPVS
		endpointsEventHandler = proxierIPVS
```
这个Proxier具备以下方法：
```
   +OnEndpointsAdd(endpoints *api.Endpoints)
   +OnEndpointsDelete(endpoints *api.Endpoints)
   +OnEndpointsSynced()
   +OnEndpointsUpdate(oldEndpoints, endpoints *api.Endpoints)
   +OnServiceAdd(service *api.Service)
   +OnServiceDelete(service *api.Service)
   +OnServiceSynced()
   +OnServiceUpdate(oldService, service *api.Service)
   +Sync()
   +SyncLoop()
```
所以ipvs的这个Proxier实现了我们需要的绝大部分接口

小结一下：
```
     +-----------> endpointHandler
     |
     +-----------> serviceHandler
     |                ^
     |                | +-------------> sync 定期同步等
     |                | |
ProxyServer---------> Proxier --------> service 事件回调           
     |                  |                                                
     |                  +-------------> endpoint事件回调          
     |                                             |  触发
     +-----> ipvs interface ipvs handler     <-----+
```

## 启动proxyServer

1. 检查是不是带了clean up参数，如果带了那么清除所有规则退出
2. OOM adjuster貌似没实现，忽略
3. resouceContainer也没实现，忽略
4. 启动metrics服务器，这个挺重要，比如我们想监控时可以传入这个参数, 包含promethus的 metrics. metrics-bind-address参数
5. 启动informer, 开始监听事件，分别启动协程处理。

1 2 3 4我们都不用太关注，细看5即可：
```
informerFactory := informers.NewSharedInformerFactory(s.Client, s.ConfigSyncPeriod)

serviceConfig := config.NewServiceConfig(informerFactory.Core().InternalVersion().Services(), s.ConfigSyncPeriod)
// 注册 service handler并启动
serviceConfig.RegisterEventHandler(s.ServiceEventHandler)
// 这里面仅仅是把ServiceEventHandler赋值给informer回调 
go serviceConfig.Run(wait.NeverStop)

endpointsConfig := config.NewEndpointsConfig(informerFactory.Core().InternalVersion().Endpoints(), s.ConfigSyncPeriod)
// 注册endpoint 
endpointsConfig.RegisterEventHandler(s.EndpointsEventHandler)
go endpointsConfig.Run(wait.NeverStop)

go informerFactory.Start(wait.NeverStop)
```
serviceConfig.Run与endpointConfig.Run仅仅是给回调函数赋值, 所以注册的handler就给了informer, informer监听到事件时就会回调：
```
for i := range c.eventHandlers {
	glog.V(3).Infof("Calling handler.OnServiceSynced()")
	c.eventHandlers[i].OnServiceSynced()
}
```

那么问题来了，注册进去的这个handler是啥？ 回顾一下上文的
```
		serviceEventHandler = proxierIPVS
		endpointsEventHandler = proxierIPVS
```
所以都是这个proxierIPVS

handler的回调函数, informer会回调这几个函数，所以我们在自己开发时实现这个interface注册进去即可：
```
type ServiceHandler interface {
	// OnServiceAdd is called whenever creation of new service object
	// is observed.
	OnServiceAdd(service *api.Service)
	// OnServiceUpdate is called whenever modification of an existing
	// service object is observed.
	OnServiceUpdate(oldService, service *api.Service)
	// OnServiceDelete is called whenever deletion of an existing service
	// object is observed.
	OnServiceDelete(service *api.Service)
	// OnServiceSynced is called once all the initial even handlers were
	// called and the state is fully propagated to local cache.
	OnServiceSynced()
}
```

## 开始监听
```
go informerFactory.Start(wait.NeverStop)
```
这里执行后，我们创建删除service endpoint等动作都会被监听到，然后回调,回顾一下上面的图，最终都是由Proxier去实现，所以后面我们重点关注Proxier即可

```
s.Proxier.SyncLoop()
```
然后开始SyncLoop,下文开讲

## Proxier 实现
我们创建一个service时OnServiceAdd方法会被调用, 这里记录一下之前的状态与当前状态两个东西，然后发个信号给syncRunner让它去处理：
```
func (proxier *Proxier) OnServiceAdd(service *api.Service) {
	namespacedName := types.NamespacedName{Namespace: service.Namespace, Name: service.Name}
	if proxier.serviceChanges.update(&namespacedName, nil, service) && proxier.isInitialized() {
		proxier.syncRunner.Run()
	}
}
```

记录service 信息,可以看到没做什么事，就是把service存在map里, 如果没变直接删掉map信息不做任何处理：
```
change, exists := scm.items[*namespacedName]
if !exists {
	change = &serviceChange{}
    // 老的service信息
	change.previous = serviceToServiceMap(previous)
	scm.items[*namespacedName] = change
}
// 当前监听到的service信息
change.current = serviceToServiceMap(current)

如果一样，直接删除
if reflect.DeepEqual(change.previous, change.current) {
	delete(scm.items, *namespacedName)
}
```

proxier.syncRunner.Run() 里面就发送了一个信号
```
select {
case bfr.run <- struct{}{}:
default:
}
```
