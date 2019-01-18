+++
author = "fanux"
date = "2019-01-10T10:54:24+02:00"
draft = false
title = "keepalived in docker"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

# [kubernetes集群三步安装](https://sealyun.com/pro/products/)

# 概述
目前keepalived作为kubernetes集群高可用的重要组件，保障虚拟ip可以在多个主机间漂移，[sealos](https://github.com/fanux/sealos) 也是使用了，只是在方案上与传统的方式有很大区别

首先把keepalived放到容器里了，版本也用了比较新的2.x.x以上

然后使用kubernetes static pod去管理keepalived服务
 
# keepalived放到容器里的好处
* 安装成功率更高，更跨平台, 传统方式如用yum安装或者其它，如果采用那些办法在别的一些发型版系统上sealos就不可用。其次，很多系统的源不一样导致版本不一致造成问题，如果通过源码编译可能一些系统库版本直接导致编译不通过，所以为了提高高可用的安装成功率，放容器里是最好的方式
* 无需额外对keepalived增加监控, 因为是pod，而sealos又已经集成了prometheus，所以不需要再额外添加监控信息
* 统一管理, keepalived异常退出什么的kubelet也会将其拉起，与其它的kubernetes组件就有了一个统一的方式管理

# keepalived在k8s中高可用中的作用
sealos中图中LVS的地方替换成HAproxy了
![](/HA-arch.png)

kubelet kubeproxy在连接master时，如果配置某个具体的master节点的IP，当该master宕机时集群中节点就不能正常工作，所以需要keepalived提供一个虚拟IP在多个节点之间漂移。

然后组件就可以通过vip访问haproxy，haproxy去负载多个master节点


# 实现
keepalived的Dockerfile:
```
FROM centos:7.4.1708
RUN yum install -y  wget  && yum install -y gcc-c++ openssl-devel openssl && yum install -y net-tools 
RUN wget http://www.keepalived.org/software/keepalived-2.0.8.tar.gz && tar zxvf keepalived-2.0.8.tar.gz && cd keepalived-2.0.8 && ./configure && make && make install  
CMD ["keepalived", "-n","--all", "-d", "-D",  "-f", "/etc/keepalived/keepalived.conf", "--log-console"]
```
这里需要用-n参数让keepalived在前台启动，之前在前台启动有一些无法执行检测脚本的问题，和官方沟通后解决, 不然可能需要用一些守护进程去守护，就比较恶心了.

keepalived配置, [模板文件](https://github.com/fanux/sealos/blob/master/roles/keepalived/templates/keepalived.conf.j2)：

模板里的值对应下文host文件里的一些值 
```
global_defs {
   router_id kubernetes
}

vrrp_script Checkhaproxy {
    script "/etc/keepalived/check_haproxy.sh"
    interval 3
    weight -25 
}

vrrp_instance VI_1 {
    state {{ lb }}

    interface {{ ansible_default_ipv4.interface }}
    virtual_router_id  100
    priority {{ priority }}
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass kubernetes
    }

    virtual_ipaddress {
         {{ vip }} 
    }
    track_script {
        Checkhaproxy
    }
}
```
这里的检测脚本检测失败后优先级就-25，这样主原先的优先级是100，从是80，优先级低于从了，vip就会漂移到从上面。

再看一下keepalived[检测脚本](https://github.com/fanux/sealos/blob/master/roles/keepalived/templates/check_haproxy.sh.j2), 如果HAproxy代理的master节点返回值异常了，就漂移：
```
#!/bin/bash

if [ `curl https://{{ ansible_default_ipv4.address }}:6444 --insecure |grep kind |wc -l` -eq 0 ] ; then
   exit 1 # just exit, MASTER will reduce weight(-25), so vip will move on BACKUP node
fi
```
这里网上有很多人简单粗暴的配置检测haproxy进程在不在，其实是有问题的，因为一旦haproxy假死，其实已经不正常了 但是IP漂移不走。

[haproxy配置](https://github.com/fanux/sealos/blob/master/roles/haproxy/templates/haproxy.cfg.j2)了check功能，所以不论哪个master挂了，都能负载到其它master上
```
global
  daemon
  log 127.0.0.1 local0
  log 127.0.0.1 local1 notice
  maxconn 4096
defaults
  log               global
  retries           3
  maxconn           2000
  timeout connect   5s
  timeout client    50s
  timeout server    50s
frontend k8s
  bind *:6444
  mode tcp
  default_backend k8s-backend
backend k8s-backend
  balance roundrobin
  mode tcp
  {% for host in groups['k8s-master'] %}
  server {{hostvars[host].name}} {{ host }}:6443 check port 6443  inter 1500 rise 1 fall 3
  {% endfor %}
```


# 测试过程
我安装了一个集群,具体安装[参考文档](https://github.com/fanux/sealos)，host文件为：
```
[k8s-master]
10.1.86.201 name=node01 order=1 role=master lb=MASTER lbname=lbmaster priority=100
10.1.86.202 name=node02 order=2 role=master lb=BACKUP lbname=lbbackup priority=80
10.1.86.203 name=node03 order=3 role=master

[k8s-node]
10.1.86.205 name=node04 role=node

[k8s-all:children]
k8s-master
k8s-node

[all:vars]
vip=10.1.86.209
k8s_version=1.13.2
ip_interface=eth.*
```
安装完之后查看vip是否正常：
```
[root@dev-86-201 ~]# ip addr|grep 209
    inet 10.1.86.209/32 scope global eth0  # 能看到vip
```
停掉haproxy检查vip是不是漂移到202上：
```
[root@dev-86-201 ~]# mv /etc/kubernetes/manifests/haproxy.yaml .
```
再看vip：
```
[root@dev-86-201 ~]# ip addr|grep 209 # 已经不在
[root@dev-86-201 ~]# 
```
vip正常漂移到202上：
```
[root@dev-86-202 ~]# ip addr|grep 209
    inet 10.1.86.209/32 scope global eth0  # 能看到vip
```

再恢复haproxy:
```
 mv haproxy.yaml /etc/kubernetes/manifests/
```
vip再次漂回201：
```
[root@dev-86-201 ~]# ip addr|grep 209
    inet 10.1.86.209/32 scope global eth0  # 能看到vip
```

如果关闭机器或者拔掉网卡也会与上述结果一致，请各位可自测

# 其它
sealos非常简单轻量，不追求大而全的功能，而提供核心的实现，这样无论是使用还是定制修改，或者把其中某一块哪出来都非常方便。

比如只需要用keepalived+haproxy的场景，   只需要装etcd高可用集群的场景等等

不管你懂不懂ansible，我相信看看看都能很容易看懂sealos的代码，然后根据自己的需要去做一些定制等

QQ群：98488045

# 公众号：
![sealyun](https://sealyun.com/kubernetes-qrcode.jpg)

### 微信群：
![](/wechatgroup1.png)
