+++
title = "使用client-go操作CRD"
date = "2019-09-08T13:50:46+02:00"
tags = ["client-go","CRD"]
categories = ["starting"]
description = ""
banner = "/img/kube-ovn-vpc.png"
+++

使用client-go包访问Kubernetes CRD
Kubernetes API服务器可通过自定义资源定义轻松扩展。但是，用client-go库访问这些资源有点麻烦，官方也没有完整的文档。如kubebuilder operator-framework都能很方便的帮助我们去创建实现一个controller，但是封装的过于好导致我们并不清楚内部是怎么调用client-go的，很多场景我们是需要自己去调用接口操作CRD的而不是在controller中去访问CRD。

本文非常实用，比较全比较完善的相关文档也比较难找到。

举个栗子：

我们在实现虚拟机CRD时，节点上agent需要查询虚拟机CRD，这种情况显然我们不会通过controller进行操作，此时我们就需要知道怎么直接用client-go操作CRD。
<!--more-->

# 创建CRD

```
apiVersion: "apiextensions.k8s.io/v1beta1"
kind: "CustomResourceDefinition"
metadata:
  name: "projects.example.sealyun.com"
spec:
  group: "example.sealyun.com"
  version: "v1alpha1"
  scope: "Namespaced"
  names:
    plural: "projects"
    singular: "project"
    kind: "Project"
  validation:
    openAPIV3Schema:
      required: ["spec"]
      properties:
        spec:
          required: ["replicas"]
          properties:
            replicas:
              type: "integer"
              minimum: 1
```

这个可以使用kubebuilder或者operator-framework生成, 自己写太累

要定义自定义资源定义，您需要考虑API组名称（在本例中example.sealyun.com）。按照惯例，这通常是您控制的域的域名（例如，您组织的域），以防止命名冲突。然后CRD的名称遵循模式<plural-resource-name>.<api-group-name>，因此在这种情况下projects.example.sealyun.com。

通常，您希望根据特定架构验证用户在自定义资源中存储的数据。这就是spec.validation.openAPIV3Schema它的用途：它包含一个描述资源应具有的格式的JSON模式。

使用kubectl创建资源定义, 如果用kubebuilder可以直接make && make deploy：

```
> kubectl apply -f projects-crd.yaml
customresourcedefinition "projects.example.sealyun.com" created
```

可以创建此新资源类型的实例:

```
apiVersion: "example.sealyun.com/v1alpha1"
kind: "Project"
metadata:
  name: "example-project"
  namespace: "default"
spec:
  replicas: 1
```

```
> kubectl apply -f project.yaml
project "example-project" created
```
```
> kubectl get projects
NAME               AGE
example-project    2m
```

# 创建Golang客户端

接下来，我们将使用client-go包来访问这些自定义资源。

> 定义类型

kubebuilder等都会自动为您生成，我这里为了讲清楚所有的东西也加上这块的相关说明

首先定义自定义资源的类型。通过API组版本组织这些类型是一个很好的做法; 例如，api/types/v1alpha1/project.go：

```
package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

type ProjectSpec struct {
    Replicas int `json:"replicas"`
}

type Project struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

    Spec ProjectSpec `json:"spec"`
}

type ProjectList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`

	Items []Project `json:"items"`
}
```

该metav1.ObjectMeta类型包含了典型metadata的属性

> 定义DeepCopy方法

Kubernetes API（在本例中为Project和ProjectList）提供的每种类型都需要实现该k8s.io/apimachinery/pkg/runtime.Object接口。该接口定义了两种方法GetObjectKind()和DeepCopyObject()。第一种方法已经由嵌入式metav1.TypeMeta结构提供; 第二个你必须自己实现。

该DeepCopyObject方法旨在生成对象的深层副本。由于这涉及许多样板代码，因此很多工具通常会自动生成这些方法。为了本文的目的，我们将手动完成。继续向deepcopy.go同一个包添加第二个文件：

```
package v1alpha1

