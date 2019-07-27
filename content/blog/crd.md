+++
author = "fanux"
date = "2019-07-01T10:54:24+02:00"
draft = false
title = "kubernetes CRD如此简单"
tags = ["kubernetes","dev"]
comments = true     # set false to hide Disqus comments
banner = "img/banners/banner-1.png"
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

扩展kubernetes两个最常用最需要掌握的东西：自定义资源CRD 和 adminsion webhook, 本文教你如何十分钟掌握CRD开发.

kubernetes允许用户自定义自己的资源对象，就如同deployment statefulset一样，这个应用非常广泛，比如prometheus opterator就自定义Prometheus对象，再加上一个自定义的controller监听到kubectl create Prometheus时就去创建Pod组成一个pormetheus集群。rook等等同理。

我需要用kubernetes调度虚拟机，所以这里自定义一个 VirtualMachine 类型
<!--more-->

# [kubebuilder](https://github.com/kubernetes-sigs/kubebuilder)
kubebuilder能帮我们节省大量工作，让开发CRD和adminsion webhook变得异常简单。

## 安装
通过源码安装：
```
git clone https://github.com/kubernetes-sigs/kubebuilder
cd kubebuilder
make build
cp bin/kubebuilder $GOPATH/bin
```

或者下载二进制：
```
os=$(go env GOOS)
arch=$(go env GOARCH)

# download kubebuilder and extract it to tmp
curl -sL https://go.kubebuilder.io/dl/2.0.0-beta.0/${os}/${arch} | tar -xz -C /tmp/

# move to a long-term location and put it on your path
# (you'll need to set the KUBEBUILDER_ASSETS env var if you put it somewhere else)
sudo mv /tmp/kubebuilder_2.0.0-beta.0_${os}_${arch} /usr/local/kubebuilder
export PATH=$PATH:/usr/local/kubebuilder/bin
```

