+++
author = "fanux"
date = "2019-03-28T10:54:24+02:00"
draft = false
title = "tektoncd pipeline教程 - kubernetes原生pipeline"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

> [kubernetes集群三步安装](https://sealyun.com/pro/products/)

# 概览
Tekton Pipeline,是一个k8s native的pipeline, 任务跑在pod中，通过自定义CRD去管理任务与工作流等等，我看完tekton之后感觉是功能很强大，但是有点过度设计了，没有drone的简约大方灵活之感

# Task
Tekton Pipelines的主要目标是单独运行您的任务或作为管道的一部分运行。每个任务都在Kubernetes集群上作为Pod运行，每个步骤都作为自己的容器。这点深得drone思想精髓，其实drone也有计划将kubernetes作为任务执行引擎，只是没有下文了。

A Task定义了需要执行的工作，例如以下是一个简单的任务：

```
apiVersion: tekton.dev/v1alpha1
kind: Task
metadata:
  name: echo-hello-world
spec:
  steps:
    - name: echo
      image: ubuntu
      command:
        - echo
      args:
        - "hello world"
```

这steps是一系列由任务顺序执行的命令。这个steps内的配置几乎与drone如出一辙

Task定义好并没有被执行，创建TaskRun时才会执行。这是合理的，相当于是一个触发

```
apiVersion: tekton.dev/v1alpha1
kind: TaskRun
metadata:
  name: echo-hello-world-task-run
spec:
  taskRef:
    name: echo-hello-world
  trigger:
    type: manual
```
kubectl apply -f < name-of-file.yaml >

查看TaskRun
kubectl get taskruns / echo-hello-world-task-run -o yaml

```
apiVersion: tekton.dev/v1alpha1
kind: TaskRun
metadata:
  creationTimestamp: 2018-12-11T15:49:13Z
  generation: 1
  name: echo-hello-world-task-run
  namespace: default
  resourceVersion: "6706789"
  selfLink: /apis/tekton.dev/v1alpha1/namespaces/default/taskruns/echo-hello-world-task-run
  uid: 4e96e9c6-fd5c-11e8-9129-42010a8a0fdc
spec:
  generation: 1
  inputs: {}
  outputs: {}
  taskRef:
    name: echo-hello-world
  taskSpec: null
  trigger:
    type: manual
status:
  conditions:
    - lastTransitionTime: 2018-12-11T15:50:09Z
      status: "True"
      type: Succeeded
  podName: echo-hello-world-task-run-pod-85ca51
  startTime: 2018-12-11T15:49:39Z
  steps:
    - terminated:
        containerID: docker://fcfe4a004...6729d6d2ad53faff41
        exitCode: 0
        finishedAt: 2018-12-11T15:50:01Z
        reason: Completed
        startedAt: 2018-12-11T15:50:01Z
    - terminated:
        containerID: docker://fe86fc5f7...eb429697b44ce4a5b
        exitCode: 0
        finishedAt: 2018-12-11T15:50:02Z
        reason: Completed
        startedAt: 2018-12-11T15:50:02Z
```

状态Succeeded = True显示任务已成功运行。

# 任务输入和输出
在更常见的场景中，任务需要多个步骤来处理输入和输出资源。例如，Task可以从GitHub存储库获取源代码并从中构建Docker镜像。

PipelinesResources用于定义任务的输入(如代码)与输出(如Docker镜像)。有一些系统定义的资源类型可供使用，以下是通常需要的两个资源示例。

该git资源可以是你要编译的代码：

```
apiVersion: tekton.dev/v1alpha1
kind: PipelineResource
metadata:
  name: skaffold-git
spec:
  type: git
  params:
    - name: revision
      value: master
    - name: url
      value: https://github.com/GoogleContainerTools/skaffold
```

该image资源代表要被任务编译成的镜像：

```
apiVersion: tekton.dev/v1alpha1
kind: PipelineResource
metadata:
  name: skaffold-image-leeroy-web
spec:
  type: image
  params:
    - name: url
      value: gcr.io/<use your project>/leeroy-web
```

以下是Task输入和输出。输入资源是GitHub存储库，输出是从该源生成的图像。任务命令的参数支持模板化，因此任务的定义是常量，参数的值可以在运行时更改。
```
apiVersion: tekton.dev/v1alpha1
kind: Task
metadata:
  name: build-docker-image-from-git-source
spec:
  inputs:
    resources:
      - name: docker-source
        type: git
    params:
      - name: pathToDockerFile       # 这些参数都是可以自定义的
        description: The path to the dockerfile to build
        default: /workspace/docker-source/Dockerfile
      - name: pathToContext
        description:
          The build context used by Kaniko
          (https://github.com/GoogleContainerTools/kaniko#kaniko-build-contexts)
        default: /workspace/docker-source
  outputs:
    resources:
      - name: builtImage
        type: image
  steps:
    - name: build-and-push
      image: gcr.io/kaniko-project/executor  # 特定功能的镜像，可以用来docker build
      command:
        - /kaniko/executor
      args:
        - --dockerfile=${inputs.params.pathToDockerFile}   # 这时原pathToDockerFile就是上面定义的参数
        - --destination=${outputs.resources.builtImage.url}
        - --context=${inputs.params.pathToContext}
```

TaskRun将输入和输出绑定到已定义的PipelineResources值，除了执行任务步骤外，还将值设置为用于模板化的参数。

```
apiVersion: tekton.dev/v1alpha1
kind: TaskRun
metadata:
  name: build-docker-image-from-git-source-task-run
spec:
  taskRef:
    name: build-docker-image-from-git-source
  trigger:
    type: manual
  inputs:
    resources:
      - name: docker-source
        resourceRef:
          name: skaffold-git
    params:                       # 执行时把参数传给Task，这样就不需要重复定义task，只需要增加input output 和taskrun 就可以跑一个别的工程, 从解耦这个角度到说比drone更好，任务流程可以复用
      - name: pathToDockerFile
        value: Dockerfile
      - name: pathToContext
        value: /workspace/docker-source/examples/microservices/leeroy-web #configure: may change according to your source
  outputs:
    resources:
      - name: builtImage
        resourceRef:
          name: skaffold-image-leeroy-web  # 这也是上面指定的资源
```

PS: inputs outputs应当不限制死必须叫这两个名字，只要是能支持参数就好。比如定义一个叫build的资源去指定docker build的镜像：
```
apiVersion: tekton.dev/v1alpha1
kind: PipelineResource
metadata:
  name: skaffold-image-leeroy-web
spec:
  type: image
  params:
    - name: url
      value: docker-in-docker:latest
```

Task 里：
```
apiVersion: tekton.dev/v1alpha1
kind: Task
metadata:
  name: build-docker-image-from-git-source
spec:
  build:
     resources:
     - name: build
       type: image
  params:
  - name: build-image
    default: docker-in-docker:latest
  steps:
      - name: build-and-push
      image: ${build.params.build-image}     
```
我是觉得需要能进行这样的扩展了, 仅是inputs outputs就狭义了


获取pipeline全部信息
kubectl get build-pipeline
```
NAME                                                   AGE
taskruns/build-docker-image-from-git-source-task-run   30s

NAME                                          AGE
pipelineresources/skaffold-git                6m
pipelineresources/skaffold-image-leeroy-web   7m

NAME                                       AGE
tasks/build-docker-image-from-git-source   7m
```

要查看TaskRun的输出，请使用以下命令：

kubectl get taskruns / build-docker-image-from-git-source-task-run -o yaml
```
apiVersion: tekton.dev/v1alpha1
kind: TaskRun
metadata:
  creationTimestamp: 2018-12-11T18:14:29Z
  generation: 1
  name: build-docker-image-from-git-source-task-run
  namespace: default
  resourceVersion: "6733537"
  selfLink: /apis/tekton.dev/v1alpha1/namespaces/default/taskruns/build-docker-image-from-git-source-task-run
  uid: 99d297fd-fd70-11e8-9129-42010a8a0fdc
spec:
  generation: 1
  inputs:
    params:
      - name: pathToDockerFile
        value: Dockerfile
      - name: pathToContext
        value: /workspace/git-source/examples/microservices/leeroy-web #configure: may change depending on your source
    resources:
      - name: git-source
        paths: null
        resourceRef:
          name: skaffold-git
  outputs:
    resources:
      - name: builtImage
        paths: null
        resourceRef:
          name: skaffold-image-leeroy-web
  taskRef:
    name: build-docker-image-from-git-source
  taskSpec: null
  trigger:
    type: manual
status:
  conditions:
    - lastTransitionTime: 2018-12-11T18:15:09Z
      status: "True"
      type: Succeeded
  podName: build-docker-image-from-git-source-task-run-pod-24d414
  startTime: 2018-12-11T18:14:29Z
  steps:
    - terminated:
        containerID: docker://138ce30c722eed....c830c9d9005a0542
        exitCode: 0
        finishedAt: 2018-12-11T18:14:47Z
        reason: Completed
        startedAt: 2018-12-11T18:14:47Z
    - terminated:
        containerID: docker://4a75136c029fb1....4c94b348d4f67744
        exitCode: 0
        finishedAt: 2018-12-11T18:14:48Z
        reason: Completed
        startedAt: 2018-12-11T18:14:48Z
```
类型的状态Succeeded = True显示Task已成功运行，您还可以验证Docker镜像是否生成。

# Pipeline
Pipeline定义要按顺序执行的任务列表，同时还通过使用该from字段指示是否应将任何输出用作后续任务的输入，并指示执行的顺序（使用runAfter和from字段）。您在任务中使用的相同模板也可以在管道中使用。

例如：
```
apiVersion: tekton.dev/v1alpha1
kind: Pipeline
metadata:
  name: tutorial-pipeline
spec:
  resources:
    - name: source-repo
      type: git
    - name: web-image
      type: image
  tasks:
    - name: build-skaffold-web # 编译与打镜像任务，上面已经介绍过
      taskRef:
        name: build-docker-image-from-git-source
      params:
        - name: pathToDockerFile
          value: Dockerfile
        - name: pathToContext
          value: /workspace/examples/microservices/leeroy-web #configure: may change according to your source
      resources:
        inputs:
          - name: workspace
            resource: source-repo
        outputs:
          - name: image
            resource: web-image
    - name: deploy-web          # 部署
      taskRef:
        name: deploy-using-kubectl # 这里引入了一个通过k8s部署的Task，我们在下文看它是什么
      resources:
        inputs:                    # 定义输入，这里的输入其实是上个任务的输出
          - name: workspace
            resource: source-repo
          - name: image            # 比如这个镜像，就是上个任务产生的
            resource: web-image
            from:                  # from就如同管道一样，把上个任务的输出作为这个任务的输入
              - build-skaffold-web
      params:                      # 留意这些参数都是传给Task模板的,覆盖inputs里的参数
        - name: path
          value: /workspace/examples/microservices/leeroy-web/kubernetes/deployment.yaml #configure: may change according to your source
        - name: yqArg
          value: "-d1"
        - name: yamlPathToImage
          value: "spec.template.spec.containers[0].image"
```

以上Pipeline是引用一个Task被叫的deploy-using-kubectl：
```
apiVersion: tekton.dev/v1alpha1
kind: Task
metadata:
  name: deploy-using-kubectl
spec:
  inputs:
    resources:
      - name: workspace
        type: git
      - name: image
        type: image
    params:
      - name: path
        description: Path to the manifest to apply
      - name: yqArg
        description:
          Okay this is a hack, but I didn't feel right hard-coding `-d1` down
          below
      - name: yamlPathToImage
        description:
          The path to the image to replace in the yaml manifest (arg to yq)
  steps:
    - name: replace-image  # 第一步替换镜像
      image: mikefarah/yq  # 特定功能的镜像，和drone同理，这里主要就是个模板渲染
      command: ["yq"]
      args:
        - "w"
        - "-i"
        - "${inputs.params.yqArg}"
        - "${inputs.params.path}"
        - "${inputs.params.yamlPathToImage}"
        - "${inputs.resources.image.url}"
    - name: run-kubectl                 # 第二步执行kubectl
      image: lachlanevenson/k8s-kubectl
      command: ["kubectl"]
      args:
        - "apply"
        - "-f"
        - "${inputs.params.path}"   # 这就是yaml文件的位置
```

要运行Pipeline，请创建PipelineRun如下：
```
apiVersion: tekton.dev/v1alpha1
kind: PipelineRun
metadata:
  name: tutorial-pipeline-run-1
spec:
  pipelineRef:
    name: tutorial-pipeline
  trigger:
    type: manual
  resources:
    - name: source-repo
      resourceRef:
        name: skaffold-git
    - name: web-image
      resourceRef:
        name: skaffold-image-leeroy-web
```
执行与查看pipeline:

kubectl apply -f < name-of-file.yaml >
kubectl获取pipelineruns / tutorial-pipeline-run-1 -o yaml

# 总结
初学者会觉得有点绕，但是这种设计也是为了解耦合，我个人觉得优劣如下：

优势：
* 可以把k8s集群作为任务执行引擎，这样可以更好的利用资源，比如把线上夜间闲置资源用来跑任务，构建镜像 离线分析 甚至机器学习。
* 解耦做的比较好，任务模板可以拿来复用，而不需要大家都去重复定义
* 输入输出理念，一个任务的输入作为另个任务的输出不错

劣势：
* 有点过度设计，一些简单的场景可能觉得配置起来有点绕了
* 输入输出依赖分布式系统，对比drone一个pipeline中的容器是共享了一个数据卷的，这样上个任务产生的文件很方便的给下个任务用，而基于集群的任务就可能得依赖git docker镜像仓库等做输入输出，有点麻烦，好的解决办法是利用k8s分布试存储给pipeline设置一个共享卷，方便任务间传输数据

总体来说路子是对的而且还是有很多场景可以用的。

探讨可加QQ群：98488045

# 公众号：
![sealyun](https://sealyun.com/kubernetes-qrcode.jpg)

### 微信群：
![](/wechatgroup1.png)
