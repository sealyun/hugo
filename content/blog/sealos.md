+++
author = "fanux"
date = "2018-10-24T10:54:24+02:00"
draft = false
title = "构建生产环境可用的高可用kubernetes集群"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

# [kubernetes集群三步安装](https://sealyun.com/pro/products/)

# k8s 1.14以上版本请直接参考[sealos readme](https://github.com/fanux/sealos)

sealos是一个轻量级kubernetes HA安装项目，重点关注功能的收敛而非庞大复杂厚重，旨在容易定制。除kubelet意外其它任何组件均在容器中运行
这样做的好处有几点：

1. 保证一致性，这样避免掉很多因宿主环境问题导致的安装失败，如keepalived版本问题，系统库问题等等
2. 统一管理统一监控，这样我们就不需要为如keepalived etcd haproxy单独配置进程级别的监控，仅要监控pod即可，kubelet也会对这些容器做比较好的管理，如自动拉起等
<!--more-->

# 构建生产环境可用的高可用kubernetes集群 | [sealos项目地址](https://github.com/fanux/sealos)

# 特性
- [x] 支持任意节点的etcd集群自动构建，且etcd集群使用安全证书，通过static pod方式启动，这样可以通过监控pod来监控etcd集群健康状态
- [x] 支持多master节点，允许任意一台master宕机集群功能不受影响
- [x] calico使用etcd集群，配置安全证书，网络管控数据无单点故障
- [x] 包含dashboard, heapster coreDNS addons, coreDNS双副本，无单点故障
- [x] 使用haproxy负载master节点，同样是用static pod，这样可通过统一监控pod状态来监控haproxy是否健康
- [x] haproxy节点使用keepalived提供虚拟IP，任意一个节点宕机虚拟IP可实现漂移，不影响node连接master
- [x] node节点与kube-proxy配置使用虚拟IP
- [x] promethus 监控功能，一键安装，无需配置
- [x] [istio 微服务支持](https://sealyun.com/pro/istio/)

# ship on docker
## 你必须已经有了[sealyun kubernetes离线安装包](https://sealyun.com/pro/products/) 

原理是为了减少大家搭建ansible和sealos的环境，客户端的东西都放到docker里，把安装包挂载到容器中，然后ansible脚本会把包分发到你在hosts文件中配置的所有服务器上

所以大概分成三步：

1. 配置免密钥，把docker里的公钥分发给你所有的服务器
2. 配置ansible playbook的hosts文件
3. 执行ansible

下面逐一说明：

# 启动ansible容器与免密钥设置
找台宿主机如你的PC，或者一台服务器，把下载好的离线包拷贝到/data目录，启动sealos容器，把离线包挂载进去：
```
docker run --rm -v /data/kube{k8sversion}.tar.gz:/data/kube{k8sversion}.tar.gz -it -w /etc/ansible fanux/sealos:{k8sversion} bash
```
如安装kubernetes v1.13.0 HA:
```
docker run --rm -v /data/kube1.13.0.tar.gz:/data/kube1.13.0.tar.gz -it -w /etc/ansible fanux/sealos:v1.13.0 bash
```

在容器里面执行：
```
mkdir ~/.ssh
cd ~/.ssh
ssh-keygen -t rsa -b 2048
ssh-copy-id $IP # $IP就是你需要安装的目标机器，所有机器都要做免密钥
```
这样公钥分发工作完成了，所有的机器直接ssh无需输入密码即可登录

如果还有交互验证，ansible无法连接那就得改ansible参数了：
```
ssh_args = -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -C
```

# 修改配置
Config your own hosts
```
# cd /etc/ansible
# vim hosts
```
配置说明：
```
[k8s-master]
10.1.86.204 name=node01 order=1 role=master lb=MASTER lbname=lbmaster priority=100
10.1.86.205 name=node02 order=2 role=master lb=BACKUP lbname=lbbackup priority=80
10.1.86.206 name=node03 order=3 role=master 

[k8s-node]
10.1.86.207 name=node04 role=node

[k8s-all:children]
k8s-master
k8s-node

[all:vars]
vip=10.1.86.209   # 同网段未被占用IP
k8s_version=1.12.0  # kubernetes版本
ip_interface=eth.*
etcd_crts=["ca-key.pem","ca.pem","client-key.pem","client.pem","member1-key.pem","member1.pem","server-key.pem","server.pem","ca.csr","client.csr","member1.csr","server.csr"]
k8s_crts=["apiserver.crt","apiserver-kubelet-client.crt","ca.crt", "front-proxy-ca.key","front-proxy-client.key","sa.pub", "apiserver.key","apiserver-kubelet-client.key",  "ca.key",  "front-proxy-ca.crt",  "front-proxy-client.crt" , "sa.key"]
```

注意role=master的会装etcd与kubernetes控制节点，role=node即k8s node节点，配置比较简单，除了改IP和版本，其它基本不用动

# 启动安装
```
# ansible-playbook roles/install-all.yaml
```

# uninstall all
```
# ansible-playbook roles/uninstall-all.yaml
```

# 新增节点
删掉hosts文件中已经安装的node节点配置，加上新的

假如之前的配置是：
```
[k8s-master]
10.1.86.204 name=node01 order=1 role=master lb=MASTER lbname=lbmaster priority=100
10.1.86.205 name=node02 order=2 role=master lb=BACKUP lbname=lbbackup priority=80
10.1.86.206 name=node03 order=3 role=master 

[k8s-node]
10.1.86.207 name=node04 role=node
```
现在想安装增加10.1.86.208这个节点，那么删除[k8s-node]项的10.1.86.207 再把208添加上：

```
[k8s-master]
10.1.86.204 name=node01 order=1 role=master lb=MASTER lbname=lbmaster priority=100
10.1.86.205 name=node02 order=2 role=master lb=BACKUP lbname=lbbackup priority=80
10.1.86.206 name=node03 order=3 role=master 

[k8s-node]
10.1.86.208 name=node04 role=node
```
再执行`ansible-playbook roles/install-kubenode.yaml` 即可

同理role下其它yaml文件也可执行, 如单独安装keepalived，单独安装etcd，haproxy等