import "k8s.io/apimachinery/pkg/runtime"

// DeepCopyInto copies all properties of this object into another object of the
// same type that is provided as a pointer.
func (in *Project) DeepCopyInto(out *Project) {
    out.TypeMeta = in.TypeMeta
    out.ObjectMeta = in.ObjectMeta
    out.Spec = ProjectSpec{
        Replicas: in.Spec.Replicas,
    }
}

// DeepCopyObject returns a generically typed copy of an object
func (in *Project) DeepCopyObject() runtime.Object {
    out := Project{}
    in.DeepCopyInto(&out)

    return &out
}

// DeepCopyObject returns a generically typed copy of an object
func (in *ProjectList) DeepCopyObject() runtime.Object {
    out := ProjectList{}
    out.TypeMeta = in.TypeMeta
    out.ListMeta = in.ListMeta

    if in.Items != nil {
        out.Items = make([]Project, len(in.Items))
        for i := range in.Items {
            in.Items[i].DeepCopyInto(&out.Items[i])
        }
    }

    return &out
}
```

> 注册类型

接下来，您需要使客户端库知道新类型。允许客户端在与API服务器通信时自动处理新类型。

为此，register.go请在包中添加一个新文件：

```
package v1alpha1

import (
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/apimachinery/pkg/runtime"
    "k8s.io/apimachinery/pkg/runtime/schema"
)

const GroupName = "example.sealyun.com"
const GroupVersion = "v1alpha1"

var SchemeGroupVersion = schema.GroupVersion{Group: GroupName, Version: GroupVersion}

var (
    SchemeBuilder = runtime.NewSchemeBuilder(addKnownTypes)
    AddToScheme   = SchemeBuilder.AddToScheme
)

func addKnownTypes(scheme *runtime.Scheme) error {
    scheme.AddKnownTypes(SchemeGroupVersion,
        &Project{},
        &ProjectList{},
    )

    metav1.AddToGroupVersion(scheme, SchemeGroupVersion)
    return nil
}
```

此代码实际上并没有做任何事情（除了创建新runtime.SchemeBuilder实例）。重要的部分是AddToScheme函数，它是runtime.SchemeBuilder中创建的类型。一旦Kubernetes客户端初始化为注册您的类型，您可以稍后从客户端代码的任何部分调用此函数。

> 构建HTTP客户端

在定义类型并添加方法以在全局方案构建器中注册它们之后，您现在可以创建能够加载自定义资源的HTTP客户端。

为此，将以下代码添加到包的main.go文件中：

```
package main

import (
    "flag"
    "log"
    "time"

    "k8s.io/apimachinery/pkg/runtime/schema"
    "k8s.io/apimachinery/pkg/runtime/serializer"

    "github.com/martin-helmich/kubernetes-crd-example/api/types/v1alpha1"
    "k8s.io/client-go/kubernetes/scheme"
    "k8s.io/client-go/rest"
    "k8s.io/client-go/tools/clientcmd"
)

var kubeconfig string

func init() {
    flag.StringVar(&kubeconfig, "kubeconfig", "", "path to Kubernetes config file")
    flag.Parse()
}

func main() {
    var config *rest.Config
    var err error

    if kubeconfig == "" {
        log.Printf("using in-cluster configuration")
        config, err = rest.InClusterConfig()
    } else {
        log.Printf("using configuration from '%s'", kubeconfig)
        config, err = clientcmd.BuildConfigFromFlags("", kubeconfig)
    }

    if err != nil {
        panic(err)
    }

    v1alpha1.AddToScheme(scheme.Scheme)

    crdConfig := *config
    crdConfig.ContentConfig.GroupVersion = &schema.GroupVersion{Group: v1alpha1.GroupName, Version: v1alpha1.GroupVersion}
    crdConfig.APIPath = "/apis"
    crdConfig.NegotiatedSerializer = serializer.DirectCodecFactory{CodecFactory: scheme.Codecs}
    crdConfig.UserAgent = rest.DefaultKubernetesUserAgent()

    exampleRestClient, err := rest.UnversionedRESTClientFor(&crdConfig)
    if err != nil {
        panic(err)
    }
}
```
您现在可以使用第exampleRestClient中创建的内容来查询example.sealyun.com/v1alpha1API组中的所有自定义资源。示例可能如下所示：

```
result := v1alpha1.ProjectList{}
err := exampleRestClient.
    Get().
    Resource("projects").
    Do().
    Into(&result)
