+++
author = "fanux"
date = "2018-12-25T10:54:24+02:00"
draft = false
title = "kube-scheduler定制，支持深度学习批处理任务调度"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

> [kubernetes集群三步安装](https://sealyun.com/pro/products/)

# 什么是批处理任务
深度学习中经常会出现多机多卡的任务，也就是同事会起多个pod，但是这多个pod属于同一个任务。

这样就会有一个问题

一个任务要起100个pod，每个pod需要一张卡，总共需要100张GPU卡，而集群中只有99张空闲的GPU卡，这样默认的k8s调度器会如何处理？

因为默认调度器是一个一个pod调度的，只会检查单个pod资源够不够，这样前99个都能成功，最后一个pod调度失败。  

这样非常有可能造成 

1. 任务跑不了  
2. 前99个占着GPU不释放，新的任务无法调度 
3. 严重时整个集群死锁，都“占着茅坑不拉屎”

所以需要在调度时对整个task所需所有资源进行检查，当集群总体资源不够时，一个pod都得不到调度。

社区提供了一个能支持这种特性的[调度器](https://github.com/kubernetes-sigs/kube-batch/blob/master/doc/usage/tutorial.md)
但是这个调度器是没办法和原生调度器很好的配合工作的

1. 最大的问题在于两个调度器都有cache，这样cache的内容会冲突，导致调度混乱
2. 这个调度器没法和原生调度器同时起作用，这样用了这个batch调度器后就没法用亲和性什么的特性了

所以我们做的事是将两者特性融合，选择的方法是定制化开发kube-scheduler

其实scheduler是可以通过extender扩展的，但是extender还是太弱了，它仅能在预选和优选过程中加入自己的过滤策略，而这对于批处理任务远远不够。

# 实现难点

> 需要优选时加batch任务检查
拿到一个pod ---> 如果是一个batchpod ---> 查询集群资源是否满足batch任务--->否调度失败

> 需要保障batch任务中其它pod能得到调度

如果集群资源能满足这个batch任务直接去bind有个问题：
假设调度队列是这样,假设集群中有三个GPU，而batch任务需要三个GPU：

|A batch pod ->| pod -> |pod -> |A batch pod -> |A batch pod|
| --- | --- | --- | --- | --- |
|集群资源够 调度成功  |    调度了别的pod |调度了别的pod| GPU被别的pod占用 GPU不够 失败   | GPU不够 失败 |


                
所以最终结果是A批任务占用了一个GPU但是整个任务是调度失败的，那一个GPU还得不到释放

所以需要修改pod调度队列里的顺序?让A batch pod连续调度? 没这么简单，

pod调度是创建协程并发调度的，这样即便去调整任务队列里pod的顺序也不一定能保证batch任务其它pod能得到优先调度。
```
go wait.Until(sched.scheduleOne, 0, sched.config.StopEverything)
```

> 只要batch pod走到Bind逻辑了就没有回头路了

batch任务中所有pod先进行assume调度，其中任意一个失败就清理掉其它已经bind但是还没实际进行调度的pod。 并把所有pod扔回队列，或者直接返回调度失败清理改任务的pod，让上层重新触发?

scheduler流程 scheduler/sheduler.go scheduleOne逻辑：

选节点->cache assume pod on node-> 创建协程bind

所以在assume时去检查，不满足退还已经调度的pod是不可行的，因为之前batch任务中的pod可能已经bind过了， 所以只能batch任务中最后一个pod得到确认才能去bind前面的pod

> 预占用策略
预占用策略： 第一个batch pod任务来时，检查集群资源是不是够，如果够进行预占，把其它几个node打上标记，让接下来pod无法占用其它的node，这样batch任务其实pod过来就有节点可用。

回到了不能bind的问题。。。

这种问题有两点：

如何知道batch任务中其它pod需要什么样的节点，如果pod都一样问题可简化
如果后面的pod失败了，第一个pod还是已经bind，还是会出现一样的问题
最终还是在所有pod assume之前不能bind单个pod

综上，需要在几个地方处理

队列最好用优先级队列，把正在调度的pod的关联pod优先级提高
选节点时做判断，看集群资源是否够
选好节点assume pod时检查，如果自己不够或者pod组不够就不去bind
问题是之前的pod已经走了bind流程，所以最重要的是如何解决让之前的pod不去bind，延迟bind

> 最终方案 - 延迟绑定

方案：在batch任务bind时进行特殊处理

1. 如果是batch任务扔进task cache，不进行binding
2. 如果batch任务最后一个pod扔进task cache,该task ready，放进bind队列
3. 在bind队列里取task 进行bind，task互斥锁与普通pod bind时互斥

> 使用
batch任务使用，pod增加两个注解：

```
      annotations:
        scheduling.k8s.io/group-name: qj-1
        scheduling.k8s.io/group-pod-num: 3
```
pod加上这两个注解表示属于同一个task, num表示task里有多少pod。

本来是再定义一个CRD去描述这个task，耦合会小一些，但是实现麻烦些，需要多监听一个CRD，偷懒就没这样做

# 实现
延迟绑定流程：
![](/batch-scheduler-flow.png)

* 如果是普通的pod，找到节点后assume就直接bind
* 如果是批处理任务，直接扔到批处理缓存中返回
* 有个协程一直检查批缓存中是否有成功的task (pod都齐了)
* 成功的task扔进binding队列，worker取成功的task进行批量绑定，绑定时与普通pod互斥

batch scheduler接口与成员
![](/batch-scheduler.png)

Run 起一个协程检查成功的task并塞入队列
RunBind 起一个task绑定协程
PodQuePriority 去动态修改pod队列的优先级，让同task的pod优先调度

执行流程：
![](batch-scheduler-run.png)

## 延迟绑定
scheduler/scheduler.go:

```
	//fanux if it is a batch pod, return
	if sched.Config.BatchScheduler.IsBatchPod(assumedPod) {
		err = sched.Config.BatchScheduler.HandleBatchPod(assumedPod)
		if err != nil {
			glog.Errorf("schedule batch pod failed: %v", assumedPod.Namespace, assumedPod.Name)
		}
		return
	}
```

增加绑定互斥，防止batch任务和普通pod同事binding:

```
	go func() {
		//fanux add bind mutex
		sched.Config.BatchScheduler.Lock()
		defer sched.Config.BatchScheduler.UnLock()

		err := sched.bind(assumedPod, &v1.Binding{
```

## 检查资源是否充足CheckResourceIsEnough

should't use filterFunc, needs nodelist

scheduler/util/batch.go
```
package util

import "api/core/v1"

//CheckResourceIsEnough is
func CheckResourceIsEnough(pod *v1.Pod, nodes []*v1.Node) (bool, error) {
	return false, nil
}
```

scheduler/core/generic_scheduler.go
```
	//fanux add checkBatchPodResource
	flag, err := util.CheckResourceIsEnough(pod, filteredNodes)
	if !flag || err != nil {
		return "", err
	}

	trace.Step("Prioritizing")
```

处理资源不足时的情况
```
	suggestedHost, err := sched.schedule(pod)

	//fanux add handle if resource not enough
	if strings.Contains(err.Error(), common.BatchResourceNotEnough) {
		sched.Config.BatchScheduler.HandleResourceNotEnough(pod)
	} else if err != nil {
```

## 如何获取节点已经分配GPU的数量
nodeInfo allocatableResource - requestedResource is avaliavle resource
```
	requestedResource *Resource
	nonzeroRequest    *Resource
	allocatableResource *Resource
```
GPU 是 ScalarResources, 资源名称叫 : `NVIDIAGPUResourceName = "nvidia.com/gpu"`
```
type Resource struct {
	MilliCPU         int64
	Memory           int64
	EphemeralStorage int64
	// We store allowedPodNumber (which is Node.Status.Allocatable.Pods().Value())
	// explicitly as int, to avoid conversions and improve performance.
	AllowedPodNumber int
	// ScalarResources
	ScalarResources map[v1.ResourceName]int64
}
```

## 增加podupdater，可更新podcondition状态
```
	batchScheduler := batch.NewBatchScheduler(c.schedulerCache, c.podQueue, &binder{c.client}, &podConditionUpdater{c.client})
```

## 需要把batch scheduler的cache给generic_scheduler资源检查时需要用

需要知道已经有哪些pod已经assume过了，把这个数量减掉才是batch任务还需要多少GPU

core/generic_scheduler.go
```
	//fanux add batch Cache
	//check batch pod resource is enough need batch scheduler cache
	BatchCache common.TaskCache
```
```
	//fanux add checkBatchPodResource
	flag, err := common.CheckResourceIsEnough(pod, filteredNodes, g.cachedNodeInfoMap, g.BatchCache)
```

factory.go
```
	//fanux check batch resource is enough need batch scheduler cache
	batchCache := batchScheduler.GetTaskCache()

	algo := core.NewGenericScheduler(
        ...
		batchCache,
	)
```
then checkresource :
```
	//shoud not use metadata, need use metadata - assumed pod num in batch cache
	_, podNum := GetPodBathMeta(pod)
	podNum -= batchCache.GetTaskAssumedPodNum(pod)
```

## 检查资源是否充足详细算法：
有很多细节
```
//获取pod需要多少GPU，这个需要把pod里容器配额加起来
func GetPodGPUCount(pod *v1.Pod) (count int) {
	for _, c := range pod.Spec.Containers {
		limit, ok := c.Resources.Limits[NVIDIAGPUResourceName]
		l, okay := limit.AsInt64()
		if !ok || !okay {
			continue
		}
		count += int(l)
	}

	glog.Infof("Pod [%s] need GPU [%d]", pod.GetName(), count)

	return
}

//获取节点空闲GPU，需要把可分配的减去已经申请的
func GetNodeFreeGPU(nodeInfo *cache.NodeInfo) int {
	if nodeInfo == nil {
		return 0
	}

	allocatable, ok := nodeInfo.AllocatableResource().ScalarResources[NVIDIAGPUResourceName]
	if !ok {
		glog.Errorf("can't fetch allocatable GPU : %v", nodeInfo)
		return 0
	}
	glog.Infof("node [%s] allocatable GPU [%d]", nodeInfo.Node().Name, allocatable)

	requested, ok := nodeInfo.RequestedResource().ScalarResources[NVIDIAGPUResourceName]
	if !ok {
		//glog.Errorf("can't fetch requested GPU : %v", nodeInfo)
		//return 0
		requested = 0
	}
	glog.Infof("node [%s] requested GPU [%d]", nodeInfo.Node().Name, requested)

	available := allocatable - requested

	glog.Infof("available node [%s] GPU : [%d]", nodeInfo.Node().Name, available)

	return int(available)
}

//这里最关键的点是需要把annotations里面获取的task pod总数减去已经assume过的batch pod，这样才是真实所需
func CheckResourceIsEnough(pod *v1.Pod, nodes []*v1.Node, cachedNodeInfoMap map[string]*cache.NodeInfo, batchCache TaskCache) (bool, error) {
	//if is not batch pod, return true,nil
	if !IsBatch(pod) {
		glog.Infof("pod %s is not batch pod", pod.GetName())
		return true, nil
	}

	//shoud not use metadata, need use metadata - ready pod num in batch cache
	_, podNum := GetPodBathMeta(pod)
	podNum -= batchCache.GetTaskAssumedPodNum(pod)

	everyPodNeedsGPU := GetPodGPUCount(pod)
	if everyPodNeedsGPU == 0 {
		glog.Infof("pod %s require 0 GPU", pod.GetName())
		return true, nil
	}

	// TODO maybe check nodes[1:], node[0] already allocate a pod, CPU and other metric may reach limit
	for _, node := range nodes {
		nodeInfo, ok := cachedNodeInfoMap[node.Name]
		if !ok {
			continue
		}
		nodeFree := GetNodeFreeGPU(nodeInfo)
		podNum -= nodeFree / everyPodNeedsGPU
		glog.Infof("pod: [%s] node: [%s] podNum [%d] nodeFree [%d] podNeed [%d]", pod.GetName(), node.Name, podNum, nodeFree, everyPodNeedsGPU)
		if podNum <= 0 {
			return true, nil
		}
	}

	return false, fmt.Errorf("BatchResourceNotEnough : pod name is %s", pod.GetName())
}

//判断是不是batch pod
func IsBatch(pod *v1.Pod) bool {
	g, n := GetPodBathMeta(pod)
	if g == "" || n == 0 {
		glog.Infof("The pod's group name is empty string,pod name is %v.", pod.GetName())
		return false
	}
	return true
}
```

# 关于GPU的使用与发现
[资源包](https://github.com/sealyun/GPU/releases)

这里包含docker nv-docker GPU-device plugin
```
install.sh...

/etc/docker/daemon.json
```
[root@compute-gpu006 ~]# cat /etc/docker/daemon.json
{
    "default-runtime":"nvidia",
    "runtimes": {
        "nvidia": {
            "path": "/usr/bin/nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
```

kubectl describe node xxx:
```
Capacity:
 cpu:                72
 ephemeral-storage:  222779Mi
 hugepages-1Gi:      0
 hugepages-2Mi:      2Gi
 memory:             791014684Ki
 nvidia.com/gpu:     2                # 这里就能看到GPU了
 pods:               110
Allocatable:
 cpu:                72
 ephemeral-storage:  210240641086
 hugepages-1Gi:      0
 hugepages-2Mi:      2Gi
 memory:             788815132Ki
 nvidia.com/gpu:     2
 pods:               110
```
```

# 总结
原生调度器的设计就是pod one by one，所以做这个功能的开发还是改动非常大的，也是比较困难的，工作量不大，但是需要找到一个优雅的方案，
合理的架构比较麻烦,想了很久做了这个侵入不太大的实现方案，欢迎大家一起讨论

# 公众号：
![sealyun](https://sealyun.com/kubernetes-qrcode.jpg)
