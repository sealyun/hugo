+++
author = "fanux"
date = "2019-08-03T10:54:24+02:00"
draft = false
title = "kustomize 颤抖吧helm!"
tags = ["network","dev"]
comments = true     # set false to hide Disqus comments
banner = "kustomize.jpeg"
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

本人是helm的重度用户，但是吧越用越不爽。。。 helm v2版本三大弊病：

* 多租户支持不了
* 搞个tiller服务端，鸡肋
* 扯出自己很多概念

v3版本抛弃tiller算是个进步，但是听说要上撸啊（lua）我就瞬间崩溃了，我只是想渲染个yaml文件而已。好在好多chart包貌似生态很繁荣。。。

今天给大家介绍kustomize是如何让helm寝食难安，做梦都在颤抖的.

<!--more-->
![](https://sealyun.com/kustomize.jpeg)

# 安装
kustomize已经集成在高版本(1.14+)的kubectl里了，可以使用 `kubectl apply -k [目录]` 来执行 

安装太低级不说了，装不上的智商估计就不用往下继续看了。。。

# 快速开始
```
mkdir ~/hello
DEMO_HOME=~/hello

BASE=$DEMO_HOME/base
mkdir -p $BASE

curl -s -o "$BASE/#1.yaml" "https://raw.githubusercontent.com\
/kubernetes-sigs/kustomize\
/master/examples/helloWorld\
/{configMap,deployment,kustomization,service}.yaml"
```

看下目录结构：
```
base
    ├── configMap.yaml
    ├── deployment.yaml
    ├── kustomization.yaml
    └── service.yaml
```

configmap deployment service里就是我们普通的yaml文件，再加个kustomizeation文件：

文件中指定了一些配置，指定我们把哪些个文件进行合并
```
➜  hello cat base/kustomization.yaml 
# Example configuration for the webserver
# at https://github.com/monopole/hello
commonLabels:
  app: hello

resources:
- deployment.yaml
- service.yaml
- configMap.yaml
```

build一下就会输出整个yaml了：
```
# kustomize build base
apiVersion: v1
data:
  altGreeting: Good Morning!
  enableRisky: "false"
kind: ConfigMap
metadata:
  labels:
    app: hello
  name: the-map
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: hello
  name: the-service
...
```

很简单吧，是不是发现没什么卵用，咱再继续

## 预上线配置与生产配置
我们经常会遇到如开发环境与生产环境的配置文件不一样的情况，典型的配额与副本数不一样。 我们现在就来处理这种场景，staging环境与production环境。

```
OVERLAYS=$DEMO_HOME/overlays
mkdir -p $OVERLAYS/staging
mkdir -p $OVERLAYS/production
```

如两个环境的configmap不一样的场景
```
cat <<'EOF' >$OVERLAYS/staging/kustomization.yaml
namePrefix: staging-
commonLabels:
  variant: staging
  org: acmeCorporation
commonAnnotations:
  note: Hello, I am staging!
resources:
- ../../base
patchesStrategicMerge: # 这里意思是我们要把base里的configmap用下面的configmap overlay一下
- map.yaml
EOF
```

这样我们用下面的configmap去更新base中的，这里相当于增加了俩字段。
```
cat <<EOF >$OVERLAYS/staging/map.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: the-map
data:
  altGreeting: "Have a pineapple!"
  enableRisky: "true"
EOF
```

再build一下观察configmap变化：
```
➜  hello kustomize build overlays/staging 
apiVersion: v1
data:
  altGreeting: Have a pineapple!  # 覆盖了base中的data
  enableRisky: "true"
kind: ConfigMap
metadata:
  annotations:
    note: Hello, I am staging!  # 新增了配置文件中的commonAnnotations
  labels:
    app: hello                  # 继承了base中的label
    org: acmeCorporation        # 新增了配置文件中的label
    variant: staging
  name: staging-the-map
```

production同理不再赘述了， 然后就可以部署到k8s集群中：
```
kustomize build $OVERLAYS/staging |\
    kubectl apply -f -
```
或者
```
kubectl apply -k $OVERLAYS/staging
```

# 设置字段，如镜像tag
我们yaml文件中镜像有tag，每次版本更新都去修改文件比较麻烦。特别是在CI/CD时有可能取的是类似 DRONE_TAG的环境变量用作镜像tag。

```
cd base
kustomize edit set image monopole/hello=alpine:3.6
```
kustomization.yaml中就可以看到：
```
images:
- name: monopole/hello
  newName: alpine
  newTag: "3.6"
```

再build时deployment中镜像就变了：
```
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: hello
  name: the-deployment
spec:
...
        image: alpine:3.6
```
这样在CI/CD时以DRONE为例就可以直接这样：
```
deploy:
   image: kustomize:latest
   commands:
     - kustomize edit set image monopole/hello=alpine:{DRONE_TAG=latest}
     - kubectl apply -k .
```
这样你代码的tag与构建镜像的tag以及yaml文件中的tag就完美保持一致了，再也不用担心上错版本了。

# 注入k8s运行时数据
kustomize有个很强大的特性就是允许注入k8s运行时的一些数据，举个栗子：

假设部署个php要去连mysql，但是只知道mysql的Servicename 并不知道端口号是啥，那么kubemize就可以帮你解决这个问题：

这里给个获取metadata.name的例子，其它运行时数据一个理

php的yaml文件可以这样写：
```
apiVersion: apps/v1beta2
kind: Deployment
metadata:
  name: wordpress
spec:
  template:
    spec:
      initContainers:
      - name: init-command
        image: debian
        command:
        - "echo $(WORDPRESS_SERVICE)"
        - "echo $(MYSQL_SERVICE)"
      containers:
      - name: wordpress
        env:
        - name: WORDPRESS_DB_HOST
          value: $(MYSQL_SERVICE)
        - name: WORDPRESS_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-pass
              key: password
```

然后配置下kusztomize：
```
cat <<EOF >>$DEMO_HOME/kustomization.yaml
vars:
  - name: WORDPRESS_SERVICE  # 最终被渲染进yaml
    objref:
      kind: Service
      name: wordpress        # 获取叫wordpress的Service
      apiVersion: v1
    fieldref:
      fieldpath: metadata.name # 最终获取service中的metadata.name作为WORDPRESS_SERVICE 
  - name: MYSQL_SERVICE
    objref:
      kind: Service
      name: mysql
      apiVersion: v1
EOF
```
这是个十分强大的特性，比如有时我们觉得DNS不够稳定或者短链接多不想走DNS服务发现，A访问B时想直接用B的clusterip，但是B部署之前又不知道IP是啥，就可以

通过这种方式获取到clusterip，理解了这个原理就可以随意发挥了.

探讨可加QQ群：98488045
