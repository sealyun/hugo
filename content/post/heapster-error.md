+++
author = "fanux"
date = "2018-08-10T10:54:24+02:00"
draft = false
title = "kubernetes dashboard监控数据无法正常显示"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

# [kubernetes集群三步安装](https://sealyun.com/pro/products/)

# kubernetes1.12.0版本dashboard使用heapster无法正常显示监控数据

查看heapster日志：
```
E0228 20:01:05.019281       1 manager.go:101] Error in scraping containers from kubelet:30.0.1.4:10255: failed to get all container stats from Kubelet URL "http://30.0.1.4:10255/stats/container/": Post http://30.0.1.4:10255/stats/container/: dial tcp 30.0.1.4:10255: getsockopt: connection refused
```
因为1.12.0已经取消了这个端口：

```
      --read-only-port int32    
 The read-only port for the Kubelet to serve on with no authentication/authorization 
(set to 0 to disable) (default 10255) (DEPRECATED: 
This parameter should be set via the config file specified by the Kubelet's --config flag. 
See https://kubernetes.io/docs/tasks/administer-cluster/kubelet-config-file/ for more information.)
```

解决办法：

1. 修改heapster启动参数：
```
kubectl edit deploy heapster -n kube-system
```
source参数改成：
```
 --source=kubernetes:https://kubernetes.default:443?useServiceAccount=true&kubeletHttps=true&kubeletPort=10250&insecure=true
```

2. 此时还是不正常的，因为heapster的service account没有权限访问API，我们需要提权：

```
[root@dev-86-206 dashboard]# cat ../heapster/rbac/heapster-rbac.yaml
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: heapster
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin   # 修改这里
subjects:
- kind: ServiceAccount
  name: heapster
  namespace: kube-system
```

```
kubectl delete -f ../heapster/rbac/heapster-rbac.yaml
kubectl create -f ../heapster/rbac/heapster-rbac.yaml
```

如此heapster可正常访问kubelet和APIserver metric了

