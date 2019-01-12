+++
author = "fanux"
date = "2018-04-24T10:54:24+02:00"
draft = false
title = "k8s离线包解析"
#slug = "dotscale-2014-as-a-sketch"
tags = ["event","dotScale","sketchnote"]
image = "images/2014/Jul/titledotscale.png"
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

# k8s离线包解析
[产品地址](http://sealyun.com/pro/products/)
## 鸣谢
* 大家好，首先感谢大家对我们产品的支持，特别是一些老客户的持续支持，让我可以有动力把这个事情持续进行下去。
* 感谢大家对付费产品的认可，尊重付费

## 产品介绍
我们专注于k8s离线包的制作，优化细节，让大家可以很方便快速的安装k8s集群。
下面详细介绍安装包的原理以及如何去制作一个这样的包，大家参考我的方法也可以制作自己想要的版本然后用于自己的离线环境

## 目录结构
```
.
├── bin  # 指定版本的bin文件，只需要这三个，其它组件跑容器里
│   ├── kubeadm
│   ├── kubectl
│   └── kubelet
├── conf
│   ├── 10-kubeadm.conf  # 这个文件新版本没用到，我在shell里直接生成，这样可以检测cgroup driver
│   ├── dashboard
│   │   ├── dashboard-admin.yaml
│   │   └── kubernetes-dashboard.yaml
│   ├── heapster
│   │   ├── grafana.yaml
│   │   ├── heapster.yaml
│   │   ├── influxdb.yaml
│   │   └── rbac
│   │       └── heapster-rbac.yaml
│   ├── kubeadm.yaml # kubeadm的配置文件
│   ├── kubelet.service  # kubelet systemd配置文件
│   ├── net
│   │   └── calico.yaml
│   └── promethus
├── images  # 所有镜像包
│   └── images.tar
└── shell
    ├── init.sh  # 初始化脚本
    └── master.sh # 运行master脚本
```

## init.sh解析
```
# 网络配置，让calico可以路由
cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system
sysctl -w net.ipv4.ip_forward=1


# 关闭防火墙 交换分区 selinux
systemctl stop firewalld && systemctl disable firewalld
swapoff -a
setenforce 0

# 导入镜像
docker load -i ../images/images.tar
cp ../bin/kube* /usr/bin

# Cgroup driver
cp ../conf/kubelet.service /etc/systemd/system/
mkdir /etc/systemd/system/kubelet.service.d

# 获取docker Cgroup driver类型，kubelet systemd配置需要一致
cgroupDriver=$(docker info|grep Cg)
driver=${cgroupDriver##*: }
echo "driver is ${driver}"

cat <<EOF > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_SYSTEM_PODS_ARGS=--pod-manifest-path=/etc/kubernetes/manifests --allow-privileged=true"
Environment="KUBELET_NETWORK_ARGS=--network-plugin=cni --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=/opt/cni/bin"
Environment="KUBELET_DNS_ARGS=--cluster-dns=10.96.0.10 --cluster-domain=cluster.local"
Environment="KUBELET_AUTHZ_ARGS=--authorization-mode=Webhook --client-ca-file=/etc/kubernetes/pki/ca.crt"
Environment="KUBELET_CADVISOR_ARGS=--cadvisor-port=0"
Environment="KUBELET_CGROUP_ARGS=--cgroup-driver=${driver}" # 看这里
Environment="KUBELET_CERTIFICATE_ARGS=--rotate-certificates=true --cert-dir=/var/lib/kubelet/pki"
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_KUBECONFIG_ARGS \$KUBELET_SYSTEM_PODS_ARGS \$KUBELET_NETWORK_ARGS \$KUBELET_DNS_ARGS \$KUBELET_AUTHZ_ARGS \$KUBELET_CADVISOR_ARGS \$KUBELET_CGROUP_ARGS \$KUBELET_CERTIFICATE_ARGS \$KUBELET_EXTRA_ARGS
EOF

systemctl enable kubelet
systemctl enable docker
```

## master.sh解析
```
# 启动kubeadm
kubeadm init --config ../conf/kubeadm.yaml

# kubectl配置拷贝
mkdir ~/.kube
cp /etc/kubernetes/admin.conf ~/.kube/config

# 装网络
kubectl apply -f ../conf/net/calico.yaml

# 去污点，生产环境中最好不去，我是为了heapster能正常启动
kubectl taint nodes --all node-role.kubernetes.io/master-

# 装heapster
kubectl apply -f ../conf/heapster/
kubectl apply -f ../conf/heapster/rbac

# 装dashboard
kubectl apply -f ../conf/dashboard
```

## 制作过程

### 下载bin文件
我们到github kubernetes下把bin文件下载下来，只需要下载node的bin即可，当然如果你master镜像不好下载也可以下载全部bin
如：[node bin文件](https://dl.k8s.io/v1.10.3/kubernetes-node-linux-amd64.tar.gz)

拷贝到/usr/bin下面，kubectl kubeadm kubelet 三个是必须的

### 拷贝kubelet service文件，脚本里有

### 修改kubeadm.yaml
修改里面版本与bin版本一致，然后启动kubeadm  kubeadm init --config kubeadm.yaml
这里可能有的镜像下载不下来，你就得导入了

### 一切正常后保存所有镜像
docker save -o images.tar $(docker images|grep ago|awk '{print $1":"$2}')
这里最好搞干净的服务器，不然别的镜像也会被save下来


# 公众号：
![sealyun](https://sealyun.com/kubernetes-qrcode.jpg)

### 微信群：
![](/wechatgroup1.png)
