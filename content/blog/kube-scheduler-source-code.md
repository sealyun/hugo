+++
author = "fanux"
date = "2018-11-06T10:54:24+02:00"
draft = false
title = "kubernetes源码分析之kube-scheduler - 从代码看原理"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
banner = "img/banners/banner-1.png"
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

> [kubernetes集群三步安装](https://sealyun.com/pro/products/)

# kube-scheduler源码分析

## 关于源码编译
我嫌弃官方提供的编译脚本太麻烦，所以用了更简单粗暴的方式编译k8s代码，当然官方脚本在编译所有项目或者夸平台编译以及realse时还是挺有用的。

在容器中编译：
```
docker run -v /work/src/k8s.io/kubernetes:/go/src/k8s.io/kubernetes golang:1.11.2 bash
```

在容器中可以保证环境干净

进入bash后直接进入kube-scheduler的主目录编译即可
<!--more-->

```
cd cmd/kube-scheduler && go build
```

二进制就产生了。。。

### 源码编译接入CI/CD
作为高端玩家，自动化是必须的，因为服务器性能更好，用CI/CD编译更快，这里分享一下我的一些配置:

1. 我把vendor打到编译的基础镜像里了，因为vendor大而且不经常更新

```
$ cat Dockerfile-build1.12.2
FROM golang:1.11.2
COPY vendor/ /vendor
```
然后代码里的vendor就可以删了

2. .drone.yml

```
workspace:
  base: /go/src/k8s.io
  path: kubernetes

pipeline:
    build:
        image: fanux/kubernetes-build:1.12.2-beta.3
        commands:
           - make all WHAT=cmd/kube-kubescheduler GOFLAGS=-v
    publish:
        image: plugins/docker
        registry: xxx
        username: xxx
        password: xxx
        email: xxx
        repo: xxx/container/kube-scheduler
        tags: ${DRONE_TAG=latest}
        dockerfile: dockerfile/Dockerfile-kube-scheduler
        insecure: true
        when:
            event: [push, tag]
```

3. Dockerfile 静态编译连基础镜像都省了

```
$ cat dockerfile/Dockerfile-kube-scheduler
FROM scratch
COPY  _output/local/bin/linux/amd64/kube-scheduler /
CMD ["/kube-scheduler"]
```

对于kubeadm这种二进制交付的，可直接编译然后传到nexus上, 通过drone deploy事件选择是不是要编译kubeadm：

```
    build_kubeadm:
        image: fanux/kubernetes-build:1.12.2-beta.3
        commands:
           - make all WHAT=cmd/kube-kubeadm GOFLAGS=-v
           - curl -v -u container:container --upload-file kubeadm http://172.16.59.153:8081/repository/kubernetes/kubeadm/
        when:
            event: deployment
            enviroment: kubeadm
```

### 直接go build的大坑
发现build完的kubeadm二进制并不能用，可能是build时选用的基础镜像的问题，也可能是没去生成一些代码导致的问题
```
[signal SIGSEGV: segmentation violation code=0x1 addr=0x63 pc=0x7f2b7f5f057c]

runtime stack:
runtime.throw(0x17c74a8, 0x2a)
	/usr/local/go/src/runtime/panic.go:608 +0x72
runtime.sigpanic()
	/usr/local/go/src/runtime/signal_unix.go:374 +0x2f2
```

后面再补上CD的配置

如此我编译scheduler代码大约40秒左右，如vendor可软连接还可节省十几秒


# 调度器cache
## cache状态机
```
   +-------------------------------------------+  +----+
   |                            Add            |  |    |
   |                                           |  |    | Update
   +      Assume                Add            v  v    |
Initial +--------> Assumed +------------+---> Added <--+
   ^                +   +               |       +
   |                |   |               |       |
   |                |   |           Add |       | Remove
   |                |   |               |       |
   |                |   |               +       |
   +----------------+   +-----------> Expired   +----> Deleted
```

* Assume 尝试调度，会把node信息聚合到node上，如pod require多少CPU内存，那么加到node上，如果超时了需要重新减掉 
* AddPod 会检测是不是已经尝试调度了该pod，校验是否过期,如果过期了会被重新添加
* Remove pod信息会在该节点上被清除掉
* cache其它接口如node相关的cache接口  ADD update等

## cache实现
```
type schedulerCache struct {
	stop   <-chan struct{}
	ttl    time.Duration
	period time.Duration

	// This mutex guards all fields within this cache struct.
	mu sync.RWMutex
	// a set of assumed pod keys.
	// The key could further be used to get an entry in podStates.
	assumedPods map[string]bool
	// a map from pod key to podState.
	podStates map[string]*podState
	nodes     map[string]*NodeInfo
	nodeTree  *NodeTree
	pdbs      map[string]*policy.PodDisruptionBudget
	// A map from image name to its imageState.
	imageStates map[string]*imageState
}
```

这里存储了基本调度所需要的所有信息

以AddPod接口为例，本质上就是把监听到的一个pod放到了cache的map里：

```
cache.addPod(pod)
ps := &podState{
	pod: pod,
}
cache.podStates[key] = ps
```

node Tree
节点信息有这样一个结构体保存：

```
type NodeTree struct {
	tree      map[string]*nodeArray // a map from zone (region-zone) to an array of nodes in the zone.
	zones     []string              // a list of all the zones in the tree (keys)
	zoneIndex int
	NumNodes  int
	mu        sync.RWMutex
}
```

cache 运行时会循环清理过期的assume pod

```
func (cache *schedulerCache) run() {
	go wait.Until(cache.cleanupExpiredAssumedPods, cache.period, cache.stop)
}
```

# scheduler
scheduler里面最重要的两个东西：cache 和调度算法
```
type Scheduler struct {
	config *Config  -------> SchedulerCache
                       |
                       +---> Algorithm
}
```

等cache更新好了，调度器就是调度一个pod:
```
func (sched *Scheduler) Run() {
	if !sched.config.WaitForCacheSync() {
		return
	}

	go wait.Until(sched.scheduleOne, 0, sched.config.StopEverything)
}
```

核心逻辑来了：

```
   +-------------+
   | 获取一个pod |
   +-------------+
          |
   +-----------------------------------------------------------------------------------+
   | 如果pod的DeletionTimestamp 存在就不用进行调度, kubelet发现这个字段会直接去删除pod |
   +-----------------------------------------------------------------------------------+
          |
   +-----------------------------------------+
   | 选一个suggestedHost，可理解为合适的节点 |
   +-----------------------------------------+
          |_____________选不到就进入强占的逻辑，与我当初写swarm调度器逻辑类似
          |
   +--------------------------------------------------------------------------------+
   | 虽然还没真调度到node上，但是告诉cache pod已经被调度到node上了，变成assume pod  |
   | 这里面会先检查volumes                                                          |
   | 然后：err = sched.assume(assumedPod, suggestedHost) 假设pod被调度到node上了    |
   +--------------------------------------------------------------------------------+
          |
   +---------------------------+
   | 异步的bind这个pod到node上 |
   | 先bind volume             |
   | bind pod                  |
   +---------------------------+
          |
   +----------------+
   | 暴露一些metric |
   +----------------+
```

## bind动作：

```
err := sched.bind(assumedPod, &v1.Binding{
	ObjectMeta: metav1.ObjectMeta{Namespace: assumedPod.Namespace, Name: assumedPod.Name, UID: assumedPod.UID},
	Target: v1.ObjectReference{
		Kind: "Node",
		Name: suggestedHost,
	},
})
```

先去bind pod，然后告诉cache bind结束
```
err := sched.config.GetBinder(assumed).Bind(b)
if err := sched.config.SchedulerCache.FinishBinding(assumed); 
```

### bind 流程
```
   +----------------+
   | GetBinder.Bind
   +----------------+
       |
   +-------------------------------------+
   | 告诉cache bind完成 FinishBinding接口
   +-------------------------------------+
       |
   +-----------------------------------------------------+
   | 失败了就ForgetPod, 更新一下pod状态为 BindingRejected
   +-----------------------------------------------------+
```

### bind 实现
最终就是调用了apiserver bind接口:
```
func (b *binder) Bind(binding *v1.Binding) error {
	glog.V(3).Infof("Attempting to bind %v to %v", binding.Name, binding.Target.Name)
	return b.Client.CoreV1().Pods(binding.Namespace).Bind(binding)
}
```


## 调度算法

```
▾ algorithm/
  ▸ predicates/  预选
  ▸ priorities/  优选
```

现在最重要的就是选节点的实现

```
suggestedHost, err := sched.schedule(pod)
```

也就是调度算法的实现：

```
type ScheduleAlgorithm interface {
    // 传入pod 节点列表，返回一下合适的节点
	Schedule(*v1.Pod, NodeLister) (selectedMachine string, err error)
    // 资源抢占用的
	Preempt(*v1.Pod, NodeLister, error) (selectedNode *v1.Node, preemptedPods []*v1.Pod, cleanupNominatedPods []*v1.Pod, err error)

    // 预选函数集，
	Predicates() map[string]FitPredicate
                                |                              这一个节点适合不适合调度这个pod，不适合的话返回原因
                                +-------type FitPredicate func(pod *v1.Pod, meta PredicateMetadata, nodeInfo *schedulercache.NodeInfo) (bool, []PredicateFailureReason, error)
    // 返回优选配置,最重要两个函数 map 和 reduce
	Prioritizers() []PriorityConfig
                         |____________PriorityMapFunction 计算 节点的优先级
                         |____________PriorityReduceFunction 根据map的结果计算所有node的最终得分
                         |____________PriorityFunction 废弃
}
```


调度算法可以通过两种方式生成： 

* Provider 默认方式, 通用调度器
* Policy   策略方式, 特殊调度器

最终new了一个scheduler:

```
priorityConfigs, err := c.GetPriorityFunctionConfigs(priorityKeys)
priorityMetaProducer, err := c.GetPriorityMetadataProducer()
predicateMetaProducer, err := c.GetPredicateMetadataProducer()
                                              |
algo := core.NewGenericScheduler(             |
	c.schedulerCache,                         |
	c.equivalencePodCache,                    V
	c.podQueue,
	predicateFuncs,   ============> 这里面把预选优选函数都注入进来了
	predicateMetaProducer,
	priorityConfigs,
	priorityMetaProducer,
	extenders,
	c.volumeBinder,
	c.pVCLister,
	c.alwaysCheckAllPredicates,
	c.disablePreemption,
	c.percentageOfNodesToScore,
)


type genericScheduler struct {
	cache                    schedulercache.Cache
	equivalenceCache         *equivalence.Cache
	schedulingQueue          SchedulingQueue
	predicates               map[string]algorithm.FitPredicate
	priorityMetaProducer     algorithm.PriorityMetadataProducer
	predicateMetaProducer    algorithm.PredicateMetadataProducer
	prioritizers             []algorithm.PriorityConfig
	extenders                []algorithm.SchedulerExtender
	lastNodeIndex            uint64
	alwaysCheckAllPredicates bool
	cachedNodeInfoMap        map[string]*schedulercache.NodeInfo
	volumeBinder             *volumebinder.VolumeBinder
	pvcLister                corelisters.PersistentVolumeClaimLister
	disablePreemption        bool
	percentageOfNodesToScore int32
}
```
这个scheduler实现了ScheduleAlgorithm中定义的接口

Schedule 流程：

```
   +------------------------------------+
   | trace记录一下，要开始调度哪个pod了 | 
   +------------------------------------+
          |
   +-----------------------------------------------+
   | pod基本检查，这里主要检查卷和delete timestamp |
   +-----------------------------------------------+
          |
   +----------------------------------------+
   | 获取node列表, 更新cache的node info map |
   +----------------------------------------+
          |
   +----------------------------------------------+
   | 预选，返回合适的节点列表和预选失败节点的原因 |
   +----------------------------------------------+
          |
   +----------------------------------------------------------+
   | 优选，                                                   |
   | 如果预选结果只有一个节点，那么直接使用之，不需要进行优选 |
   | 否则进行优选过程                                         |
   +----------------------------------------------------------+
          |
   +------------------------------------+
   | 在优选结果列表中选择得分最高的节点 |
   +------------------------------------+
```

### 预选
主要分成两块

* 预选, 检查该节点符合不符合
* 执行extender, 自定义调度器扩展，官方实现了HTTP extender 把预选结果发给用户，用户再去过滤

podFitOnNode: 判断这个节点是不是适合这个pod调度

这里插播一个小知识，调度器里有个Ecache:

Equivalence Class目前是用来在Kubernetes Scheduler加速Predicate，提升Scheduler的吞吐性能。
Kubernetes scheduler及时维护着Equivalence Cache的数据，当某些情况发生时（比如delete node、bind pod等事件），
需要立刻invalid相关的Equivalence Cache中的缓存数据。

一个Equivalence Class是用来定义一组具有相同Requirements和Constraints的Pods的相关信息的集合，
在Scheduler进行Predicate阶段时可以只需对Equivalence Class中一个Pod进行Predicate，并把Predicate的结果放到
Equivalence Cache中以供该Equivalence Class中其他Pods（成为Equivalent Pods）重用该结果。只有当Equivalence Cache
中没有可以重用的Predicate Result才会进行正常的Predicate流程。

ecache这块后续可以深入讨论，本文更多关注核心架构与流程

所以这块就比较简单了, 把所有的预选函数执行行一遍

```
先排序 predicates.Ordering() 
if predicate, exist := predicateFuncs[predicateKey]; exist {
		fit, reasons, err = predicate(pod, metaToUse, nodeInfoToUse)
```

顺序是这样的：

```
	predicatesOrdering = []string{CheckNodeConditionPred, CheckNodeUnschedulablePred,
		GeneralPred, HostNamePred, PodFitsHostPortsPred,
		MatchNodeSelectorPred, PodFitsResourcesPred, NoDiskConflictPred,
		PodToleratesNodeTaintsPred, PodToleratesNodeNoExecuteTaintsPred, CheckNodeLabelPresencePred,
		CheckServiceAffinityPred, MaxEBSVolumeCountPred, MaxGCEPDVolumeCountPred, MaxCSIVolumeCountPred,
		MaxAzureDiskVolumeCountPred, CheckVolumeBindingPred, NoVolumeZoneConflictPred,
		CheckNodeMemoryPressurePred, CheckNodePIDPressurePred, CheckNodeDiskPressurePred, MatchInterPodAffinityPred}
```

这些预选函数是存在一个map里的，key是一个string，value就是一个预选函数, 再回头去看注册map的逻辑

```
predicateFuncs, err := c.GetPredicates(predicateKeys)
```
pkg/scheduler/algorithmprovider/defaults/defaults.go 里面会对这些函数进行注册,如：

```
factory.RegisterFitPredicate(predicates.NoDiskConflictPred, predicates.NoDiskConflict),
factory.RegisterFitPredicate(predicates.GeneralPred, predicates.GeneralPredicates),
factory.RegisterFitPredicate(predicates.CheckNodeMemoryPressurePred, predicates.CheckNodeMemoryPressurePredicate),
factory.RegisterFitPredicate(predicates.CheckNodeDiskPressurePred, predicates.CheckNodeDiskPressurePredicate),
factory.RegisterFitPredicate(predicates.CheckNodePIDPressurePred, predicates.CheckNodePIDPressurePredicate),
```

然后直接在init函数里调用注册逻辑

### 优选
PrioritizeNodes 优选大概可分为三个步骤:

* Map      计算单个节点,优先级
* Reduce   计算每个节点结果聚合,计算所有节点的最终得分
* Extender 与预选差不多

优选函数同理也是注册进去的, 不再赘述
```
factory.RegisterPriorityFunction2("LeastRequestedPriority", priorities.LeastRequestedPriorityMap, nil, 1),
// Prioritizes nodes to help achieve balanced resource usage
factory.RegisterPriorityFunction2("BalancedResourceAllocation", priorities.BalancedResourceAllocationMap, nil, 1),
```

这里注册时注册两个，一个map函数一个reduce函数，为了更好的理解mapreduce，去看一个实现
```
factory.RegisterPriorityFunction2("NodeAffinityPriority", priorities.CalculateNodeAffinityPriorityMap, priorities.CalculateNodeAffinityPriorityReduce, 1)
```
### node Affinity map reduce
map 核心逻辑, 比较容易理解:
```
如果满足节点亲和，积分加权重
count += preferredSchedulingTerm.Weight

return schedulerapi.HostPriority{
	Host:  node.Name,
	Score: int(count),  # 算出积分
}, nil
```

reduce:
一个节点会走很多个map，每个map会产生一个分值，如node affinity产生一个，pod affinity再产生一个，所以node和分值是一对多的关系

去掉reverse的逻辑（分值越高优先级越低）
```
var maxCount int
for i := range result {
	if result[i].Score > maxCount {
		maxCount = result[i].Score  # 所有分值里的最大值
	}
}

for i := range result {
	score := result[i].Score
	score = maxPriority * score / maxCount  # 分值乘以最大优先级是maxPriority = 10，除以最大值赋值给分值 这里是做了归一化处理;
	result[i].Score = score
}
```
这里做了归一化处理后分值就变成[0,maxPriority]之间了

```
for i := range priorityConfigs {
	if priorityConfigs[i].Function != nil {
		continue
	}
	results[i][index], err = priorityConfigs[i].Map(pod, meta, nodeInfo)
	if err != nil {
		appendError(err)
		results[i][index].Host = nodes[index].Name
	}
}

err := config.Reduce(pod, meta, nodeNameToInfo, results[index]); 
```
看这里有个results,对理解很重要，是一个二维数组：

|xxx|node1|node2|node3|
|---|---|---|---|
|nodeaffinity|1分|2分|1分|
|pod affinity|1分|3分|6分|
|...|...|...|...|

这样reduce时取一行，其实也就是处理所有节点的某项得分

```
result[i].Score += results[j][i].Score * priorityConfigs[j].Weight  (二维变一维)

```
reduce完最终这个节点的得分就等于这个节点各项得分乘以该项权重的和,最后排序选最高分 (一维变0纬)

# 调度队列 SchedulingQueue
scheduler配置里有一个`NextPod` 方法，获取一个pod，并进行调度：
```
pod := sched.config.NextPod()
```
配置文件在这里初始化：
```
pkg/scheduler/factory/factory.go
NextPod: func() *v1.Pod {
	return c.getNextPod()
},

func (c *configFactory) getNextPod() *v1.Pod {
	pod, err := c.podQueue.Pop()
	if err == nil {
		return pod
	}
...
}
```

队列接口：
```
type SchedulingQueue interface {
	Add(pod *v1.Pod) error
	AddIfNotPresent(pod *v1.Pod) error
	AddUnschedulableIfNotPresent(pod *v1.Pod) error
	Pop() (*v1.Pod, error)
	Update(oldPod, newPod *v1.Pod) error
	Delete(pod *v1.Pod) error
	MoveAllToActiveQueue()
	AssignedPodAdded(pod *v1.Pod)
	AssignedPodUpdated(pod *v1.Pod)
	WaitingPodsForNode(nodeName string) []*v1.Pod
	WaitingPods() []*v1.Pod
}
```
给了两种实现，优先级队列和FIFO ：
```
func NewSchedulingQueue() SchedulingQueue {
	if util.PodPriorityEnabled() {
		return NewPriorityQueue()  # 基于堆排序实现，根据优先级排序
	}
	return NewFIFO() # 简单的先进先出
}
```

队列实现比较简单，不做深入分析, 更重要的是关注队列，调度器，cache之间的关系:

```
AddFunc:    c.addPodToCache,
UpdateFunc: c.updatePodInCache,
DeleteFunc: c.deletePodFromCache,
            | informer监听,了pod创建事件之后往cache和队列里都更新了
            V 
if err := c.schedulerCache.AddPod(pod); err != nil {
	glog.Errorf("scheduler cache AddPod failed: %v", err)
}

c.podQueue.AssignedPodAdded(pod)
```
```
+------------+ ADD   +-------------+   POP  +-----------+
| informer   |------>|  sche Queue |------->| scheduler |
+------------+   |   +-------------+        +----^------+
                 +-->+-------------+             |
                     | sche cache  |<------------+
                     +-------------+
```

# Extender
## 调度器扩展
定制化调度器有三种方式：

* 改scheduler代码重新编译 - 没啥可讨论
* 重写调度器，调度时选择调度器 - 比较简单，问题是没法与默认调度器共同作用
* 写调度器扩展（extender）让k8s调度完了 把符合的节点扔给你 你再去过滤和优选 - 重点讨论，新版本做了一些升级，老的方式可能都无用了 [资料](https://github.com/kubernetes/community/blob/master/contributors/design-proposals/scheduling/scheduler_extender.md)
* 这里有个调度器扩展[事例](https://github.com/everpeace/k8s-scheduler-extender-example)

目前第三点资料非常少，很多细节需要在代码里找到答案，带着问题看代码效果更好。


## Extender接口
```
+----------------------------------+       +----------+
| kube-scheduler -> extender client|------>| extender | (你需要开发的扩展，单独的进程)
+----------------------------------+       +----------+
```

这个接口是kube-scheduler实现的，下面会介绍HTTPextender的实现
```
type SchedulerExtender interface {
    // 最重要的一个接口，输入pod和节点列表，输出是符合调度的节点的列表
	Filter(pod *v1.Pod,
		nodes []*v1.Node, nodeNameToInfo map[string]*schedulercache.NodeInfo,
	) (filteredNodes []*v1.Node, failedNodesMap schedulerapi.FailedNodesMap, err error)

    // 这个给节点打分的，优选时需要用的
	Prioritize(pod *v1.Pod, nodes []*v1.Node) (hostPriorities *schedulerapi.HostPriorityList, weight int, err error)

    // Bind接口主要是最终调度器选中节点哪个节点时通知extender
	Bind(binding *v1.Binding) error

	// IsBinder returns whether this extender is configured for the Bind method.
	IsBinder() bool

    // 可以过滤你感兴趣的pod 比如按照标签
	IsInterested(pod *v1.Pod) bool

	// ProcessPreemption returns nodes with their victim pods processed by extender based on
	// given:
	//   1. Pod to schedule
	//   2. Candidate nodes and victim pods (nodeToVictims) generated by previous scheduling process.
	//   3. nodeNameToInfo to restore v1.Node from node name if extender cache is enabled.
	// The possible changes made by extender may include:
	//   1. Subset of given candidate nodes after preemption phase of extender.
	//   2. A different set of victim pod for every given candidate node after preemption phase of extender.
    // 我猜是与亲和性相关的功能，不太清楚 TODO
	ProcessPreemption(
		pod *v1.Pod,
		nodeToVictims map[*v1.Node]*schedulerapi.Victims,
		nodeNameToInfo map[string]*schedulercache.NodeInfo,
	) (map[*v1.Node]*schedulerapi.Victims, error)

    // 优先级抢占特性，可不实现
	SupportsPreemption() bool

    // 当访问不到extender时怎么处理，返回真时extender获取不到时调度不能失败
	IsIgnorable() bool
}
```

官方实现了HTTPextender，可以看下：
```
type HTTPExtender struct {
	extenderURL      string
	preemptVerb      string
	filterVerb       string  # 预选RUL
	prioritizeVerb   string  # 优选RUL
	bindVerb         string
	weight           int
	client           *http.Client
	nodeCacheCapable bool
	managedResources sets.String
	ignorable        bool
}
```

看其预选和优选逻辑：

```
args = &schedulerapi.ExtenderArgs{  # 调度的是哪个pod，哪些节点符合调度条件, 返回的也是这个结构体
	Pod:       pod,
	Nodes:     nodeList,
	NodeNames: nodeNames,
}

if err := h.send(h.filterVerb, args, &result); err != nil { # 发了个http请求给extender(你要去实现的httpserver), 返回过滤后的结构
	return nil, nil, err
}
```

## HTTPExtender配置参数从哪来

## scheduler extender配置：

```
NamespaceSystem string = "kube-system"

SchedulerDefaultLockObjectNamespace string = metav1.NamespaceSystem

// SchedulerPolicyConfigMapKey defines the key of the element in the
// scheduler's policy ConfigMap that contains scheduler's policy config.
SchedulerPolicyConfigMapKey = "policy.cfg"
```

## 总结
调度器的代码写的还是挺不错的，相比较于kube-proxy好多了，可扩展性也还可以，不过目测调度器会面临一次大的重构，现阶段调度器对深度学习的批处理任务支持就不好
而one by one调度的这种设定关系到整个项目的架构，要想优雅的支持更优秀的调度估计重构是跑不掉了