还需要装下[kustomize](https://github.com/kubernetes-sigs/kustomize) 这可是个渲染yaml的神器，让helm颤抖。
```
go install sigs.k8s.io/kustomize/v3/cmd/kustomize
```

## 使用
注意你得先有个kubernetes集群，[一步安装走你](https://github.com/fanux/sealos)

> 创建CRD

```
kubebuilder init --domain sealyun.com --license apache2 --owner "fanux"
kubebuilder create api --group infra --version v1 --kind VirtulMachine
```

> 安装CRD并启动controller

```
make install # 安装CRD
make run # 启动controller
```
然后我们就可以看到创建的CRD了
```
# kubectl get crd
NAME                                           AGE
virtulmachines.infra.sealyun.com                  52m
```

来创建一个虚拟机：
```
# kubectl apply -f config/samples/
# kubectl get virtulmachines.infra.sealyun.com 
NAME                   AGE
virtulmachine-sample   49m
```
看一眼yaml文件：
```
# cat config/samples/infra_v1_virtulmachine.yaml 
apiVersion: infra.sealyun.com/v1
kind: VirtulMachine
metadata:
  name: virtulmachine-sample
spec:
  # Add fields here
  foo: bar
```

这里仅仅是把yaml存到etcd里了，我们controller监听到创建事件时啥事也没干。

> 把controller部署到集群中

```
make docker-build docker-push IMG=fanux/infra-controller
make deploy
```
我是连的远端的kubenetes, make docker-build时test过不去，没有etcd的bin文件，所以先把test关了。

修改Makefile:
```
# docker-build: test
docker-build: 
```
Dockerfile里的`gcr.io/distroless/static:latest` 这个镜像你也可能拉不下来，随意改改就行，我改成了`golang:1.12.7`

也有可能构建时有些代码拉不下来，启用一下go mod vendor 把依赖打包进去
```
go mod vendor
如果你本地有些代码拉不下来，可以用proxy:
```
export GOPROXY=https://goproxy.io
```
```
再改下Dockerfile, 注释掉download：

修改后：
```
# Build the manager binary
FROM golang:1.12.7 as builder

WORKDIR /go/src/github.com/fanux/sealvm
# Copy the Go Modules manifests
COPY . . 

# Build
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o manager main.go

# Use distroless as minimal base image to package the manager binary
# Refer to https://github.com/GoogleContainerTools/distroless for more details
# FROM gcr.io/distroless/static:latest
FROM golang:1.12.7
WORKDIR /
COPY --from=builder /go/src/github.com/fanux/sealvm/manager .
ENTRYPOINT ["/manager"]
```

`make deploy` 时报错： `Error: json: cannot unmarshal string into Go struct field Kustomization.patches of type types.Patch`

把 `config/default/kustomization.yaml` 中的 `patches:` 改成 `patchesStrategicMerge:` 即可


`kustomize build config/default` 这个命令就渲染出了controller的yaml文件，可以体验下

看 你的controller已经跑起来了：
```
kubectl get deploy -n sealvm-system
NAME                        DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
sealvm-controller-manager   1         1         1            0           3m
kubectl get svc -n sealvm-system
NAME                                        TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
sealvm-controller-manager-metrics-service   ClusterIP   10.98.71.199   <none>        8443/TCP   4m
```

## 开发

### 增加对象数据参数
看下config/samples下面的yaml文件：
```
apiVersion: infra.sealyun.com/v1
kind: VirtulMachine
metadata:
  name: virtulmachine-sample
spec:
  # Add fields here
  foo: bar
```
这里参数里有`foo:bar`， 那我们来加个虚拟CPU，内存信息：

直接`api/v1/virtulmachine_types.go`即可
```
// VirtulMachineSpec defines the desired state of VirtulMachine
// 在这里加信息
type VirtulMachineSpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file
	CPU    string `json:"cpu"`   // 这是我增加的
	Memory string `json:"memory"`
}

// VirtulMachineStatus defines the observed state of VirtulMachine
// 在这里加状态信息，比如虚拟机是启动状态，停止状态啥的
type VirtulMachineStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file
}
```
然后make一下：
```
make && make install && make run
```
这时再去渲染一下controller的yaml就会发现CRD中已经带上CPU和内存信息了：

`kustomize build config/default`
```
properties:
  cpu:
    description: 'INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
      Important: Run "make" to regenerate code after modifying this file'
    type: string
  memory:
    type: string
```

修改一下yaml:
```
apiVersion: infra.sealyun.com/v1
kind: VirtulMachine
metadata:
  name: virtulmachine-sample
spec:
  cpu: "1"
  memory: "2G"
```

```
# kubectl apply -f config/samples 
virtulmachine.infra.sealyun.com "virtulmachine-sample" configured
# kubectl get virtulmachines.infra.sealyun.com virtulmachine-sample -o yaml 
apiVersion: infra.sealyun.com/v1
kind: VirtulMachine
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"infra.sealyun.com/v1","kind":"VirtulMachine","metadata":{"annotations":{},"name":"virtulmachine-sample","namespace":"default"},"spec":{"cpu":"1","memory":"2G"}}
  creationTimestamp: 2019-07-26T08:47:34Z
  generation: 2
  name: virtulmachine-sample
  namespace: default
  resourceVersion: "14811698"
  selfLink: /apis/infra.sealyun.com/v1/namespaces/default/virtulmachines/virtulmachine-sample
  uid: 030e2b9a-af82-11e9-b63e-5254bc16e436
spec:      # 新的CRD已生效
  cpu: "1"
  memory: 2G 
```
Status 同理，就不再赘述了，比如我把status里加一个Create, 表示controller要去创建虚拟机了(主要一些控制层面的逻辑)，创建完了把状态改成Running

### Reconcile 唯一需要实现的接口
controller把轮训与事件监听都封装在这一个接口里了.你不需要关心怎么事件监听的.

#### 获取虚拟机信息
```
func (r *VirtulMachineReconciler) Reconcile(req ctrl.Request) (ctrl.Result, error) {
	ctx = context.Background()
	_ = r.Log.WithValues("virtulmachine", req.NamespacedName)

	vm := &v1.VirtulMachine{}
	if err := r.Get(ctx, req.NamespacedName, vm); err != nil { # 获取VM信息
		log.Error(err, "unable to fetch vm")
	} else {
        fmt.Println(vm.Spec.CPU, vm.Spec.Memory) # 打印CPU内存信息
	}

	return ctrl.Result{}, nil
}
```
`make && make install && make run`这个时候去创建一个虚拟机`kubectl apply -f config/samples`,日志里就会输出CPU内存了. List接口同理，我就不赘述了

```
r.List(ctx, &vms, client.InNamespace(req.Namespace), client.MatchingField(vmkey, req.Name))
```

#### 更新状态

#### 删除

探讨可加QQ群：98488045
