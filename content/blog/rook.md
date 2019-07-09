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

本文中需要用的yaml文件和Dockerfile等都放到这个[仓库](https://github.com/sealyun/rook)
包含：rook operator ceph cluster storage class配置，mysql wordpress事例，性能测试fio Dockerfile与yaml等
<!--more-->

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

# 外部访问ceph集群
cluster.yaml里有配置，可配置成共享宿主机网络，这样外面可直接连接ceph集群：
```
  network:
    # toggle to use hostNetwork
    hostNetwork: false
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

# 增加节点,删除节点
```
kubectl edit cephcluster rook-ceph -n rook-ceph
```
把useAllNodes设置成false，然后在nodes列表里增加节点名即可，保存退出后会自动增加ceph节点
```
    nodes:
    - config: null
      name: izj6c3afuzdjhtkj156zt0z
      resources: {}
    - config: null
      name: izj6cg4wnagly61eny0hy9z
      resources: {}
    - config: null
      name: izj6cg4wnagly61eny0hyaz
      resources: {}
    useAllDevices: false
```
删除同理，直接edit删除即可，十分强大

# 性能测试 
这里着重说明测试方法，给出在我的场景下的测试结果，用户应当根据自己的场景进行自己的测试。

## 测试环境
我这里使用阿里云服务器，挂载了一个1000G的磁盘，不过我实际测试时用的盘很少（盘大太慢）
```
[root@izj6c3afuzdjhtkj156zt0z ~]# df -h|grep dev
devtmpfs        3.9G     0  3.9G    0% /dev
tmpfs           3.9G     0  3.9G    0% /dev/shm
/dev/vda1        40G   17G   21G   44% /
/dev/vdb1       985G   41G  895G    5% /data   
/dev/rbd0       296G  2.1G  294G    1% /var/lib/kubelet/plugins/ceph.rook.io/rook-ceph-system/mounts/pvc-692e2be3-2434-11e9-aef7-00163e01e813
```
可看到一个本地盘和一个ceph挂过来的盘

先搞个fio的镜像
```
[root@izj6c3afuzdjhtkj156zt0z fio]# cat Dockerfile
FROM docker.io/centos:7.6.1810
RUN yum install -y fio
```

测试容器，稍微改一下mysql的yaml:
```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pv-claim
  labels:
    app: wordpress
spec:
  storageClassName: rook-ceph-block
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 300Gi
---
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: wordpress-mysql
  labels:
    app: wordpress
spec:
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: wordpress
        tier: mysql
    spec:
      containers:
      - image: fio:latest
        imagePullPolicy: IfNotPresent
        command: ["sleep", "10000000"]
        name: mysql
        volumeMounts:
        - name: mysql-persistent-storage
          mountPath: /var/lib/mysql
      volumes:
      - name: mysql-persistent-storage
        persistentVolumeClaim:
          claimName: mysql-pv-claim
```
## 测试过程
进入到容器内跑测试工具：
```
$ kubectl exec -it wordpress-mysql-775c44887c-5vhx9 bash

# touch /var/lib/mysql/test # 创建测试文件
# fio -filename=/var/lib/mysql/test -direct=1 -iodepth=128 -rw=randrw -ioengine=libaio -bs=4k -size=200G -numjobs=8 -runtime=100 -group_reporting -name=Rand_Write_Testing
```
结果：
```
Rand_Write_Testing: (g=0): rw=randrw, bs=(R) 4096B-4096B, (W) 4096B-4096B, (T) 4096B-4096B, ioengine=libaio, iodepth=128
...
fio-3.1
Starting 2 processes
Rand_Write_Testing: Laying out IO file (1 file / 2048MiB)
Jobs: 2 (f=2): [m(2)][100.0%][r=16.6MiB/s,w=17.2MiB/s][r=4240,w=4415 IOPS][eta 00m:00s]
Rand_Write_Testing: (groupid=0, jobs=2): err= 0: pid=34: Wed Jan 30 02:44:18 2019
   read: IOPS=3693, BW=14.4MiB/s (15.1MB/s)(1443MiB/100013msec)
    slat (usec): min=2, max=203952, avg=262.47, stdev=2107.16
    clat (msec): min=3, max=702, avg=30.85, stdev=30.97
     lat (msec): min=3, max=702, avg=31.11, stdev=31.21
    clat percentiles (msec):
     |  1.00th=[   12],  5.00th=[   14], 10.00th=[   16], 20.00th=[   18],
     | 30.00th=[   20], 40.00th=[   22], 50.00th=[   24], 60.00th=[   27],
     | 70.00th=[   30], 80.00th=[   36], 90.00th=[   46], 95.00th=[   64],
     | 99.00th=[  194], 99.50th=[  213], 99.90th=[  334], 99.95th=[  397],
     | 99.99th=[  502]
   bw (  KiB/s): min=  440, max=12800, per=49.98%, avg=7383.83, stdev=3004.90, samples=400
   iops        : min=  110, max= 3200, avg=1845.92, stdev=751.22, samples=400
  write: IOPS=3700, BW=14.5MiB/s (15.2MB/s)(1446MiB/100013msec)
    slat (usec): min=2, max=172409, avg=266.11, stdev=2004.53
    clat (msec): min=7, max=711, avg=37.85, stdev=37.52
     lat (msec): min=7, max=711, avg=38.12, stdev=37.72
    clat percentiles (msec):
     |  1.00th=[   16],  5.00th=[   19], 10.00th=[   21], 20.00th=[   23],
     | 30.00th=[   25], 40.00th=[   27], 50.00th=[   29], 60.00th=[   32],
     | 70.00th=[   36], 80.00th=[   42], 90.00th=[   53], 95.00th=[   73],
     | 99.00th=[  213], 99.50th=[  292], 99.90th=[  397], 99.95th=[  472],
     | 99.99th=[  600]
   bw (  KiB/s): min=  536, max=12800, per=49.98%, avg=7397.37, stdev=3000.10, samples=400
   iops        : min=  134, max= 3200, avg=1849.32, stdev=750.02, samples=400
  lat (msec)   : 4=0.01%, 10=0.22%, 20=22.18%, 50=68.05%, 100=5.90%
  lat (msec)   : 250=3.09%, 500=0.54%, 750=0.02%
  cpu          : usr=1.63%, sys=4.68%, ctx=311249, majf=0, minf=18
  IO depths    : 1=0.1%, 2=0.1%, 4=0.1%, 8=0.1%, 16=0.1%, 32=0.1%, >=64=100.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.1%
     issued rwt: total=369395,370084,0, short=0,0,0, dropped=0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=128

Run status group 0 (all jobs):
   READ: bw=14.4MiB/s (15.1MB/s), 14.4MiB/s-14.4MiB/s (15.1MB/s-15.1MB/s), io=1443MiB (1513MB), run=100013-100013msec
  WRITE: bw=14.5MiB/s (15.2MB/s), 14.5MiB/s-14.5MiB/s (15.2MB/s-15.2MB/s), io=1446MiB (1516MB), run=100013-100013msec

Disk stats (read/write):
  rbd0: ios=369133/369841, merge=0/35, ticks=4821508/7373587, in_queue=12172273, util=99.93%
```

在宿主机上测试：
```
$ touch /data/test
$ fio -filename=/data/test -direct=1 -iodepth=128 -rw=randrw -ioengine=libaio -bs=4k -size=2G -numjobs=2 -runtime=100 -group_reporting -name=Rand_Write_Testing
```
```
Rand_Write_Testing: (g=0): rw=randrw, bs=(R) 4096B-4096B, (W) 4096B-4096B, (T) 4096B-4096B, ioengine=libaio, iodepth=128
...
fio-3.1
Starting 2 processes
Rand_Write_Testing: Laying out IO file (1 file / 2048MiB)
Jobs: 2 (f=2): [m(2)][100.0%][r=19.7MiB/s,w=19.8MiB/s][r=5043,w=5056 IOPS][eta 00m:00s]
Rand_Write_Testing: (groupid=0, jobs=2): err= 0: pid=13588: Wed Jan 30 10:41:25 2019
   read: IOPS=5024, BW=19.6MiB/s (20.6MB/s)(1963MiB/100019msec)
    slat (usec): min=2, max=80213, avg=191.32, stdev=2491.48
    clat (usec): min=1022, max=176786, avg=19281.58, stdev=23666.08
     lat (usec): min=1031, max=176791, avg=19473.50, stdev=23757.08
    clat percentiles (msec):
     |  1.00th=[    3],  5.00th=[    4], 10.00th=[    5], 20.00th=[    6],
     | 30.00th=[    7], 40.00th=[    8], 50.00th=[    9], 60.00th=[   10],
     | 70.00th=[   12], 80.00th=[   25], 90.00th=[   67], 95.00th=[   73],
     | 99.00th=[   81], 99.50th=[   85], 99.90th=[   93], 99.95th=[   96],
     | 99.99th=[  104]
   bw (  KiB/s): min= 9304, max=10706, per=49.99%, avg=10046.66, stdev=243.04, samples=400
   iops        : min= 2326, max= 2676, avg=2511.62, stdev=60.73, samples=400
  write: IOPS=5035, BW=19.7MiB/s (20.6MB/s)(1967MiB/100019msec)
    slat (usec): min=3, max=76025, avg=197.61, stdev=2504.40
    clat (msec): min=2, max=155, avg=31.21, stdev=27.12
     lat (msec): min=2, max=155, avg=31.40, stdev=27.16
    clat percentiles (msec):
     |  1.00th=[    7],  5.00th=[    9], 10.00th=[   10], 20.00th=[   11],
     | 30.00th=[   13], 40.00th=[   14], 50.00th=[   15], 60.00th=[   18],
     | 70.00th=[   48], 80.00th=[   68], 90.00th=[   75], 95.00th=[   80],
     | 99.00th=[   88], 99.50th=[   93], 99.90th=[  102], 99.95th=[  104],
     | 99.99th=[  112]
   bw (  KiB/s): min= 9208, max=10784, per=49.98%, avg=10066.14, stdev=214.26, samples=400
   iops        : min= 2302, max= 2696, avg=2516.50, stdev=53.54, samples=400
  lat (msec)   : 2=0.04%, 4=3.09%, 10=34.76%, 20=33.31%, 50=5.05%
  lat (msec)   : 100=23.67%, 250=0.08%
  cpu          : usr=1.54%, sys=5.80%, ctx=286367, majf=0, minf=20
  IO depths    : 1=0.1%, 2=0.1%, 4=0.1%, 8=0.1%, 16=0.1%, 32=0.1%, >=64=100.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.1%
     issued rwt: total=502523,503598,0, short=0,0,0, dropped=0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=128

Run status group 0 (all jobs):
   READ: bw=19.6MiB/s (20.6MB/s), 19.6MiB/s-19.6MiB/s (20.6MB/s-20.6MB/s), io=1963MiB (2058MB), run=100019-100019msec
  WRITE: bw=19.7MiB/s (20.6MB/s), 19.7MiB/s-19.7MiB/s (20.6MB/s-20.6MB/s), io=1967MiB (2063MB), run=100019-100019msec

Disk stats (read/write):
  vdb: ios=502513/504275, merge=0/658, ticks=4271124/7962372, in_queue=11283349, util=92.48%
```
这里看到随机读写性能损失约 27%多，这个结论并没有太多参考意义，用户应当根据自己实际场景进行测试

改用ceph共享宿主机网络模式进行测试，结果差不多，并无性能提升

要想排除在容器内测试因素的影响，也可以直接在宿主机上对块设备进行测试，做法很简单，可以把块挂到别的目录上如：

```
umount /dev/rbd0
mkdir /data1
mount /dev/rbd0 /data1
touch /data1/test  # 然后对这个文件测试，我这边测试结果与容器内差不多
```

# bluestore方式
直接使用裸盘而不使用分区或者文件系统的方式部署ceph
```
storage:
  useAllNodes: false
  useAllDevices: false
  deviceFilter:
  location:
  config:
    storeType: bluestore
  nodes:
  - name: "ke-dev1-worker1"
    devices:
    - name: "vde"
  - name: "ke-dev1-worker3"
    devices:
    - name: "vde"
  - name: "ke-dev1-worker4"
    devices:
    - name: "vdf"
```

bluestore模式能显著提升ceph性能，我这边测试随机读写性能提升了8%左右
```
Rand_Write_Testing: (g=0): rw=randrw, bs=(R) 4096B-4096B, (W) 4096B-4096B, (T) 4096B-4096B, ioengine=libaio, iodepth=128
...
fio-3.1
Starting 2 processes
Rand_Write_Testing: Laying out IO file (1 file / 2048MiB)
Jobs: 2 (f=2): [m(2)][100.0%][r=16.4MiB/s,w=16.7MiB/s][r=4189,w=4284 IOPS][eta 00m:00s]]
Rand_Write_Testing: (groupid=0, jobs=2): err= 0: pid=25: Thu Jan 31 11:37:39 2019
   read: IOPS=3990, BW=15.6MiB/s (16.3MB/s)(1566MiB/100464msec)
    slat (usec): min=2, max=246625, avg=239.16, stdev=1067.33
    clat (msec): min=2, max=493, avg=27.68, stdev=16.71
     lat (msec): min=2, max=493, avg=27.92, stdev=16.75
    clat percentiles (msec):
     |  1.00th=[   12],  5.00th=[   15], 10.00th=[   16], 20.00th=[   18],
     | 30.00th=[   20], 40.00th=[   22], 50.00th=[   24], 60.00th=[   27],
     | 70.00th=[   30], 80.00th=[   35], 90.00th=[   45], 95.00th=[   54],
     | 99.00th=[   74], 99.50th=[   84], 99.90th=[  199], 99.95th=[  334],
     | 99.99th=[  485]
   bw (  KiB/s): min= 2118, max=10456, per=50.20%, avg=8013.40, stdev=1255.78, samples=400
   iops        : min=  529, max= 2614, avg=2003.31, stdev=313.95, samples=400
  write: IOPS=3997, BW=15.6MiB/s (16.4MB/s)(1569MiB/100464msec)
    slat (usec): min=3, max=273211, avg=246.87, stdev=1026.98
    clat (msec): min=11, max=499, avg=35.90, stdev=18.04
     lat (msec): min=12, max=506, avg=36.15, stdev=18.08
    clat percentiles (msec):
     |  1.00th=[   19],  5.00th=[   22], 10.00th=[   23], 20.00th=[   26],
     | 30.00th=[   28], 40.00th=[   30], 50.00th=[   33], 60.00th=[   35],
     | 70.00th=[   39], 80.00th=[   44], 90.00th=[   54], 95.00th=[   63],
     | 99.00th=[   85], 99.50th=[   95], 99.90th=[  309], 99.95th=[  351],
     | 99.99th=[  489]
   bw (  KiB/s): min= 2141, max=10163, per=50.20%, avg=8026.23, stdev=1251.78, samples=400
   iops        : min=  535, max= 2540, avg=2006.51, stdev=312.94, samples=400
  lat (msec)   : 4=0.01%, 10=0.10%, 20=16.63%, 50=73.71%, 100=9.25%
  lat (msec)   : 250=0.22%, 500=0.09%
  cpu          : usr=1.85%, sys=5.60%, ctx=366744, majf=0, minf=17
  IO depths    : 1=0.1%, 2=0.1%, 4=0.1%, 8=0.1%, 16=0.1%, 32=0.1%, >=64=100.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.1%
     issued rwt: total=400928,401597,0, short=0,0,0, dropped=0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=128

