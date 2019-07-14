+++
author = "fanux"
date = "2019-05-23T10:54:24+02:00"
draft = false
title = "kubernetes Admission Controller原理介绍"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
banner = "img/banner-1.png"
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
banner = "/img/adminson-controller.png"
+++

> Admission Controller介绍

Apiserver干的最重要的三个事就是：

1. 认证 : 看是否是合法用户
2. 授权 : 看用户具备哪些权限
3. admission controller : 一个调用链，对请求进行控制或修改，比如是否允许这个请求。

admission controller非常有用，也是经常会用到的k8s的一个扩展方式，今天在源码级别对其做一下介绍，以及如何自己去开发一个admission controller.

   我们的应用场景是：我们希望把所有需要创建的pod都加上一个注解，因为我们早期是通过podpreset给pod注入lxcfs的配置的，但是用户在写yaml文件时很容易忘记加上，所以需要在apiserver上来个自动处理
<!--more-->

```
metadata:
  name: test-net
  annotations:
    initializer.kubernetes.io/lxcfs: "true"   # 就是在pod的metadata里加上这个配置
```

## 默认admission controller
已经有很多默认非常有用的admission插件，这里挑几个介绍一下：

名称|作用
---|---
AlwaysPullImages | 把所有镜像策略都调整成alwaysPull, 多租户安全时比较有用
DefaultStorageClass | 默认存储类型
DefaultTolerationSeconds | 节点notready:NoExecute时的容忍时间，比如有时我们升级kubelet，希望升级时pod不要漂移就会用到
DenyEscalatingExec | 拒绝远程连接容器
ExtendedResourceToleration | 比如我有扩展资源，那么我可以通过它来玷污节点，防止不需要该资源的pod到我的机器上来，如GPU
LimitRanger | 在多租户配额时相当有用，如果pod没配额，那么我可以默认给个很低的配额
NamespaceAutoProvision | 这个也非常有用，资源的namespace不存在时就创建一个
PodPreset | 可以对pod进行一些预处理设置
ResourceQuota | 多租户配额时比较重要，看资源是否满足resource quota中的配置

## alwaysPullImages 介绍
   多租户时经常会开启这个，强制所有的镜像必须去拉取，因为如果不这样，那么别的租户如果知道了你的镜像名就可以写一个yaml去启动你的镜像，强制拉时犹豫需要image pull secret所以无法拉取你的镜像。

   所以这个admission干的事就是把镜像拉取策略都改成alwaysPull：

代码位置：
```golang
kubernetes/plugin/pkg/admission/alwayspullimages/admission.go

func (a *AlwaysPullImages) Admit(attributes admission.Attributes, o admission.ObjectInterfaces) (err error) {
    // 你可以在attibutes里获取到对象的一切信息，用户信息等
	if shouldIgnore(attributes) { // 检查一下是不是你关注的object, 比如创建的一个configmap 那么显然可以忽视
		return nil
	}
	pod, ok := attributes.GetObject().(*api.Pod)

    // 这里把initContainer和Container的拉取策略都给改了
	for i := range pod.Spec.InitContainers {
		pod.Spec.InitContainers[i].ImagePullPolicy = api.PullAlways
	}

	for i := range pod.Spec.Containers {
		pod.Spec.Containers[i].ImagePullPolicy = api.PullAlways
	}

	return nil
}

# 还提供一个校验接口，看是不是真的都已经被改了
func (a *AlwaysPullImages) Validate(attributes admission.Attributes, o admission.ObjectInterfaces) (err error) {
	pod, ok := attributes.GetObject().(*api.Pod)
	for i := range pod.Spec.InitContainers {
		if pod.Spec.InitContainers[i].ImagePullPolicy != api.PullAlways {
			return admission.NewForbidden(attributes,
				field.NotSupported(field.NewPath("spec", "initContainers").Index(i).Child("imagePullPolicy"),
					pod.Spec.InitContainers[i].ImagePullPolicy, []string{string(api.PullAlways)},
				),
			)
		}
	}

    ...

	return nil
}
```

