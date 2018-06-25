+++
author = "fanux"
date = "2018-06-21T10:54:24+02:00"
draft = false
title = "kubernetes开发指南"
#slug = "dotscale-2014-as-a-sketch" #链接地址
tags = ["event","dotScale","sketchnote"]
image = "images/2014/Jul/titledotscale.png"
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

> 广告 | [kubernetes离线安装包，仅需三步](http://sealyun.com/pro/products/)

## 初始化客户端
这里给了两种初始化kubernetes客户端的方式，一种根据kubeconfig文件的路径，官方有，比较简单

另一种就是根据kubeconfig内容的字符串去初始化一个客户端，这种方式应用场景是比如我们把很多的kubeconfig文件存在了数据库中（多租户时）
```
package client

import (
	"fmt"

	"github.com/Sirupsen/logrus"

	"git.xfyun.cn/container/genesis/modules/authentication"
	"git.xfyun.cn/container/genesis/utils"

	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

//KubeClientFromKubeconfigPath is
func KubeClientFromKubeconfigPath(path string) (clientSet *kubernetes.Clientset, err error) {

	cfg, err := clientcmd.BuildConfigFromFlags("", path)
	if err != nil {
		return nil, fmt.Errorf("new kube config error: %s", err)
	}

	if clientSet, err = kubernetes.NewForConfig(cfg); err != nil {
		return nil, fmt.Errorf("new kube config error: %s", err)
	}
	return clientSet, nil
}

//KubeClientFromKubeconfigStringBody is
func KubeClientFromKubeconfigStringBody(body string) (*kubernetes.Clientset, error) {
	b, err := utils.Base64Decode(body)
	if err != nil {
		return nil, err
	}

	logrus.Debugf("Fetch kubeconfig string: %s", string(b))
	clientConfig, err := clientcmd.NewClientConfigFromBytes(b)
	if err != nil {
		return nil, fmt.Errorf("new client config from body error: %s", err)
	}
	cfg, err := clientConfig.ClientConfig()
	if err != nil {
		return nil, fmt.Errorf("new kube config from body error: %s", err)
	}

	clientSet, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		return nil, fmt.Errorf("new kube config from body error: %s", err)
	}
	return clientSet, nil
}
```

## yaml文件解析技巧
yaml文件中的---进行切分时很多一些yaml库没法解析，需要自己进行切分，当然k8s源码里已经有了对应实现，我们拿来用即可

编写一个回调函数进行处理，拿到的就是切分好的json了
```
package utils

import (
	"bytes"
	"fmt"
	"io"

	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/util/yaml"
)

var bs = []byte(`
kind: Namespace
metadata:
   name: test
---

kind: bbb
name: aaa`)

/* Out put
```
{"kind":"Namespace","metadata":{"name":"test"}}
{"kind":"bbb","name":"aaa"}
```
*/
func example() {
	reader := bytes.NewReader(bs)
	ext := runtime.RawExtension{}
	d := yaml.NewYAMLOrJSONDecoder(reader, 4096)
	for {
		if err := d.Decode(&ext); err != nil {
			if err == io.EOF {
				return
			}
			return
		}
		fmt.Println(string(ext.Raw))
	}
}

//YamlCallback is
type YamlCallback func([]byte) error

//YamlHandler is
func YamlHandler(rawBytes []byte, fn YamlCallback) (err error) {
	reader := bytes.NewReader(rawBytes)
	ext := runtime.RawExtension{}
	d := yaml.NewYAMLOrJSONDecoder(reader, 4096)
	for {
		if err = d.Decode(&ext); err != nil {
			if err == io.EOF {
				return nil
			}
			return fmt.Errorf("decode yaml json failed: %v", err)
		}
		//Raw is already to json
		if err = fn(ext.Raw); err != nil {
			return fmt.Errorf("handler yaml callback fn failed: %v", err)
		}
	}
}

```

## 监听service事件
出自kube-proxy源码
```
// informers "k8s.io/kubernetes/pkg/client/informers/informers_generated/internalversion"

// 先根据client获取个informer工厂
informerFactory := informers.NewSharedInformerFactory(s.Client, s.ConfigSyncPeriod)

// 生产个service的informer，同样可以监听别的对象
serviceInformer=informerFactory.Core().InternalVersion().Services()

/*
	AddFunc    func(obj interface{})
	UpdateFunc func(oldObj, newObj interface{})
	DeleteFunc func(obj interface{})
*/
serviceInformer.Informer().AddEventHandlerWithResyncPeriod(
	cache.ResourceEventHandlerFuncs{
		AddFunc:    result.handleAddService, // 你自己的回调函数
		UpdateFunc: result.handleUpdateService,
		DeleteFunc: result.handleDeleteService,
	},
	resyncPeriod,
)
informerFactory.Start(wait.NeverStop) // 开始监听
```
