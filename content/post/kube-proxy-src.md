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

> 广告 | [kubernetes离线安装包，仅需三步](http://sealyun.com/pro/products/)

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

这里面处理了这个信号
```
s.Proxier.SyncLoop()

func (proxier *Proxier) SyncLoop() {
	// Update healthz timestamp at beginning in case Sync() never succeeds.
	if proxier.healthzServer != nil {
		proxier.healthzServer.UpdateTimestamp()
	}
	proxier.syncRunner.Loop(wait.NeverStop)
}
```

runner里收到信号执行，没收到信号会定期执行：
```
func (bfr *BoundedFrequencyRunner) Loop(stop <-chan struct{}) {
	glog.V(3).Infof("%s Loop running", bfr.name)
	bfr.timer.Reset(bfr.maxInterval)
	for {
		select {
		case <-stop:
			bfr.stop()
			glog.V(3).Infof("%s Loop stopping", bfr.name)
			return
		case <-bfr.timer.C():  // 定期执行
			bfr.tryRun()
		case <-bfr.run:
			bfr.tryRun()       // 收到事件信号执行
		}
	}
}
```
这个bfr runner里我们最需要主意的是一个回调函数，tryRun里检查这个回调是否满足被调度的条件：
```
type BoundedFrequencyRunner struct {
	name        string        // the name of this instance
	minInterval time.Duration // the min time between runs, modulo bursts
	maxInterval time.Duration // the max time between runs

	run chan struct{} // try an async run

	mu      sync.Mutex  // guards runs of fn and all mutations
	fn      func()      // function to run, 这个回调
	lastRun time.Time   // time of last run
	timer   timer       // timer for deferred runs
	limiter rateLimiter // rate limiter for on-demand runs
}

// 传入的proxier.syncProxyRules这个函数
proxier.syncRunner = async.NewBoundedFrequencyRunner("sync-runner", proxier.syncProxyRules, minSyncPeriod, syncPeriod, burstSyncs)
```
这是个600行左右的搓逼函数，也是处理主要逻辑的地方。

## syncProxyRules
1. 设置一些iptables规则，如mark与comment
2. 确定机器上有网卡，ipvs需要绑定地址到上面
3. 确定有ipset，ipset是iptables的扩展，可以给一批地址设置iptables规则
...(又臭又长，重复代码多，看不下去了，细节问题自己去看吧)
4. 我们最关注的，如何去处理VirtualServer的

```
serv := &utilipvs.VirtualServer{
	Address:   net.ParseIP(ingress.IP),
	Port:      uint16(svcInfo.port),
	Protocol:  string(svcInfo.protocol),
	Scheduler: proxier.ipvsScheduler,
}
if err := proxier.syncService(svcNameString, serv, false); err == nil {
	if err := proxier.syncEndpoint(svcName, svcInfo.onlyNodeLocalEndpoints, serv); err != nil {
	}
}
```
看下实现, 如果没有就创建，如果已存在就更新, 给网卡绑定service的cluster ip：
```
func (proxier *Proxier) syncService(svcName string, vs *utilipvs.VirtualServer, bindAddr bool) error {
	appliedVirtualServer, _ := proxier.ipvs.GetVirtualServer(vs)
	if appliedVirtualServer == nil || !appliedVirtualServer.Equal(vs) {
		if appliedVirtualServer == nil {
			if err := proxier.ipvs.AddVirtualServer(vs); err != nil {
				return err
			}
		} else {
			if err := proxier.ipvs.UpdateVirtualServer(appliedVirtualServer); err != nil {
				return err
			}
		}
	}

	// bind service address to dummy interface even if service not changed,
	// in case that service IP was removed by other processes
	if bindAddr {
		_, err := proxier.netlinkHandle.EnsureAddressBind(vs.Address.String(), DefaultDummyDevice)
		if err != nil {
			return err
		}
	}
	return nil
}
```

## 创建service实现
现在可以去看ipvs的AddVirtualServer的实现了，主要是利用socket与内核进程通信做到的。
`pkg/util/ipvs/ipvs_linux.go` 里 runner结构体实现了这些方法, 这里用到了 docker/libnetwork/ipvs库：

```
// runner implements Interface.
type runner struct {
	exec       utilexec.Interface
	ipvsHandle *ipvs.Handle
}

// New returns a new Interface which will call ipvs APIs.
func New(exec utilexec.Interface) Interface {
	ihandle, err := ipvs.New("") // github.com/docker/libnetwork/ipvs
	if err != nil {
		glog.Errorf("IPVS interface can't be initialized, error: %v", err)
		return nil
	}
	return &runner{
		exec:       exec,
		ipvsHandle: ihandle,
	}
}
```

New的时候创建了一个特殊的socket, 这里与我们普通的socket编程无差别，关键是syscall.AF_NETLINK这个参数，代表与内核进程通信：
```
sock, err := nl.GetNetlinkSocketAt(n, netns.None(), syscall.NETLINK_GENERIC)

func getNetlinkSocket(protocol int) (*NetlinkSocket, error) {
	fd, err := syscall.Socket(syscall.AF_NETLINK, syscall.SOCK_RAW|syscall.SOCK_CLOEXEC, protocol)
	if err != nil {
		return nil, err
	}
	s := &NetlinkSocket{
		fd: int32(fd),
	}
	s.lsa.Family = syscall.AF_NETLINK
	if err := syscall.Bind(fd, &s.lsa); err != nil {
		syscall.Close(fd)
		return nil, err
	}

	return s, nil
}
```

创建一个service, 转换成docker service格式，直接调用:
```
// AddVirtualServer is part of Interface.
func (runner *runner) AddVirtualServer(vs *VirtualServer) error {
	eSvc, err := toBackendService(vs)
	if err != nil {
		return err
	}
	return runner.ipvsHandle.NewService(eSvc)
}
```

然后就是把service信息打包，往socket里面写即可：
```

func (i *Handle) doCmdwithResponse(s *Service, d *Destination, cmd uint8) ([][]byte, error) {
	req := newIPVSRequest(cmd)
	req.Seq = atomic.AddUint32(&i.seq, 1)

	if s == nil {
		req.Flags |= syscall.NLM_F_DUMP                    //Flag to dump all messages
		req.AddData(nl.NewRtAttr(ipvsCmdAttrService, nil)) //Add a dummy attribute
	} else {
		req.AddData(fillService(s))
	} // 把service塞到请求中

	if d == nil {
		if cmd == ipvsCmdGetDest {
			req.Flags |= syscall.NLM_F_DUMP
		}

	} else {
		req.AddData(fillDestinaton(d))
	}

    // 给内核进程发送service信息
	res, err := execute(i.sock, req, 0)
	if err != nil {
		return [][]byte{}, err
	}

	return res, nil
}
```
> 构造请求

```
func newIPVSRequest(cmd uint8) *nl.NetlinkRequest {
	return newGenlRequest(ipvsFamily, cmd)
}
```
在构造请求时传入的是ipvs协议簇

然后构造一个与内核通信的消息头
```
func NewNetlinkRequest(proto, flags int) *NetlinkRequest {
	return &NetlinkRequest{
		NlMsghdr: syscall.NlMsghdr{
			Len:   uint32(syscall.SizeofNlMsghdr),
			Type:  uint16(proto),
			Flags: syscall.NLM_F_REQUEST | uint16(flags),
			Seq:   atomic.AddUint32(&nextSeqNr, 1),
		},
	}
}
```
> 给消息加Data,这个Data是个数组，需要实现两个方法：

```
type NetlinkRequestData interface {
	Len() int  // 长度
	Serialize() []byte // 序列化, 内核通信也需要一定的数据格式，service信息也需要实现
}
```
比如 header是这样序列化的, 一看愣住了，思考好久才看懂：
拆下看：
(*[unsafe.Sizeof(*hdr)]byte) 一个*[]byte类型，长度就是结构体大小
(unsafe.Pointer(hdr))把结构体转成byte指针类型
加个*取它的值
用[:]转成byte返回
```
func (hdr *genlMsgHdr) Serialize() []byte {
	return (*(*[unsafe.Sizeof(*hdr)]byte)(unsafe.Pointer(hdr)))[:]
}
```

> 发送service信息给内核

一个很普通的socket发送接收数据
```
func execute(s *nl.NetlinkSocket, req *nl.NetlinkRequest, resType uint16) ([][]byte, error) {
	var (
		err error
	)

	if err := s.Send(req); err != nil {
		return nil, err
	}

	pid, err := s.GetPid()
	if err != nil {
		return nil, err
	}

	var res [][]byte

done:
	for {
		msgs, err := s.Receive()
		if err != nil {
			return nil, err
		}
		for _, m := range msgs {
			if m.Header.Seq != req.Seq {
				continue
			}
			if m.Header.Pid != pid {
				return nil, fmt.Errorf("Wrong pid %d, expected %d", m.Header.Pid, pid)
			}
			if m.Header.Type == syscall.NLMSG_DONE {
				break done
			}
			if m.Header.Type == syscall.NLMSG_ERROR {
				error := int32(native.Uint32(m.Data[0:4]))
				if error == 0 {
					break done
				}
				return nil, syscall.Errno(-error)
			}
			if resType != 0 && m.Header.Type != resType {
				continue
			}
			res = append(res, m.Data)
			if m.Header.Flags&syscall.NLM_F_MULTI == 0 {
				break done
			}
		}
	}
	return res, nil
}
```

> Service 数据打包
这里比较细，核心思想就是内核只认一定格式的标准数据，我们把service信息按其标准打包发送给内核即可。
至于怎么打包的就不详细讲了。
```
func fillService(s *Service) nl.NetlinkRequestData {
	cmdAttr := nl.NewRtAttr(ipvsCmdAttrService, nil)
	nl.NewRtAttrChild(cmdAttr, ipvsSvcAttrAddressFamily, nl.Uint16Attr(s.AddressFamily))
	if s.FWMark != 0 {
		nl.NewRtAttrChild(cmdAttr, ipvsSvcAttrFWMark, nl.Uint32Attr(s.FWMark))
	} else {
		nl.NewRtAttrChild(cmdAttr, ipvsSvcAttrProtocol, nl.Uint16Attr(s.Protocol))
		nl.NewRtAttrChild(cmdAttr, ipvsSvcAttrAddress, rawIPData(s.Address))

		// Port needs to be in network byte order.
		portBuf := new(bytes.Buffer)
		binary.Write(portBuf, binary.BigEndian, s.Port)
		nl.NewRtAttrChild(cmdAttr, ipvsSvcAttrPort, portBuf.Bytes())
	}

	nl.NewRtAttrChild(cmdAttr, ipvsSvcAttrSchedName, nl.ZeroTerminated(s.SchedName))
	if s.PEName != "" {
		nl.NewRtAttrChild(cmdAttr, ipvsSvcAttrPEName, nl.ZeroTerminated(s.PEName))
	}
	f := &ipvsFlags{
		flags: s.Flags,
		mask:  0xFFFFFFFF,
	}
	nl.NewRtAttrChild(cmdAttr, ipvsSvcAttrFlags, f.Serialize())
	nl.NewRtAttrChild(cmdAttr, ipvsSvcAttrTimeout, nl.Uint32Attr(s.Timeout))
	nl.NewRtAttrChild(cmdAttr, ipvsSvcAttrNetmask, nl.Uint32Attr(s.Netmask))
	return cmdAttr
}
```

## 总结
Service总体来讲代码比较简单，但是觉得有些地方实现的有点绕，不够简单直接。 总体来说就是监听apiserver事件，然后比对 处理，定期也会去执行同步策略.
