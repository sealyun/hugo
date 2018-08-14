+++
author = "fanux"
date = "2018-08-12T10:54:24+02:00"
draft = false
title = "etcd管理指南"
#slug = "dotscale-2014-as-a-sketch"
tags = ["event","dotScale","sketchnote"]
#image = "images/2014/Jul/titledotscale.png"
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

> 广告 | [kubernetes各版本离线安装包](http://sealyun.com/pro/products/)


# etcd 证书配置
## 证书生成
cfssl安装：
```
mkdir ~/bin
curl -s -L -o ~/bin/cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
curl -s -L -o ~/bin/cfssljson https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
chmod +x ~/bin/{cfssl,cfssljson}
export PATH=$PATH:~/bin
```
```
mkdir ~/cfssl
cd ~/cfssl
```
写入如下json文件，ip替换成自己的
```
root@dev-86-201 cfssl]# cat ca-config.json
{
    "signing": {
        "default": {
            "expiry": "43800h"
        },
        "profiles": {
            "server": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth"
                ]
            },
            "client": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth"
                ]
            },
            "peer": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            }
        }
    }
}
[root@dev-86-201 cfssl]# cat ca-csr.json
{
    "CN": "My own CA",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "US",
            "L": "CA",
            "O": "My Company Name",
            "ST": "San Francisco",
            "OU": "Org Unit 1",
            "OU": "Org Unit 2"
        }
    ]
}
[root@dev-86-201 cfssl]# cat server.json
{
    "CN": "etcd0",
    "hosts": [
        "127.0.0.1",
        "0.0.0.0",
        "10.1.86.201",
        "10.1.86.203",
        "10.1.86.202"
    ],
    "key": {
        "algo": "ecdsa",
        "size": 256
    },
    "names": [
        {
            "C": "US",
            "L": "CA",
            "ST": "San Francisco"
        }
    ]
}

[root@dev-86-201 cfssl]# cat member1.json  # 填本机IP
{
    "CN": "etcd0",
    "hosts": [
        "10.1.86.201"
    ],
    "key": {
        "algo": "ecdsa",
        "size": 256
    },
    "names": [
        {
            "C": "US",
            "L": "CA",
            "ST": "San Francisco"
        }
    ]
}

[root@dev-86-201 cfssl]# cat client.json
{
    "CN": "client",
    "hosts": [
       ""
    ],
    "key": {
        "algo": "ecdsa",
        "size": 256
    },
    "names": [
        {
            "C": "US",
            "L": "CA",
            "ST": "San Francisco"
        }
    ]
}
```

生成证书：
```
cfssl gencert -initca ca-csr.json | cfssljson -bare ca -
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=server server.json | cfssljson -bare server
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=peer member1.json | cfssljson -bare member1
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=client client.json | cfssljson -bare client
```
## 启动etcd
cfssl目录拷贝到/etc/kubernetes/pki/cfssl 目录
```
[root@dev-86-201 manifests]# cat etcd.yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    scheduler.alpha.kubernetes.io/critical-pod: ""
  creationTimestamp: null
  labels:
    component: etcd
    tier: control-plane
  name: etcd
  namespace: kube-system
spec:
  containers:
  - command:
    - etcd
    - --advertise-client-urls=https://10.1.86.201:2379
    - --cert-file=/etc/kubernetes/pki/etcd/server.pem
    - --client-cert-auth=true
    - --data-dir=/var/lib/etcd
    - --initial-advertise-peer-urls=https://10.1.86.201:2380
    - --initial-cluster=etcd0=https://10.1.86.201:2380
    - --key-file=/etc/kubernetes/pki/etcd/server-key.pem
    - --listen-client-urls=https://10.1.86.201:2379
    - --listen-peer-urls=https://10.1.86.201:2380
    - --name=etcd0
    - --peer-cert-file=/etc/kubernetes/pki/etcd/member1.pem
    - --peer-client-cert-auth=true
    - --peer-key-file=/etc/kubernetes/pki/etcd/member1-key.pem
    - --peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.pem
    - --snapshot-count=10000
    - --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.pem
    image: k8s.gcr.io/etcd-amd64:3.2.18
    imagePullPolicy: IfNotPresent
   #livenessProbe:
   #  exec:
   #    command:
   #    - /bin/sh
   #    - -ec
   #    - ETCDCTL_API=3 etcdctl --endpoints=https://[10.1.86.201]:2379 --cacert=/etc/kubernetes/pki/etcd/ca.pem
   #      --cert=/etc/kubernetes/pki/etcd/client.pem --key=/etc/kubernetes/pki/etcd/client-key.pem
   #      get foo
   #  failureThreshold: 8
   #  initialDelaySeconds: 15
   #  timeoutSeconds: 15
    name: etcd
    resources: {}
    volumeMounts:
    - mountPath: /var/lib/etcd
      name: etcd-data
    - mountPath: /etc/kubernetes/pki/etcd
      name: etcd-certs
  hostNetwork: true
  priorityClassName: system-cluster-critical
  volumes:
  - hostPath:
      path: /var/lib/etcd
      type: DirectoryOrCreate
    name: etcd-data
  - hostPath:
      path: /etc/kubernetes/pki/cfssl
      type: DirectoryOrCreate
    name: etcd-certs
status: {}
```
进入etcd容器执行：
```
alias etcdxx="ETCDCTL_API=3 etcdctl --endpoints=https://[10.1.86.201]:2379 --cacert=/etc/kubernetes/pki/etcd/ca.pem --cert=/etc/kubernetes/pki/etcd/client.pem --key=/etc/kubernetes/pki/etcd/client-key.pem"
etcdxx member add etcd1 --peer-urls="https://10.1.86.202:2380"
```
## 增加节点
拷贝etcd0(10.1.86.201)节点上的证书到etcd1(10.1.86.202)节点上
修改member1.json:
```
{
    "CN": "etcd1",
    "hosts": [
        "10.1.86.202"
    ],
    "key": {
        "algo": "ecdsa",
        "size": 256
    },
    "names": [
        {
            "C": "US",
            "L": "CA",
            "ST": "San Francisco"
        }
    ]
}
```
重新生成在etcd1上生成member1证书：
```
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=peer member1.json | cfssljson -bare member1
```
启动etcd1：
```
[root@dev-86-202 manifests]# cat etcd.yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    scheduler.alpha.kubernetes.io/critical-pod: ""
  creationTimestamp: null
  labels:
    component: etcd
    tier: control-plane
  name: etcd
  namespace: kube-system
spec:
  containers:
  - command:
    - etcd
    - --advertise-client-urls=https://10.1.86.202:2379
    - --cert-file=/etc/kubernetes/pki/etcd/server.pem
    - --data-dir=/var/lib/etcd
    - --initial-advertise-peer-urls=https://10.1.86.202:2380
    - --initial-cluster=etcd0=https://10.1.86.201:2380,etcd1=https://10.1.86.202:2380
    - --key-file=/etc/kubernetes/pki/etcd/server-key.pem
    - --listen-client-urls=https://10.1.86.202:2379
    - --listen-peer-urls=https://10.1.86.202:2380
    - --name=etcd1
    - --peer-cert-file=/etc/kubernetes/pki/etcd/member1.pem
    - --peer-client-cert-auth=true
    - --peer-key-file=/etc/kubernetes/pki/etcd/member1-key.pem
    - --peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.pem
    - --snapshot-count=10000
    - --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.pem
    - --initial-cluster-state=existing  # 千万别加双引号，被坑死
    image: k8s.gcr.io/etcd-amd64:3.2.18
    imagePullPolicy: IfNotPresent
  # livenessProbe:
  #   exec:
  #     command:
  #     - /bin/sh
  #     - -ec
  #     - ETCDCTL_API=3 etcdctl --endpoints=https://[10.1.86.202]:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt
  #       --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt --key=/etc/kubernetes/pki/etcd/healthcheck-client.key
  #       get foo
  #   failureThreshold: 8
  #   initialDelaySeconds: 15
  #   timeoutSeconds: 15
    name: etcd
    resources: {}
    volumeMounts:
    - mountPath: /var/lib/etcd
      name: etcd-data
    - mountPath: /etc/kubernetes/pki/etcd
      name: etcd-certs
  hostNetwork: true
  priorityClassName: system-cluster-critical
  volumes:
  - hostPath:
      path: /var/lib/etcd
      type: DirectoryOrCreate
    name: etcd-data
  - hostPath:
      path: /etc/kubernetes/pki/cfssl
      type: DirectoryOrCreate
    name: etcd-certs
status: {}
```
或者用docker起先测试一下：
```
docker run --net=host -v /etc/kubernetes/pki/cfssl:/etc/kubernetes/pki/etcd k8s.gcr.io/etcd-amd64:3.2.18 etcd \
--advertise-client-urls=https://10.1.86.202:2379 \
--cert-file=/etc/kubernetes/pki/etcd/server.pem \
--data-dir=/var/lib/etcd \
--initial-advertise-peer-urls=https://10.1.86.202:2380 \
--initial-cluster=etcd0=https://10.1.86.201:2380,etcd1=https://10.1.86.202:2380 \
--key-file=/etc/kubernetes/pki/etcd/server-key.pem  \
--listen-client-urls=https://10.1.86.202:2379 \
--listen-peer-urls=https://10.1.86.202:2380 --name=etcd1 \
--peer-cert-file=/etc/kubernetes/pki/etcd/member1.pem \
--peer-key-file=/etc/kubernetes/pki/etcd/member1-key.pem \
--peer-client-cert-auth=true \
--peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.pem --snapshot-count=10000 \
--trusted-ca-file=/etc/kubernetes/pki/etcd/ca.pem --initial-cluster-state="existing"
```

etcd0上检查集群健康:
```
# etcdctl --endpoints=https://[10.1.86.201]:2379 --ca-file=/etc/kubernetes/pki/etcd/ca.pem --cert-file=/etc/kubernetes/pki/etcd/client.pem --key-file=/etc/kubernetes/pki/etcd/client-key.pem cluster-heal
th
member 5856099674401300 is healthy: got healthy result from https://10.1.86.201:2379
member df99f445ac908d15 is healthy: got healthy result from https://10.1.86.202:2379
cluster is healthy
```
etcd2增加同理，略

apiserver etcd证书 配置：
```
- --etcd-cafile=/etc/kubernetes/pki/cfssl/ca.pem
- --etcd-certfile=/etc/kubernetes/pki/cfssl/client.pem
- --etcd-keyfile=/etc/kubernetes/pki/cfssl/client-key.pem
```

## etcd快照恢复

说明：
有证书集群以下所有命令需带上如下证书参数，否则访问不了
```
--cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/peer.crt --key=/etc/kubernetes/pki/etcd/peer.key
```

endpoints默认为```127.0.0.1:2379```，若需指定远程etcd地址，可通过如下参数指定

```
--endpoints 172.16.154.81:2379
```

1、获取数据快照

```
ETCDCTL_API=3 etcdctl snapshot save snapshot.db
```

2、从快照恢复数据

```
ETCDCTL_API=3 etcdctl snapshot restore snapshot.db --data-dir=/var/lib/etcd/
```

3、启动新etcd节点，指定--data-dir=/var/lib/etcd/

## etcd节点扩容

节点名|IP|备注
----|----|--------------
infra0|172.16.154.81|初始节点，k8s的master节点，kubeadm所部署的单节点etcd所在机器
infra1|172.16.154.82|待添加节点，k8s的node节点
infra2|172.16.154.83|待添加节点，k8s的node节点

1、从初始etcd节点获取数据快照

```
ETCDCTL_API=3 etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/peer.crt --key=/etc/kubernetes/pki/etcd/peer.key --endpoints=https://127.0.0.1:2379 snapshot save snapshot.db
```

2、将快照文件snapshot.db复制到infra1节点，并执行数据恢复命令

数据恢复命令

```
ETCDCTL_API=3 etcdctl snapshot restore snapshot.db --data-dir=/var/lib/etcd/

注：执行上述命令需要机器上有etcdctl
```

上述命令执行成功会将快照中的数据存放到/var/lib/etcd目录中

3、在infra1节点启动etcd
将如下yaml放入/etc/kubernetes/manifests

```
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: etcd
    tier: control-plane
  name: etcd-172.16.154.82
  namespace: kube-system
spec:
  containers:
  - command:
    - etcd
    - --name=infra0
    - --initial-advertise-peer-urls=http://172.16.154.82:2380
    - --listen-peer-urls=http://172.16.154.82:2380
    - --listen-client-urls=http://172.16.154.82:2379,http://127.0.0.1:2379
    - --advertise-client-urls=http://172.16.154.82:2379
    - --data-dir=/var/lib/etcd
    - --initial-cluster-token=etcd-cluster-1
    - --initial-cluster=infra0=http://172.16.154.82:2380
    - --initial-cluster-state=new
    image: hub.xfyun.cn/k8s/etcd-amd64:3.1.12
    livenessProbe:
      httpGet:
        host: 127.0.0.1
        path: /health
        port: 2379
        scheme: HTTP
      failureThreshold: 8
      initialDelaySeconds: 15
      timeoutSeconds: 15
    name: etcd
    volumeMounts:
    - name: etcd-data
      mountPath: /var/lib/etcd
  hostNetwork: true
  volumes:
  - hostPath:
      path: /var/lib/etcd
      type: DirectoryOrCreate
    name: etcd-data
```

4、infra2节点加入etcd集群中
在infra1中etcd容器中执行

```
ETCDCTL_API=3 etcdctl member add infra2 --peer-urls="http://172.16.154.83:2380"
```

将如下yaml放入/etc/kubernetes/manifests，由kubelet启动etcd容器

```
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: etcd
    tier: control-plane
  name: etcd-172.16.154.83
  namespace: kube-system
spec:
  containers:
  - command:
    - etcd
    - --name=infra1
    - --initial-advertise-peer-urls=http://172.16.154.83:2380
    - --listen-peer-urls=http://172.16.154.83:2380
    - --listen-client-urls=http://172.16.154.83:2379,http://127.0.0.1:2379
    - --advertise-client-urls=http://172.16.154.83:2379
    - --data-dir=/var/lib/etcd
    - --initial-cluster-token=etcd-cluster-1
    - --initial-cluster=infra1=http://172.16.154.82:2380,infra2=http://172.16.154.83:2380
    - --initial-cluster-state=existing
    image: hub.xfyun.cn/k8s/etcd-amd64:3.1.12
    livenessProbe:
      httpGet:
        host: 127.0.0.1
        path: /health
        port: 2379
        scheme: HTTP
      failureThreshold: 8
      initialDelaySeconds: 15
      timeoutSeconds: 15
    name: etcd
    volumeMounts:
    - name: etcd-data
      mountPath: /var/lib/etcd
  hostNetwork: true
  volumes:
  - hostPath:
      path: /home/etcd
      type: DirectoryOrCreate
    name: etcd-data
```

infra0节点加入集群重复上述操作；注意在加入集群之前，将之前/var/lib/etcd/的数据删除。


