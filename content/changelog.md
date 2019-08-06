# 离线包Changelog

> 1.14.5 与1.15.2版本

社区：

* 无重大更新

sealyun:

更新kubelet开机启动依赖, 开机自动启动ipvs，自动拉起其它所有服务：
```
[root@iZj6cgg9qmj6d5vq9wthk3Z ~]# cat /etc/systemd/system/kubelet.service
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=http://kubernetes.io/docs/

[Service]
ExecStart=/usr/bin/kubelet
ExecStartPre=/usr/bin/kubelet-pre-start.sh
```

```
[root@iZj6cgg9qmj6d5vq9wthk3Z ~]# cat /usr/bin/kubelet-pre-start.sh
#!/bin/bash
# Open ipvs
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack_ipv4

cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system
sysctl -w net.ipv4.ip_forward=1
# systemctl stop firewalld && systemctl disable firewalld
swapoff -a
setenforce 0
exit 0
```

> 1.14.4版本

社区：

* 如当kubelet的pods目录（默认为“/ var / lib / kubelet / pods”）符号链接到另一个磁盘设备的目录时，修复kubelet无法删除孤立的pod目录
* 修复可能的fd泄漏和关闭dirs
* 修复了当pod的重启策略为Never时，kubelet不会重试pod sandbox创建的错误
* 将ip-masq-agentv2.3.0以修复漏洞
* 修复由于flexvol插件中的损坏的mnt点导致的pod问题
* 修复IPVS正常终止中的字符串比较错误，其中不删除UDP真实服务器。
* 在升级API服务器时解决了workload控制器的虚假部署，原因是由于pod中的alpha procMount字段的错误默认
* 修复了Windows上Kubelet中的内存泄漏问题，这是因为在获取容器指标时没有关闭容器

sealyun:

* 修复ubuntu下kubelet启动依赖找不到sh命令问题，使用/bin/bash绝对路径 [新增]
* 支持99年证书
* 支持HA

> 1.15.1版本

社区：

* kubeadm：实现支持并发添加/删除etcd成员
* 解决了服务支持的聚合API的问题
* 将csi插件中的超时值从15秒更改为2 分钟，修复了超时问题
* kubeadm：修复“--cri-socket”标志不起作用的错误
* 当kubelet的pods目录（默认为“/var/lib/kubelet/pods”）符号链接到另一个磁盘设备的目录时，修复kubelet无法删除孤立的pod目录
* 在doSafeMakeDir修复可能的fd泄漏和关闭dirs
* CRD处理程序现在可以正确地重新创建过时的CR存储以反映CRD更新。
* 修复了当pod的重启策略为Never时，kubelet不会重试pod sandbox 创建的错误
* 修复kubeadm重置期间从群集中删除etcd成员 

sealyun:

* 修复单master lvscare起不来问题，增加判断，如果是单master不去创建lvscare代理
* 修复kubelet启动依赖可能在一些系统下导致kubelet无法启动问题
