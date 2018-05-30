+++
author = "fanux"
date = "2018-05-29T10:54:24+02:00"
draft = false
title = "kubernetes启用ipvs"
#slug = "dotscale-2014-as-a-sketch"
tags = ["event","dotScale","sketchnote"]
image = "images/2014/Jul/titledotscale.png"
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

# kubernetes启用ipvs
确保内核开启了ipvs模块
```
[root@k8s ~]# lsmod|grep ip_vs
ip_vs_sh               12688  0
ip_vs_wrr              12697  0
ip_vs_rr               12600  16
ip_vs                 141092  23 ip_vs_rr,ip_vs_sh,xt_ipvs,ip_vs_wrr
nf_conntrack          133387  9 ip_vs,nf_nat,nf_nat_ipv4,nf_nat_ipv6,xt_conntrack,nf_nat_masquerade_ipv4,nf_conntrack_netlink,nf_conntrack_ipv4,nf_conntrack_ipv6
libcrc32c              12644  3 ip_vs,nf_nat,nf_conntrack
```
没开启加载方式:
```
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack_ipv4
```

1.10以上版本,使用kubeadm安装的，直接修改kube-proxy configmap即可
```
kubectl edit configmap kube-proxy -n kube-system
```
```
    ipvs:
      minSyncPeriod: 0s
      scheduler: ""
      syncPeriod: 30s
    kind: KubeProxyConfiguration
    metricsBindAddress: 127.0.0.1:10249
    mode: "ipvs"                          # 加上这个
    nodePortAddresses: null
```

看到pod如下信息表明成功
```
[root@k8s ~]# kubectl logs kube-proxy-72lg9 -n kube-system
I0530 03:38:11.455609       1 feature_gate.go:226] feature gates: &{{} map[]}
I0530 03:38:11.490470       1 server_others.go:183] Using ipvs Proxier.
W0530 03:38:11.503868       1 proxier.go:304] IPVS scheduler not specified, use rr by default
I0530 03:38:11.504109       1 server_others.go:209] Tearing down inactive rules.
I0530 03:38:11.552587       1 server.go:444] Version: v1.10.3
```

安装ipvsadm工具
```
yum install -y ipvsadm
```

检查service ipvs配置：
```
[root@k8s ~]# ipvsadm -ln
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
TCP  172.31.244.239:32000 rr
  -> 192.168.77.9:8443            Masq    1      0          0
TCP  172.31.244.239:32001 rr
  -> 192.168.77.8:3000            Masq    1      0          0
TCP  10.96.0.1:443 rr persistent 10800
  -> 172.31.244.239:6443          Masq    1      0          0
TCP  10.96.0.10:53 rr
  -> 192.168.77.7:53              Masq    1      0          0
  -> 192.168.77.10:53             Masq    1      0          0
TCP  10.96.82.0:80 rr
  -> 192.168.77.8:3000            Masq    1      0          0
TCP  10.96.152.25:8086 rr
  -> 192.168.77.12:8086           Masq    1      0          0
TCP  10.96.232.136:6666 rr
```
可以看到我们的dashboard dns什么的都已经配置了，可以验证一下：
```
[root@k8s ~]# wget https://172.31.244.239:32000 --no-check-certificate
--2018-05-30 16:17:15--  https://172.31.244.239:32000/
正在连接 172.31.244.239:32000... 已连接。
警告: 无法验证 172.31.244.239 的由 “/CN=.” 颁发的证书:
  出现了自己签名的证书。
    警告: 证书通用名 “.” 与所要求的主机名 “172.31.244.239” 不符。
已发出 HTTP 请求，正在等待回应... 200 OK
长度：990 [text/html]
正在保存至: “index.html”

100%[=======================================================================================================================================================>] 990         --.-K/s 用时 0s

2018-05-30 16:17:15 (16.3 MB/s) - 已保存 “index.html” [990/990])
```
是通的，完全ok

这里十分推荐大家使用ipvs模式，iptables出了问题不好调试，而且规则一多性能显著下降，我们甚至出现规则丢失的情况，ipvs稳定很多。