Run status group 0 (all jobs):
   READ: bw=15.6MiB/s (16.3MB/s), 15.6MiB/s-15.6MiB/s (16.3MB/s-16.3MB/s), io=1566MiB (1642MB), run=100464-100464msec
  WRITE: bw=15.6MiB/s (16.4MB/s), 15.6MiB/s-15.6MiB/s (16.4MB/s-16.4MB/s), io=1569MiB (1645MB), run=100464-100464msec

Disk stats (read/write):
  rbd0: ios=400921/401817, merge=0/50, ticks=4341605/7883816, in_queue=12217335, util=99.96%
```

# 总结
分布式存储在容器集群中充当非常重要的角色，使用容器集群一个非常重要的理念就是把集群当成一个整体使用，如果你在使用中还关心单个主机，比如调度到某个节点，

挂载某个节点目录等，必然会导致不能把云的威力百分之百发挥出来。   一旦计算存储分离后，就可真正实现随意漂移，对集群维护来说是个极大的福音。

比如集群机器过保了需要下架，那么我们云化的架构因为所有东西无单点，所以只需要简单驱逐改节点，然后下架即可，不用关心上面跑的是什么业务，不管是有状态还是无

状态的都可以自动修复。 不过目前面临最大的挑战可能还是分布式存储的性能问题。  在性能要求不苛刻的场景下我是极推荐这种计算存储分离架构的。

# 常见问题
注意主机时间一定要同步
```
ntpdate 0.asia.pool.ntp.org
```

## ceph cluster无法启动
报这个错误
```
$ kubectl logs rook-ceph-mon-a-c5f54799f-rd7s4 -n rook-ceph
2019-01-27 11:04:59.985 7f0a34a4f140 -1 rocksdb: Invalid argument: /var/lib/rook/mon-a/data/store.db: does not exist (create_if_missing is false)
2019-01-27 11:04:59.985 7f0a34a4f140 -1 rocksdb: Invalid argument: /var/lib/rook/mon-a/data/store.db: does not exist (create_if_missing is false)
2019-01-27 11:04:59.985 7f0a34a4f140 -1 error opening mon data directory at '/var/lib/rook/mon-a/data': (22) Invalid argument
2019-01-27 11:04:59.985 7f0a34a4f140 -1 error opening mon data directory at '/var/lib/rook/mon-a/data': (22) Invalid argument
```
需要把宿主机store.db文件删掉,然后delete pod即可, 主意别指错目录如果自己改了目录的话
```
rm -rf  /var/lib/rook/mon-a/data/store.db
```

## rook删除PVC PV依然存在
因为storageclass回收参数：
```
reclaimPolicy: Retain  # 设置成Delete即可
```

## rook-ceph namespace无法删除 cephclusters.ceph.rook.io CRD无法删除
```
[root@izj6c3afuzdjhtkj156zt0z ~]# kubectl get ns
NAME          STATUS        AGE
default       Active        18h
kube-public   Active        18h
kube-system   Active        18h
monitoring    Active        18h
rook-ceph     Terminating   17h
```

把CRD metadata finalizers下面的内容删了，CRD就会自动删除，然后只要rook-ceph namespace里没有东西就会自动清理掉
```
$ kubectl edit crd cephclusters.ceph.rook.io
```

## 使用宿主机网络时集群无法正常启动
集群中单节点时把mon设置成1即可
```
  mon:
    count: 1
    allowMultiplePerNode: true

  network:
    # toggle to use hostNetwork
    hostNetwork: true
```

探讨可加QQ群：98488045