```

为了以更加类型安全的方式使用您的API，通常最好将这些操作包装在您自己的客户端集中。为此，创建一个新的子包clientset/v1alpha1。首先，实现一个定义API组类型的接口，并将配置设置从您的main方法移动到该clientset的构造函数中（NewForConfig在下面的示例中）：

```
package v1alpha1

import (
    "github.com/martin-helmich/kubernetes-crd-example/api/types/v1alpha1"
    "k8s.io/apimachinery/pkg/runtime/schema"
    "k8s.io/apimachinery/pkg/runtime/serializer"
    "k8s.io/client-go/kubernetes/scheme"
    "k8s.io/client-go/rest"
)

type ExampleV1Alpha1Interface interface {
    Projects(namespace string) ProjectInterface 
}

type ExampleV1Alpha1Client struct {
    restClient rest.Interface
}

func NewForConfig(c *rest.Config) (*ExampleV1Alpha1Client, error) {
    config := *c
    config.ContentConfig.GroupVersion = &schema.GroupVersion{Group: v1alpha1.GroupName, Version: v1alpha1.GroupVersion}
    config.APIPath = "/apis"
    config.NegotiatedSerializer = serializer.DirectCodecFactory{CodecFactory: scheme.Codecs}
    config.UserAgent = rest.DefaultKubernetesUserAgent()

    client, err := rest.RESTClientFor(&config)
    if err != nil {
        return nil, err
    }

    return &ExampleV1Alpha1Client{restClient: client}, nil
}

func (c *ExampleV1Alpha1Client) Projects(namespace string) ProjectInterface {
    return &projectClient{
        restClient: c.restClient,
        ns: namespace,
    }
}
```
以上是对client的封装


接下来，您需要实现一个特定的Project客户端集来访问自定义资源（请注意，上面的示例已经使用了我们仍需要提供的ProjectInterface和projectClient类型）。projects.go在同一个包中创建第二个文件：

```
package v1alpha1

import (
    "github.com/martin-helmich/kubernetes-crd-example/api/types/v1alpha1"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/apimachinery/pkg/watch"
    "k8s.io/client-go/kubernetes/scheme"
    "k8s.io/client-go/rest"
)

type ProjectInterface interface {
    List(opts metav1.ListOptions) (*v1alpha1.ProjectList, error)
    Get(name string, options metav1.GetOptions) (*v1alpha1.Project, error)
    Create(*v1alpha1.Project) (*v1alpha1.Project, error)
    Watch(opts metav1.ListOptions) (watch.Interface, error)
    // ...
}

type projectClient struct {
    restClient rest.Interface
    ns         string
}

func (c *projectClient) List(opts metav1.ListOptions) (*v1alpha1.ProjectList, error) {
    result := v1alpha1.ProjectList{}
    err := c.restClient.
        Get().
        Namespace(c.ns).
        Resource("projects").
        VersionedParams(&opts, scheme.ParameterCodec).
        Do().
        Into(&result)

    return &result, err
}

func (c *projectClient) Get(name string, opts metav1.GetOptions) (*v1alpha1.Project, error) {
    result := v1alpha1.Project{}
    err := c.restClient.
        Get().
        Namespace(c.ns).
        Resource("projects").
        Name(name).
        VersionedParams(&opts, scheme.ParameterCodec).
        Do().
        Into(&result)

    return &result, err
}

