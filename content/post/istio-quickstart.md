+++
author = "fanux"
date = "2018-08-1T10:54:24+02:00"
draft = false
title = "istio教程"
#slug = "dotscale-2014-as-a-sketch"
tags = ["event","dotScale","sketchnote"]
#image = "images/2014/Jul/titledotscale.png"
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

> 广告 | [kubernetes各版本离线安装包](http://sealyun.com/pro/products/)

# 安装

> 安装k8s [强势插播广告](http://sealyun.com/pro/products/) 

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
