+++
author = "fanux"
date = "2018-11-07T10:54:24+02:00"
draft = false
title = "修改kubeadm证书过期时间"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

> [kubernetes集群三步安装](https://sealyun.com/pro/products/)

# 修改kubeadm证书过期时间
本文通过修改kubeadm源码让kubeadm默认的一年证书过期时间修改为99年

我已经编译好了一个放在了[github](https://github.com/fanux/sealos/releases/tag/kubeadm1.12.2)上，有需要的可以直接下

使用方法:
```
[root@dev-86-202 ~]# chmod +x kubeadm && cp kubeadm /usr/bin
[root@dev-86-202 ~]# rm /etc/kubernetes/pki/ -rf
[root@dev-86-202 ~]# kubeadm alpha phase certs all --config  kube/conf/kubeadm.yaml
```

更新kubeconfig

```
[root@dev-86-202 ~]# rm -rf /etc/kubernetes/*conf
[root@dev-86-202 ~]# kubeadm alpha phase kubeconfig all --config ~/kube/conf/kubeadm.yaml
[root@dev-86-202 ~]# cp /etc/kubernetes/admin.conf ~/.kube/config
```

验证：

```
$ cd /etc/kubernetes/pki
$ openssl x509 -in apiserver-etcd-client.crt -text -noout
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number: 4701787282062078235 (0x41401a9f34c2711b)
    Signature Algorithm: sha256WithRSAEncryption
        Issuer: CN=etcd-ca
        Validity
            Not Before: Nov 22 11:58:50 2018 GMT
            Not After : Oct 29 11:58:51 2117 GMT   # 时间已经变成99年了
```

其它证书验证同理

## 代码编译
编译环境镜像我已经放到dockerhub上了：fanux/kubernetes-build:v1.0.0

首先clone k8s 代码：

```
git clone https://github.com/kubernetes/kubernetes
```

挂载到镜像中编译

```
docker run --rm -v yourcodedir:/go/src/k8s.io/kubernetes -it fanux/kubernetes-build:v1.0.0 bash
# cd /go/src/k8s.io/kubernetes
# make all WHAT=cmd/kubeadm GOFLAGS=-v
```

编译完产物在 _output/local/bin/linux/amd64/kubeadm 目录下

## 修改代码

证书时间代码其实在client-go里面，文件是：
```
vendor/k8s.io/client-go/util/cert/cert.go
```

然后看到这个NotAfter的都给改了即可：

```
NotAfter:  validFrom.Add(duration365d * longYear)
```

我这里longYear ＝ 99

然后编译完工

最后在代码里贴上小广告：

```
func main() {
	if err := app.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("*************************************************")
	fmt.Println("****         www.sealyun.com                  ***")
	fmt.Println("****         kubernetes install in 3 steps    ***")
	fmt.Println("****         provide by fanux                 ***")
	fmt.Println("*************************************************")
	os.Exit(0)
}
```
完美


# 公众号：
![sealyun](https://sealyun.com/kubernetes-qrcode.jpg)