然后实现一个注册函数：
```golang
func Register(plugins *admission.Plugins) {
	plugins.Register(PluginName, func(config io.Reader) (admission.Interface, error) {
		return NewAlwaysPullImages(), nil
	})
}

type AlwaysPullImages struct {
	*admission.Handler
}
```

最后需要在plugin里面把其注册进去：
```
kubernetes/pkg/kubeapiserver/options/plugins.go

func RegisterAllAdmissionPlugins(plugins *admission.Plugins) {
	imagepolicy.Register(plugins)
    ...
}
```

所以实现一个admission非常简单，主要就是实现两个接口即可。

## admission control webhooks 
很多情况下我们并不希望大动干戈去改apiserver代码，所以apiserver提供了一种动态扩展admission的方式，非常推荐。

有两种类型：

1. validating admission Webhook  只作校验，比如检测到某个特殊字段就不让请求通过
2. mutating admission webhook    可以对请求体进行修改（patch）

比较重要的是这个AdmissionReview结构体，包含一个请求一个响应

请求：有Object的详细信息，用户信息
响应: 最重要的是 1. 是否允许  2. 修改（patch）的类型  3. 修改（patch）的值， 这个符合json patch标准 （kubectl patch）

可[在此](https://github.com/kubernetes/kubernetes/blob/v1.13.0/test/images/webhook/main.go) 找到一个webhook server的例子

看一个具体例子，labelpatch，是给对象的元数据里加一些label的。

```go
const (
    // 特定的json patch格式
	addFirstLabelPatch string = `[
         { "op": "add", "path": "/metadata/labels", "value": {"added-label": "yes"}}
     ]`
	addAdditionalLabelPatch string = `[
         { "op": "add", "path": "/metadata/labels/added-label", "value": "yes" }
     ]`
)

// Add a label {"added-label": "yes"} to the object
func addLabel(ar v1beta1.AdmissionReview) *v1beta1.AdmissionResponse {
	obj := struct {
		metav1.ObjectMeta
		Data map[string]string
	}{}
	raw := ar.Request.Object.Raw
	err := json.Unmarshal(raw, &obj)
	if err != nil {
		klog.Error(err)
		return toAdmissionResponse(err)
	}

	reviewResponse := v1beta1.AdmissionResponse{}
	reviewResponse.Allowed = true
	if len(obj.ObjectMeta.Labels) == 0 {
		reviewResponse.Patch = []byte(addFirstLabelPatch) // 这里最需要注意的就是修改时是通过patch的方式
	} else {
		reviewResponse.Patch = []byte(addAdditionalLabelPatch)
	}
	pt := v1beta1.PatchTypeJSONPatch
	reviewResponse.PatchType = &pt
	return &reviewResponse
}
```
把这个放到http handle里。

把这个HTTPS服务起一个service, 这样apiserver就可以自动发现它。

```
apiVersion: admissionregistration.k8s.io/v1beta1
kind: ValidatingWebhookConfiguration
metadata:
  name: <name of this configuration object>
webhooks:
- name: <webhook name, e.g., pod-policy.example.io>
  rules:                                            # 最好明确一下该hook关心哪些api，防止带来不必要的额外开销。
  - apiGroups:
    - ""
    apiVersions:
    - v1
    operations:
    - CREATE
    resources:
    - pods
    scope: "Namespaced"
  clientConfig:
    service:
      namespace: <namespace of the front-end service>  # webhook server的namespace
      name: <name of the front-end service>            # service name
    caBundle: <pem encoded ca cert that signs the server cert used by the webhook> # 因为需要通过https访问，所以要给apiserver配置ca
  admissionReviewVersions:
  - v1beta1
  timeoutSeconds: 1
```

## 总结
adminssion control 是非常重要的APIserver扩展的方式，掌握了其开发很多地方就能以比较优雅的方式解决一些实际问题。是基于k8s开发PaaS平台的利器


探讨可加QQ群：98488045

