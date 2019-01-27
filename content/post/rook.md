+++
author = "fanux"
date = "2019-01-23T10:54:24+02:00"
draft = false
title = "rook使用教程，快速编排ceph"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

> [kubernetes集群三步安装](https://sealyun.com/pro/products/)

# 安装
```
git clone https://github.com/rook/rook

cd cluster/examples/kubernetes/ceph
kubectl create -f operator.yaml 
```
查看operator是否成功：
```
[root@dev-86-201 ~]# kubectl get pod -n rook-ceph-system
NAME                                  READY   STATUS    RESTARTS   AGE
rook-ceph-agent-5z6p7                 1/1     Running   0          88m
rook-ceph-agent-6rj7l                 1/1     Running   0          88m
rook-ceph-agent-8qfpj                 1/1     Running   0          88m
rook-ceph-agent-xbhzh                 1/1     Running   0          88m
rook-ceph-operator-67f4b8f67d-tsnf2   1/1     Running   0          88m
rook-discover-5wghx                   1/1     Running   0          88m
rook-discover-lhwvf                   1/1     Running   0          88m
rook-discover-nl5m2                   1/1     Running   0          88m
rook-discover-qmbx7                   1/1     Running   0          88m
```
然后创建ceph集群：
```
kubectl create -f cluster.yaml
```
查看ceph集群：
```
[root@dev-86-201 ~]# kubectl get pod -n rook-ceph
NAME                               READY   STATUS    RESTARTS   AGE
rook-ceph-mgr-a-8649f78d9b-jklbv   1/1     Running   0          64m
rook-ceph-mon-a-5d7fcfb6ff-2wq9l   1/1     Running   0          81m
rook-ceph-mon-b-7cfcd567d8-lkqff   1/1     Running   0          80m
rook-ceph-mon-d-65cd79df44-66rgz   1/1     Running   0          79m
rook-ceph-osd-0-56bd7545bd-5k9xk   1/1     Running   0          63m
rook-ceph-osd-1-77f56cd549-7rm4l   1/1     Running   0          63m
rook-ceph-osd-2-6cf58ddb6f-wkwp6   1/1     Running   0          63m
rook-ceph-osd-3-6f8b78c647-8xjzv   1/1     Running   0          63m
```
参数说明：
```
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    # For the latest ceph images, see https://hub.docker.com/r/ceph/ceph/tags
    image: ceph/ceph:v13.2.2-20181023
  dataDirHostPath: /var/lib/rook # 数据盘目录
  mon:
    count: 3
    allowMultiplePerNode: true
  dashboard:
    enabled: true
  storage:
    useAllNodes: true
    useAllDevices: false
    config:
      databaseSizeMB: "1024"
      journalSizeMB: "1024"
```

访问ceph dashboard:
```
[root@dev-86-201 ~]# kubectl get svc -n rook-ceph
NAME                      TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)          AGE
rook-ceph-mgr             ClusterIP   10.98.183.33     <none>        9283/TCP         66m
rook-ceph-mgr-dashboard   NodePort    10.103.84.48     <none>        8443:31631/TCP   66m  # 把这个改成NodePort模式
rook-ceph-mon-a           ClusterIP   10.99.71.227     <none>        6790/TCP         83m
rook-ceph-mon-b           ClusterIP   10.110.245.119   <none>        6790/TCP         82m
rook-ceph-mon-d           ClusterIP   10.101.79.159    <none>        6790/TCP         81m
```
然后访问https://10.1.86.201:31631 即可
![](/ceph/dashboard.png)

管理账户admin,获取登录密码：
```
kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o yaml | grep "password:" | awk '{print $2}' | base64 --decode
```

# 使用

## 创建pool
```
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: replicapool   # operator会监听并创建一个pool，执行完后界面上也能看到对应的pool
  namespace: rook-ceph
spec:
  failureDomain: host
  replicated:
    size: 3
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: rook-ceph-block    # 这里创建一个storage class, 在pvc中指定这个storage class即可实现动态创建PV
provisioner: ceph.rook.io/block
parameters:
  blockPool: replicapool
  # The value of "clusterNamespace" MUST be the same as the one in which your rook cluster exist
  clusterNamespace: rook-ceph
  # Specify the filesystem type of the volume. If not specified, it will use `ext4`.
  fstype: xfs
# Optional, default reclaimPolicy is "Delete". Other options are: "Retain", "Recycle" as documented in https://kubernetes.io/docs/concepts/storage/storage-classes/
reclaimPolicy: Retain
```
## 创建pvc
在cluster/examples/kubernetes 目录下，官方给了个worldpress的例子，可以直接运行一下：
```
kubectl create -f mysql.yaml
kubectl create -f wordpress.yaml
```
查看PV PVC：
```
[root@dev-86-201 ~]# kubectl get pvc
NAME             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS      AGE
mysql-pv-claim   Bound    pvc-a910f8c2-1ee9-11e9-84fc-becbfc415cde   20Gi       RWO            rook-ceph-block   144m
wp-pv-claim      Bound    pvc-af2dfbd4-1ee9-11e9-84fc-becbfc415cde   20Gi       RWO            rook-ceph-block   144m

[root@dev-86-201 ~]# kubectl get pv
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                    STORAGECLASS      REASON   AGE
pvc-a910f8c2-1ee9-11e9-84fc-becbfc415cde   20Gi       RWO            Retain           Bound    default/mysql-pv-claim   rook-ceph-block            145m
pvc-af2dfbd4-1ee9-11e9-84fc-becbfc415cde   20Gi       RWO            Retain           Bound    default/wp-pv-claim      rook-ceph-block            145m
```
看下yaml文件：
```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pv-claim
  labels:
    app: wordpress
spec:
  storageClassName: rook-ceph-block   # 指定storage class
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi  # 需要一个20G的盘

...

        volumeMounts:
        - name: mysql-persistent-storage
          mountPath: /var/lib/mysql
      volumes:
      - name: mysql-persistent-storage
        persistentVolumeClaim:
          claimName: mysql-pv-claim  # 指定上面定义的PVC
```
是不是非常简单。

要访问wordpress的话请把service改成NodePort类型，官方给的是loadbalance类型：
```
kubectl edit svc wordpress

[root@dev-86-201 kubernetes]# kubectl get svc
NAME              TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
wordpress         NodePort    10.109.30.99   <none>        80:30130/TCP   148m
```

# ceph集群监控
通过prometheus operator配合rook可以快速构建ceph集群的监控，sealyun安装包中已经自带了prometheus operator，所以直接干即可

## 启动ceph prometheus
注意这里是为ceph单独起了一个prometheus，这样做挺好，因为毕竟可以缓解prometheus单点的压力
```
cd cluster/examples/kubernetes/ceph/monitoring
kubectl create -f service-monitor.yaml
kubectl create -f prometheus.yaml
kubectl create -f prometheus-service.yaml
```

然后我们的grafana在30000端口，先在grafana上添加数据源

![](/ceph/data-source.png)

数据源要配置成：
```
http://rook-prometheus.rook-ceph.svc.cluster.local:9090
```

## 导入dashboard
![](/ceph/import1.png)
![](/ceph/import2.png)
![](/ceph/import3.png)

还有几个别的dashboard可以导入：
[Ceph - Cluster](https://grafana.com/dashboards/2842)
[Ceph - OSD](https://grafana.com/dashboards/5336)
[Ceph - Pools](https://grafana.com/dashboards/5342)

再次感叹生态之强大

# 总结
分布式存储在容器集群中充当非常重要的角色，使用容器集群一个非常重要的理念就是把集群当成一个整体使用，如果你在使用中还关心单个主机，比如调度到某个节点，

挂载某个节点目录等，必然会导致不能把云的威力百分之百发挥出来。   一旦计算存储分离后，就可真正实现随意漂移，对集群维护来说是个极大的福音。

比如集群机器过保了需要下架，那么我们云化的架构因为所有东西无单点，所以只需要简单驱逐改节点，然后下架即可，不用关心上面跑的是什么业务，不管是有状态还是无

状态的都可以自动修复。 不过目前面临最大的挑战可能还是分布式存储的性能问题。  在性能要求不苛刻的场景下我是极推荐这种计算存储分离架构的。


探讨可加QQ群：98488045

# 公众号：
![sealyun](https://sealyun.com/kubernetes-qrcode.jpg)

### 微信群：
![](/wechatgroup1.png)
