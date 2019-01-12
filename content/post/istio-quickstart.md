+++
author = "fanux"
date = "2018-07-30T10:54:24+02:00"
draft = false
title = "istio安装使用教程"
#slug = "dotscale-2014-as-a-sketch"
tags = ["event","dotScale","sketchnote"]
#image = "images/2014/Jul/titledotscale.png"
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

> 广告 | [kubernetes各版本离线安装包](http://sealyun.com/pro/products/)

祝贺istio1.0发布, 在此献上教程一份

# 安装

> 安装k8s [强势插播广告](http://sealyun.com/pro/products/) 

三步安装，不多说

> 安装helm, 推荐生产环境用helm安装，可以调参

[release地址](https://github.com/helm/helm/releases)

如我使用的2.9.1版本
```
yum install -y socat # 这个不装会报错
```
```
[root@istiohost ~]# wget https://storage.googleapis.com/kubernetes-helm/helm-v2.9.1-linux-amd64.tar.gz
[root@istiohost ~]# tar zxvf helm-v2.9.1-linux-amd64.tar.gz
[root@istiohost ~]# cp linux-amd64/helm /usr/bin
```

先创建一个service account 把管理员权限给helm:
```
[root@istiohost ~]# cat helmserviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tiller
  namespace: kube-system
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: tiller-clusterrolebinding
subjects:
- kind: ServiceAccount
  name: tiller
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: ""
```
```
kubectl create -f  helmserviceaccount.yaml
```

安装helm 服务端 tiller :
```
helm init  --service-account tiller #  如果已安装更新加 --upgrade 参数
helm list #没任何返回表示成功
```

> 安装istio

```
curl -L https://git.io/getLatestIstio | sh -
cd istio-1.0.0/
export PATH=$PWD/bin:$PATH
```

helm 2.10.0以前的版本需要装一下CRD：
```
kubectl apply -f install/kubernetes/helm/istio/templates/crds.yaml
kubectl apply -f install/kubernetes/helm/istio/charts/certmanager/templates/crds.yaml
```

安装istio, 由于你没有LB所以用NodePort代替:
```
helm install install/kubernetes/helm/istio  --name istio --namespace istio-system --set gateways.istio-ingressgateway.type=NodePort --set gateways.istio-egressgateway.type=NodePort
```
安装成功：
```
[root@istiohost istio-1.0.0]# kubectl get pod -n istio-system
NAME                                        READY     STATUS    RESTARTS   AGE
istio-citadel-7d8f9748c5-ntqnp              1/1       Running   0          5m
istio-egressgateway-676c8546c5-2w4cq        1/1       Running   0          5m
istio-galley-5669f7c9b-mkxjg                1/1       Running   0          5m
istio-ingressgateway-5475685bbb-96mbr       1/1       Running   0          5m
istio-pilot-5795d6d695-gr4h4                2/2       Running   0          5m
istio-policy-7f945bf487-gkpxr               2/2       Running   0          5m
istio-sidecar-injector-d96cd9459-674pk      1/1       Running   0          5m
istio-statsd-prom-bridge-549d687fd9-6cbzs   1/1       Running   0          5m
istio-telemetry-6c587bdbc4-jndjn            2/2       Running   0          5m
prometheus-6ffc56584f-98mr9                 1/1       Running   0          5m
[root@istiohost istio-1.0.0]# kubectl get svc -n istio-system
NAME                       TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                                                                                                     AGE
istio-citadel              ClusterIP   10.108.253.89    <none>        8060/TCP,9093/TCP                                                                                           5m
istio-egressgateway        NodePort    10.96.151.14     <none>        80:30830/TCP,443:30038/TCP                                                                                  5m
istio-galley               ClusterIP   10.102.83.130    <none>        443/TCP,9093/TCP                                                                                            5m
istio-ingressgateway       NodePort    10.99.194.13     <none>        80:31380/TCP,443:31390/TCP,31400:31400/TCP,15011:31577/TCP,8060:30037/TCP,15030:31855/TCP,15031:30775/TCP   5m
istio-pilot                ClusterIP   10.101.4.143     <none>        15010/TCP,15011/TCP,8080/TCP,9093/TCP                                                                       5m
istio-policy               ClusterIP   10.106.221.68    <none>        9091/TCP,15004/TCP,9093/TCP                                                                                 5m
istio-sidecar-injector     ClusterIP   10.100.5.170     <none>        443/TCP                                                                                                     5m
istio-statsd-prom-bridge   ClusterIP   10.107.28.242    <none>        9102/TCP,9125/UDP                                                                                           5m
istio-telemetry            ClusterIP   10.105.66.20     <none>        9091/TCP,15004/TCP,9093/TCP,42422/TCP                                                                       5m
prometheus                 ClusterIP   10.103.128.152   <none>        9090/TCP
```

# 使用教程
## 官网事例 Bookinfo Application
![](/noistio.svg)

* productpage 调用details和reviews渲染页面
* details包含书本信息
* reviews 书本反馈，调用ratings服务
* ratings 书本租借信息

reviews服务有三个版本:

* V1 不请求ratings
* V2 请求ratings，返回1到5个黑星
* V3 请求ratings，返回1到5个红星

数据平面：
![](/withistio.svg)

安装应用：
```
kubectl apply -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
```
安装完成：
```
[root@istiohost istio-1.0.0]# kubectl get services
NAME          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
details       ClusterIP   10.104.66.31    <none>        9080/TCP   2m
kubernetes    ClusterIP   10.96.0.1       <none>        443/TCP    4h
productpage   ClusterIP   10.109.68.13    <none>        9080/TCP   2m
ratings       ClusterIP   10.99.55.110    <none>        9080/TCP   2m
reviews       ClusterIP   10.102.19.129   <none>        9080/TCP   2m
[root@istiohost istio-1.0.0]# kubectl get pods
NAME                              READY     STATUS    RESTARTS   AGE
details-v1-fc9649d9c-dpnlp        2/2       Running   0          2m
productpage-v1-58845c779c-7g8th   2/2       Running   0          2m
ratings-v1-6cc485c997-fb7nh       2/2       Running   0          2m
reviews-v1-76987687b7-x5n7z       2/2       Running   0          2m
reviews-v2-86749dcd5-xchzb        2/2       Running   0          2m
reviews-v3-7f4746b959-nthrq       2/2       Running   0          2m
```

创建一个gateway,这是为了集群外可以访问
```
kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
```

浏览器访问url:
47.254.28.88是我的节点ip，使用nodeport模式
```
http://47.254.28.88:31380/productpage 
```
连续点击三次，你会发现右边没星星-> 黑星星-> 红星星切换，对应三个版本的review,默认策略是轮询

创建destination rules, 配置路由访问规则，现在还是轮询
```
kubectl apply -f samples/bookinfo/networking/destination-rule-all.yaml
```

# 智能路由
## 请求路由 request routing
### 根据版本路由
把所有路由切换到v1版本
```
kubectl apply -f samples/bookinfo/networking/virtual-service-all-v1.yaml
```
这样执行完后，不管怎么刷页面，我们都看不到星星，因为v1版本没星

可以看到destination是这样的：
```
  http:
  - route:
    - destination:
        host: details
        subset: v1
```
试想如此我们做版本切换将是何等简单

### 根据用户路由
```
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-test-v2.yaml
```
你会发现用jason用户登录就能看到黑星星，而其它方式看到的页面都是无星星

因为这个user走了v2版本，能不强大？  那当然还能根据header什么的做路由了，就不多说了
```
  http:
  - match:
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: reviews
        subset: v2
  - route:
    - destination:
        host: reviews
        subset: v1
```

## 故障注入 Fault injection
```
kubectl apply -f samples/bookinfo/networking/virtual-service-all-v1.yaml
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-test-v2.yaml
```
假设代码里有个bug，用户jason, reviews:v2 访问ratings时会卡10s, 我们任然希望端到端的测试能正常走完

```
kubectl apply -f samples/bookinfo/networking/virtual-service-ratings-test-delay.yaml
```
注入错误让jason用户有个7s的延迟
```
  hosts:
  - ratings
  http:
  - fault:
      delay:
        fixedDelay: 7s
        percent: 100
    match:
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: ratings
        subset: v1
  - route:
    - destination:
        host: ratings
        subset: v1
```
这时访问页面显然会出错，因为我们希望7s内能返回,这样我们就发现了一个延迟的bug
```
Error fetching product reviews!
Sorry, product reviews are currently unavailable for this book.
```
所以我们就可能通过故障注入去发现这些异常现象

## 链路切换 Traffic Shifting
我们先把50%流量发送给reviews:v1 50%流量发送给v3，然后再把100%的流量都切给v3
### 把100%流量切到v1
```
kubectl apply -f samples/bookinfo/networking/virtual-service-all-v1.yaml
```
此时不论刷几遍，都没有星星

### v1 v3各50%流量
```
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-50-v3.yaml
```
```
  - route:
    - destination:
        host: reviews
        subset: v1
      weight: 50
    - destination:
        host: reviews
        subset: v3
      weight: 50
```
此时一会有星，一会没星，但是已经不是轮询算法了

### 全切v3
```
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-v3.yaml
```
这时不管怎么刷都是红心了

# 公众号：
![sealyun](https://sealyun.com/kubernetes-qrcode.jpg)

### 微信群：
![](/wechatgroup1.png)
