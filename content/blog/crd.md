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

# 基本概念
kubernetes允许用户自定义自己的资源对象，就如同deployment statefulset一样，这个应用非常广泛，比如prometheus opterator就自定义Prometheus对象，再加上一个自定义的controller监听到kubectl create Prometheus时就去创建Pod组成一个pormetheus集群。rook等等同理。

我需要用kubernetes调度虚拟机，所以这里自定义一个 VirtualMachine 类型

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
virtulmachines.infra.genos.io                  52m
```

来创建一个虚拟机：
```
# kubectl apply -f config/samples/
# kubectl get virtulmachines.infra.genos.io 
NAME                   AGE
virtulmachine-sample   49m
```
看一眼yaml文件：
```
# cat config/samples/infra_v1_virtulmachine.yaml 
apiVersion: infra.genos.io/v1
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
再改下Dockerfile, 加一行, 注释掉download：
```
COPY vendor/ vendor/
# RUN go mod download
```

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

探讨可加QQ群：98488045
