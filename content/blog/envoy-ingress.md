+++
author = "fanux"
date = "2019-01-23T10:54:24+02:00"
draft = false
title = "基于Envoy的Ingress controller使用介绍"
tags = ["event","dotScale","sketchnote"]
banner = "img/banners/banner-1.png"
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

> [kubernetes集群三步安装](https://sealyun.com/pro/products/)

# 概述
ingress controller有很多，这里介绍其中一个[contour](https://github.com/heptio/contour), 我没有使用ingress controller的原因是

首先contour的实现是envoy, 其动态配置能力强于nginx，其次可以非常方便的对接监控系统，也是istio的核心组件。 本文其实还是以ingress的用法
为主, 因为不管是什么实现都兼容ingress的配置标准

还有就是contour是唯一实现了自定义IngressRoute CRD来实现更复杂的路由功能，websocket支持，健康检测，prefix rewite支持,还有TCP代理
<!--more-->

# 原理
安装完成之后会起两个pod，这pod里最核心的工作就是监听ingress的创建然后给envoy进行配置
```
[root@i-ao55ms86 ingress]# kubectl get pod -n heptio-contour
NAME                       READY   STATUS    RESTARTS   AGE
contour-7bfd8f9f9d-fs5xh   2/2     Running   0          43m
contour-7bfd8f9f9d-t6xjf   2/2     Running   0          43m
```
看两个核心pod:
```
- image: gcr.io/heptio-images/contour:master  # 监听
  imagePullPolicy: IfNotPresent
  name: contour
  command: ["contour"]
  args: ["serve", "--incluster"]
- image: docker.io/envoyproxy/envoy:v1.9.0    # 真正的代理
  name: envoy
  ports:
  - containerPort: 8080
    name: http
  - containerPort: 8443
    name: https
  command: ["envoy"]
  args:
  - --config-path /config/contour.json
  - --service-cluster cluster0
  - --service-node node0
  - --log-level info
  - --v2-config-only
```

```
[root@i-ao55ms86 contour]# kubectl get svc -n heptio-contour
NAME      TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
contour   NodePort   10.98.138.123   <none>        80:32024/TCP,443:30662/TCP   69m   # 这里我改成了nodeport方式进行访问Envoy
```

## 配置如何被下发的
```
[root@i-ao55ms86 contour]# kubectl exec -it contour-7bfd8f9f9d-fs5xh -c envoy -n heptio-contour -- bash
root@contour-7bfd8f9f9d-fs5xh:/# cat config/contour.json
```
用上面命令进入envoy的容器一探究竟：
```
  "dynamic_resources": {   # 这里就用到的envoy强大的动态配置功能，这会去contour服务中去拉取配置，而contour中的配置是通过坚挺ingress生成
    "lds_config": {
      "api_config_source": {
        "api_type": "GRPC",
        "grpc_services": [
          {
            "envoy_grpc": {
              "cluster_name": "contour"
            }
          }
        ]
      }
    },
    "cds_config": {
      "api_config_source": {
        "api_type": "GRPC",
        "grpc_services": [
          {
            "envoy_grpc": {
              "cluster_name": "contour"
            }
          }
        ]
      }
    }
  },
```

# 使用教程
## 基本使用

可以看到在我自己的namespace下有一系列微服务，现在想通过ingress把这些微服务统一代理起来，统一出口
```
[root@i-ao55ms86 ~]# kubectl get svc -n sealyun
NAME            TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)                         AGE
fist            NodePort   10.106.233.67   <none>        8443:32201/TCP,8080:32202/TCP   24h
fist-rbac       NodePort   10.106.233.69   <none>        8080:32204/TCP                  24h
fist-terminal   NodePort   10.106.233.68   <none>        8080:32203/TCP                  24h
ldap-service    NodePort   10.103.2.47     <none>        389:31389/TCP                   23h
palm            NodePort   10.102.115.19   <none>        80:32200/TCP                    2d5h
```

```
[root@i-ao55ms86 ingress]# cat fist-ingress.yaml 
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: fist-ingress
  namespace: sealyun                     # 注意ingress运行在你自己的namespace中，不然是找不到下面的service name的
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /token
spec:
  rules:
  - http:
      paths:
      - path: /token
        backend:
          serviceName: fist    # 这里对照上面的svc
          servicePort: 8080
```

然后就可以通过contour的service访问我们的服务了:
```
[root@i-ao55ms86 ~]# kubectl get svc -n heptio-contour
NAME      TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
contour   NodePort   10.98.138.123   <none>        80:32024/TCP,443:30662/TCP   178m
[root@i-ao55ms86 ~]# curl "http://10.98.138.123:80/token?user=fanux&group=sealyun"
{
 "message": "success",
 "code": 200,
 "data": "eyJhbGciOiJSUzI1NiI..."
}
```

### 代理多个path
如terminal这个微服务有两个path需要代理
```
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: terminal-ingress
  namespace: sealyun
spec:
  rules:
  - http:
      paths:
      - path: /terminal
        backend:
          serviceName: fist-terminal
          servicePort: 8080
      - path: /heartbeat
        backend:
          serviceName: fist-terminal
          servicePort: 8080
```

# 多租户问题
* 因为ingress controller监听了所有namespace下的Ingress创建，并给envoy下发配置，试想一下多租户都去配置Ingress时，必然会造成相互影响。
    * 比如大家都去配置了path为login的路由，后端指向了不同的service, 那么肯定会造成其他租户的路由不正常。

## 解决办法
### 通过DNS名区分
    通过类似nginx虚拟主机的方式解决，也就是不同的用户访问的DNS名不同，如上述相同path时 A.sealyun.com/login   B.sealyun.com/login这样区分

    这种方式无法解决四层的代理，且多租户任然是共用了一个envoy，这样在排查问题时可能都不太友好，sealyun fist公有云考虑用这种方式去做，不过是牺牲掉了一些功能。

### 为租户单独创建controller 
1. 每个租户都需要创建ingress controller, 创建时指定监听哪些namespace下的Ingress - 需要定制contour代码
2. 需要为ingress controller service account配置权限，让其无权限监听其他租户的namespace下的Ingress [非必须]

# 对接监控
# 灰度发布
# 蓝绿发布



探讨可加QQ群：98488045

