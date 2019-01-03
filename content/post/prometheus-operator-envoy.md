+++
author = "fanux"
date = "2019-01-01T10:54:24+02:00"
draft = false
title = "使用prometheus operator监控envoy"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

# [kubernetes集群三步安装](https://sealyun.com/pro/products/)

# 概述
prometheus operator应当是使用监控系统的最佳实践了，首先它一键构建整个监控系统，通过一些无侵入的手段去配置如监控数据源等
故障自动恢复，高可用的告警等。。

不过对于新手使用上还是有一丢丢小门槛，本文就结合如何给envoy做监控这个例子来分享使用prometheus operator的正确姿势

# prometheus operator安装
[sealyun离线安装包](https://sealyun.com/pro/products/)内已经包含prometheus operator,安装完直接使用即可

# 配置监控数据源
原理：通过operator的CRD发现监控数据源service
![](/prometheus/operator-arch.png)

## 启动envoy
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: envoy
  labels:
    app: envoy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: envoy
  template:
    metadata:
      labels:
        app: envoy
    spec:
      volumes:
      - hostPath:   # 为了配置方便把envory配置文件挂载出来了
          path: /root/envoy
          type: DirectoryOrCreate
        name: envoy
      containers:
      - name: envoy
        volumeMounts:
        - mountPath: /etc/envoy
          name: envoy
          readOnly: true
        image: envoyproxy/envoy:latest
        ports:
        - containerPort: 10000 # 数据端口
        - containerPort: 9901  # 管理端口，metric是通过此端口暴露

---
kind: Service
apiVersion: v1
metadata:
  name: envoy
  labels:
    app: envoy  # 给service贴上标签，operator会去找这个service
spec:
  selector:
    app: envoy
  ports:
  - protocol: TCP
    port: 80
    targetPort: 10000
    name: user
  - protocol: TCP   # service暴露metric的端口
    port: 81
    targetPort: 9901
    name: metrics   # 名字很重要，ServiceMonitor 会找端口名
```

envoy配置文件：
监听的地址一定需要修改成0.0.0.0，否则通过service获取不到metric
/root/envoy/envoy.yaml
```
admin:
  access_log_path: /tmp/admin_access.log
  address:
    socket_address:
      protocol: TCP
      address: 0.0.0.0   # 这里一定要改成0.0.0.0，而不能是127.0.0.1
      port_value: 9901
static_resources:
  listeners:
  - name: listener_0
    address:
      socket_address:
        protocol: TCP
        address: 0.0.0.0
        port_value: 10000
    filter_chains:
    - filters:
      - name: envoy.http_connection_manager
        config:
          stat_prefix: ingress_http
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                route:
                  host_rewrite: sealyun.com
                  cluster: service_google
          http_filters:
          - name: envoy.router
  clusters:
  - name: service_sealyun
    connect_timeout: 0.25s
    type: LOGICAL_DNS
    # Comment out the following line to test on v6 networks
    dns_lookup_family: V4_ONLY
    lb_policy: ROUND_ROBIN
    hosts:
      - socket_address:
          address: sealyun.com
          port_value: 443
    tls_context: { sni: sealyun.com }
```
## 使用ServiceMonitor
envoyServiceMonitor.yaml:
```
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  labels:
    app: envoy
  name: envoy
  namespace: monitoring  # 这个可以与service不在一个namespace中
spec:
  endpoints:
  - interval: 15s
    port: metrics        # envoy service的端口名
    path: /stats/prometheus # 数据源path
  namespaceSelector:
    matchNames:        # envoy service所在namespace
    - default
  selector:
    matchLabels:
      app: envoy       # 选择envoy service
```

create成功后我们就可以看到envoy的数据源了：
![](/prometheus/envoy-target.png)

然后就可以看到metric了：
![](/prometheus/envoy-metric.png)

然后就可以在grafana上进行一些配置了，promethues相关使用不是本文讨论的对象

# 告警配置
## alert manager配置
```
[root@dev-86-201 envoy]# kubectl get secret -n monitoring
NAME                              TYPE                                  DATA   AGE
alertmanager-main                 Opaque                                1      27d
```
我们可以看到这个secrect，看下里面具体内容：
```
[root@dev-86-201 envoy]# kubectl get secret  alertmanager-main -o yaml -n monitoring
apiVersion: v1
data:
  alertmanager.yaml: Imdsb2JhbCI6IAogICJyZXNvbHZlX3RpbWVvdXQiOiAiNW0iCiJyZWNlaXZlcnMiOiAKLSAibmFtZSI6ICJudWxsIgoicm91dGUiOiAKICAiZ3JvdXBfYnkiOiAKICAtICJqb2IiCiAgImdyb3VwX2ludGVydmFsIjogIjVtIgogICJncm91cF93YWl0IjogIjMwcyIKICAicmVjZWl2ZXIiOiAibnVsbCIKICAicmVwZWF0X2ludGVydmFsIjogIjEyaCIKICAicm91dGVzIjogCiAgLSAibWF0Y2giOiAKICAgICAgImFsZXJ0bmFtZSI6ICJEZWFkTWFuc1N3aXRjaCIKICAgICJyZWNlaXZlciI6ICJudWxsIg==
kind: Secret
```
base64解码一下：
```
"global":
  "resolve_timeout": "5m"
"receivers":
- "name": "null"
"route":
  "group_by":
  - "job"
  "group_interval": "5m"
  "group_wait": "30s"
  "receiver": "null"
  "repeat_interval": "12h"
  "routes":
  - "match":
      "alertname": "DeadMansSwitch"
    "receiver": "null"
```
所以配置alertmanager就非常简单了，就是创建一个secrect即可
如alertmanager.yaml:
```
global:
  smtp_smarthost: 'smtp.qq.com:465'
  smtp_from: '474785153@qq.com'
  smtp_auth_username: '474785153@qq.com'
  smtp_auth_password: 'xxx'       # 这个密码是开启smtp授权后生成的,下文有说怎么配置
  smtp_require_tls: false
route:
  group_by: ['alertmanager','cluster','service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 3h
  receiver: 'fanux'
  routes:
  - receiver: 'fanux'
receivers:
- name: 'fanux'
  email_configs:
  - to: '474785153@qq.com'
    send_resolved: true
```
delete掉老的secret，根据自己的配置重新生成secret即可
```
kubectl delete secret alertmanager-main -n monitoring
kubectl create secret generic alertmanager-main --from-file=alertmanager.yaml -n monitoring
```

## 邮箱配置，以QQ邮箱为例
开启smtp pop3服务
![](/prometheus/email-setting.png)
![](/prometheus/email-setting2.png) 照着操作即可，后面会弹框一个授权码，配置到上面的配置文件中
然后就可以收到告警了：
![](/prometheus/alert-email.png)

## 告警规则配置
prometheus operator自定义PrometheusRule crd去描述告警规则
```
[root@dev-86-202 shell]# kubectl get PrometheusRule -n monitoring
NAME                   AGE
prometheus-k8s-rules   6m
```

直接edit这个rule即可，也可以再自己去创建个PrometheusRule
```
kubectl edit PrometheusRule prometheus-k8s-rules -n monitoring
```
如我们在group里加一个告警：
```
spec:
  groups:
  - name: ./example.rules
    rules:
    - alert: ExampleAlert
      expr: vector(1)
  - name: k8s.rules
    rules:
```

重启prometheuspod:
```
kubectl delete pod prometheus-k8s-0 prometheus-k8s-1 -n monitoring
```
然后在界面上就可以看到新加的规则：
![](prometheus/prometheus-rule.png)



探讨可加QQ群：98488045

# 公众号：
![sealyun](https://sealyun.com/kubernetes-qrcode.jpg)