func (c *projectClient) Create(project *v1alpha1.Project) (*v1alpha1.Project, error) {
    result := v1alpha1.Project{}
    err := c.restClient.
        Post().
        Namespace(c.ns).
        Resource("projects").
        Body(project).
        Do().
        Into(&result)

    return &result, err
}

func (c *projectClient) Watch(opts metav1.ListOptions) (watch.Interface, error) {
    opts.Watch = true
    return c.restClient.
        Get().
        Namespace(c.ns).
        Resource("projects").
        VersionedParams(&opts, scheme.ParameterCodec).
        Watch()
}
```

上面还缺少一些Delete Update方法，照抄就行，或者参考[pod的实现](https://github.com/kubernetes/client-go/blob/master/kubernetes/typed/core/v1/pod.go)

再去使用就变的非常简单了：
```
import clientV1alpha1 "github.com/martin-helmich/kubernetes-crd-example/clientset/v1alpha1"
// ...

func main() {
    // ...

    clientSet, err := clientV1alpha1.NewForConfig(config)
    if err != nil {
        panic(err)
    }

    projects, err := clientSet.Projects("default").List(metav1.ListOptions{})
    if err != nil {
        panic(err)
    }

    fmt.Printf("projects found: %+v\n", projects)
}
```

> 创建informer

构建Kubernetes operator时，通常希望能够对新创建或更新的事件进行监听。理论上，可以定期调用该List()方法并检查是否添加了新资源。

大多数情况通过使用初始List()初始加载资源的所有相关实例，然后使用Watch()订阅相关事件进行处理。然后，使用从informer接收的初始对象列表和更新来构建本地缓存，该缓存允许快速访问任何自定义资源，而无需每次都访问API服务器。

这种模式非常普遍，以至于client-go库为此提供了一个cache包：来自包的Informerk8s.io/client-go/tools/cache。您可以为自定义资源构建新的Informer，如下所示：

```
package main

import (
    "time"

    "github.com/martin-helmich/kubernetes-crd-example/api/types/v1alpha1"
    client_v1alpha1 "github.com/martin-helmich/kubernetes-crd-example/clientset/v1alpha1"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/apimachinery/pkg/runtime"
    "k8s.io/apimachinery/pkg/util/wait"
    "k8s.io/apimachinery/pkg/watch"
    "k8s.io/client-go/tools/cache"
)

func WatchResources(clientSet client_v1alpha1.ExampleV1Alpha1Interface) cache.Store {
    projectStore, projectController := cache.NewInformer(
        &cache.ListWatch{
            ListFunc: func(lo metav1.ListOptions) (result runtime.Object, err error) {
                return clientSet.Projects("some-namespace").List(lo)
            },
            WatchFunc: func(lo metav1.ListOptions) (watch.Interface, error) {
                return clientSet.Projects("some-namespace").Watch(lo)
            },
        },
        &v1alpha1.Project{},
        1*time.Minute,
        cache.ResourceEventHandlerFuncs{},
    )

    go projectController.Run(wait.NeverStop)
    return projectStore
}
```

该NewInformer方法返回两个对象：第二个返回值，控制器控制List()和Watch()调用并填充第一个返回值，Store缓存监听到的一些信息。
您现在可以使用store轻松访问CRD，列出所有CRD或通过名称访问它们。store函数返回interface{}类型，因此您必须将它们强制转换回CRD类型：

```
store := WatchResource(clientSet)
project := store.GetByKey("some-namespace/some-project").(*v1alpha1.Project)
```
如此很多情况下就不需要再去调用apiserver了，给apiserver减轻压力.

# 总结

虽然现在很多工具给我们写CRD controller带来了极大的便捷，但是对于client-go这些基本的使用还是非常必要的，而官方client-go的开发文档和事例真的是少之又少，基本仅包含非常基本的操作。

还有一个dynamic client的方式也可以用来访问自定义CRD，但是文中的方式会更优雅更清晰更适合工程化。
