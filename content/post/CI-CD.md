+++
author = "fanux"
date = "2018-10-10T10:54:24+02:00"
draft = false
title = "基于drone构建CI/CD系统,对接k8s"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

# [kubernetes集群三步安装](https://sealyun.com/pro/products/)

# CI 概述
### 用一个可描述的配置定义整个工作流

程序员是很懒的动物，所以想各种办法解决重复劳动的问题，如果你的工作流中还在重复一些事，那么可能就得想想如何优化了

持续集成就是可以帮助我们解决重复的代码构建，自动化测试，发布等重复劳动，通过简单一个提交代码的动作，解决接下来要做的很多事。

容器技术使这一切变得更完美。

典型的一个场景：

我们写一个前端的工程，假设是基于vue.js的框架开发的，提交代码之后希望跑一跑测试用例，然后build压缩一个到dist目录里，再把这个目录的静态文件用nginx代理一下。 
最后打成docker镜像放到镜像仓库。 甚至还可以增加一个在线上运行起来的流程。

现在告诉你，只需要一个git push动作，接下来所有的事CI工具会帮你解决！这样的系统如果你还没用上的话，那请问还在等什么。接下来会系统的向大家介绍这一切。

# 代码仓库管理
首先SVN这种渣渣软件就该尽早淘汰，没啥好说的，有git真的没有SVN存在的必要了我觉得。

所以我们选一个git仓库,git仓库比较多，我这里选用gogs，gitea gitlab都行，根据需求自行选择
```
docker run -d --name gogs-time -v /etc/localtime:/etc/localtime -e TZ=Asia/Shanghai --publish 8022:22 \
           --publish 3000:3000 --volume /data/gogs:/data gogs:latest
```
访问3000端口，然后就没有然后了
gogs功能没有那么强大，不过占用资源少，速度快，我们稳定运行了几年了。缺点就是API不够全。

# CI 工具

当你用过drone之后。。。

装：
```
version: '2'

services:
  drone-server:
    image: drone/drone:0.7
    ports:
      - 80:8000
    volumes:
      - /var/lib/drone:/var/lib/drone/
    restart: always
    environment:
      - DRONE_OPEN=true
      - DOCKER_API_VERSION=1.24
      - DRONE_HOST=10.1.86.206
      - DRONE_GOGS=true
      - DRONE_GOGS_URL=http://10.1.86.207:3000/   # 代码仓库地址
      - DRONE_SECRET=ok

  drone-agent:
    image: drone/drone:0.7
    command: agent
    restart: always
    depends_on:
      - drone-server
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - DOCKER_API_VERSION=1.24
      - DRONE_SERVER=ws://drone-server:8000/ws/broker
      - DRONE_SECRET=ok
```
`docker-compose up -d` 然后你懂的，也没有然后了

用gogs账户登录drone即可

每个步骤就是个容器，每个插件也是个容器，各种组合，简直就是活字印刷术

怎么使用这种初级肤浅的内容我就不赘述了，但是有很多坑的地方：

* 装drone的机器能用aufs尽量用，device mapper有些插件是跑不了的，如一些docker in docker的插件，这不算是drone的毛病，只能说docker对 docker in docker支持不够好
* centos对aufs支持不够好，如果想用centos支持aufs，那你可得折腾折腾了，社区方案在此：https://github.com/sealyun/kernel-ml-aufs
* 最推荐的是drone的机器内核升级到4.9以上,然后docker使用overlay2存储驱动，高版本内核跑容器笔者也实践过比较长的时间了，比低内核稳定很多

安装方式2，在[k8s上安装](https://hub.kubeapps.com/charts/stable/drone)：
```
helm install stable/drone
```

# 使用篇
首先在你的代码仓库主目录下新建三个文件：

* .drone.yml : 描述构建与部署的流程（狭义），流程配置文件（广义）CI/CD无本质区别
* Dockerfile : 告诉你的应用如何打包成镜像，当然如果不是容器化交付可以不需要
* k8s yaml配置文件 or docker-compose文件 or chart包 ：告诉你的应用如何部署
* 其他 ：如kube-config等

用gogs账户密码登录到drone页面上之后同步下项目就可以看到项目列表，打开开关就可以关联到git仓库,比较简单，自行探索
![](http://docs.drone.io/images/drone_repo_list.png)

## 官方事例
```
pipeline:
  backend:    # 一个步骤的名称，可以随便全名
    image: golang  # 每个步骤的本质都是基于这个镜像去启动一个容器
    commands:      # 在这个容器中执行一些命令
      - go get
      - go build
      - go test

  frontend:
    image: node:6
    commands:
      - npm install
      - npm test

  publish:
    image: plugins/docker
    repo: octocat/hello-world
    tags: [ 1, 1.1, latest ]
    registry: index.docker.io

  notify:
    image: plugins/slack
    channel: developers
    username: drone
```

各步骤启动的容器共享workdir这个卷, 这样build步骤的结果产物就可以在publish这个容器中使用

结合Dockerfile看：
```
# docker build --rm -t drone/drone .

FROM drone/ca-certs
EXPOSE 8000 9000 80 443

ENV DATABASE_DRIVER=sqlite3
ENV DATABASE_CONFIG=/var/lib/drone/drone.sqlite
ENV GODEBUG=netdns=go
ENV XDG_CACHE_HOME /var/lib/drone

ADD release/drone-server /bin/   #  因为工作目录共享，所以就可以在publish时使用到 build时的产物，这样构建和发布就可以分离

ENTRYPOINT ["/bin/drone-server"]
```
上面说到构建与发布分离，很有用，如构建golang代码时我们需要go环境，但是线上或者运行时其实只需要一个可执行文件即可，

所以Dockerfile里就可以不用FROM一个golang的基础镜像，让你的镜像更小。又比如java构建时需要maven，而线上运行时不需要，

所以也是可以分离。


用drone时要发挥想象，千万不要用死了，上面每句话都需要仔细读一遍，细细理解。再总结一下关键点：

drone自身是不管每个步骤是什么功能的，只傻瓜式帮你起容器，跑完正常就执行下个步骤，失败就终止。

编译，提交到镜像仓库，部署，通知等功能都是由镜像的功能，容器的功能决定的 drone里叫插件，插件本质就是镜像，有一丢丢小区别后面说

这意味着你想干啥就弄啥镜像，如编译时需要maven，那去做个maven镜像，部署时需要对接k8s，那么搞个有kubectl客户端的镜像；要物理机部署那么搞个
ansible的镜像，等等，发挥想象，灵活使用。

## drone环境变量
有时我们希望CI出来的docker镜像tag与git的tag一致，这样的好处就是知道运行的是哪个版本的代码，升级等等都很方便，不过每次都去修改pipeline
文件显然很烦，那么drone就可以有很多环境变量来帮助我们解决这个问题：
```
pipeline:
    build:
        image: golang:1.9.2 
        commands:
            - go build -o test --ldflags '-linkmode external -extldflags "-static"'
        when:
            event: [push, tag, deployment]
    publish:
        image: plugins/docker
        repo: fanux/test
        tags: ${DRONE_TAG=latest}
        dockerfile: Dockerfile
        insecure: true
        when:
            event: [push, tag, deployment]
```
这个例子`${DRONE_TAG=latest}` 如果git tag事件触发了pipeline那就把git tag当镜像tag，否则就用latest，这样我们自己研发过程中就
可以一直用latest迭代，觉得版本差不多了，打个tag，生成一个可以给测试人员测试的镜像，非常优雅，不需要改什么东西，不容易出错

同理还有很多其它的环境变量可以用，如git的commitID  分支信息等等, [这里可以查](http://docs.drone.io/environment-reference/)

## 对接k8s实践
首先得有个k8s集群，那么首选：[kubernetes集群三步安装](https://sealyun.com/pro/products/) 广告，无视就好。。。

有了上面的铺垫，对接k8s就相当简单了：搞个kubectl的镜像嵌入流程中即可:

把项目的k8s yaml文件放到代码中，然后pipelie里直接apply
```
  publish:
    image: plugins/docker   # 镜像仓库,执行Dockerfile插件
    tags:
      - ${DRONE_TAG=latest}
    insecure: true  # 照抄
  
  deploy:
     image: kubectl:test  # 这个镜像自己去打即可
     commands:
          - cat test.yaml
          - ls   
          - rm -rf /root/.kube && cp -r .kube /root # k8s 的kubeconfig文件，可以有多个，部署到哪个集群就拷贝哪个kubeconfig文件
          - kubectl delete -f test.yaml || true
          - kubectl apply -f test.yaml 
```

不过最佳实践还有几个细节：

* k8s 的kubeconfig文件同样放在了代码目录（这个不太安全，不过仓库私有还好，还可以利用drone的secret，不细展开）
* k8s 部署的yaml文件里的镜像怎么配置？ 每次都修改test.yaml多不爽
* 如果多个集群yaml配置有区别怎么办？写多个yaml？造成混乱，非常不优雅

所以我们引入chart, 用helm进行部署:
```
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: test
  namespace: {{ .Values.namespace }}
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    metadata:
      labels:
        name: test
    spec:
      serviceAccountName: test
      containers:
      - name: test
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"  # deployment的yaml文件是模板，创建时再传参进来渲染
        imagePullPolicy: {{ .Values.image.pullPolicy }} 
....
```
注意，有了模板之后，我们部署v1版本和v2版本时就不需要改动yaml文件，这样降低出错风险，pipeline执行时把环境变量传进来，完美解决

这样git tag 镜像tag与yaml里镜像配置实现了完全的统一：
```
    deploy_dev:   # 部署到开发环境
        image: helm:v2.8.1
        commands:
            - mkdir -p /root/.kube && cp -r .kube/config-test101.194 /root/.kube 
            - helm delete test --purge || true
            - helm install --name test --set image.tag=${DRONE_TAG=latest}  Chart
        when:
            event: deployment
            environment: deploy_dev

    deploy_test:  # 部署到测试环境
        image: helm:v2.8.1
        commands:
            - mkdir -p /root/.kube && cp -r .kube/config-test101.84 /root/.kube  # 两个环境使用不同的kubeconfig
            - helm delete test --purge || true
            - helm install --name test --set image.tag=${DRONE_TAG=latest}  Chart # 把git tag传给helm，这样运行的镜像就是publish时构建的镜像，tag一致
        when:
            event: deployment
            environment: deploy_test
```
以上，优雅的解决了上面问题

细节：event可以是git的事件也可以是手动处罚的事件，类型是deployment时就是手动触发的，drone支持命令行触发

我们进行了二次开发，让drone可以在页面上触发对应的事件


# 原理篇
drone上开通一个仓库时，会给仓库设置一个webhook,在项目设置里可以看到，这样git的事件就可以通知到drone，drone根据事件去拉取代码走流程

## pipeline基本原理
理解原理对使用这个系统非常重要，否则就会把一个东西用死。

pipeline就负责起容器而已，容器干啥的系统不关心，用户决定   这句话本文不止强调过一次，非常重要多读几遍

## 插件原理
镜像即插件，也就是可能现有很多镜像都能直接当作插件嵌入到drone流程中。

有个小区别是，你会发现drone有些插件还带一些参数，这就是比普通的镜像多做了一丢丢事，如publish时打docker的镜像：
```
  publish:
    image: plugins/docker
    repo: octocat/hello-world
    tags: [ 1, 1.1, latest ]
    registry: index.docker.io
```
你会发现它有 repo tags什么的参数，其实drone处理时非常简单，就是把这些参数转化成环境变量传给容器了，
然后容器去处理这些参数。
本质就是做了这个事情：
```
docker run --rm \
  -e PLUGIN_TAG=latest \
  -e PLUGIN_REPO=octocat/hello-world \
  -e DRONE_COMMIT_SHA=d8dbe4d94f15fe89232e0402c6e8a0ddf21af3ab \
  -v $(pwd):$(pwd) \
  -w $(pwd) \
  --privileged \
  plugins/docker --dry-run
```

那我们自定义一个插件就简单了，只要写个脚本能处理特定环境变量即可，如一个curl的插件：
```
pipeline:
  webhook:
    image: foo/webhook
    url: http://foo.com
    method: post
    body: |
      hello world
```
写个脚本
```
#!/bin/sh

curl \
  -X ${PLUGIN_METHOD} \  # 处理一个几个环境变量
  -d ${PLUGIN_BODY} \
  ${PLUGIN_URL}
```
```
FROM alpine
ADD script.sh /bin/
RUN chmod +x /bin/script.sh
RUN apk -Uuv add curl ca-certificates
ENTRYPOINT /bin/script.sh
```
```
docker build -t foo/webhook .
docker push foo/webhook
```
打成docker镜像，大功告成

所以大部分情况我们会很懒的什么也不写，直接在容器里执行命令就是了，同样是一个curl的需求，不写插件的话
```
pipeline:
  webhook:
    image: busybox  # 直接用busybox
    command: 
    - curl -X POST -d 123 http://foo.com  完事，插件都懒得开发了
```

值得注意的是一些复杂功能还是需要开发插件的，如publish镜像时用的插件。关于该插件我想补充一句
它是docker里面起了一个docker engine，用docker内的docker engine进行打镜像的
所以devicemapper存储驱动是支持不了的。请升级内核用overlay2，或者ubuntu用aufs

# 其它推荐

* 镜像仓库：[harbor](https://github.com/goharbor/harbor)
* 制品库：[nexus](https://www.sonatype.com/nexus-repository-sonatype) 做maven仓库，yum仓库放二进制文件等非常合适，强烈推荐

# 总结
要实现高效的自动化，everything as code很重要，很多人喜欢在界面上点点点 填很多参数上线，其实是一种很容易出错的方式
不一定能提高效率。 你们项目如何构建，如何发布，如何部署都应该是代码，没有二义性，把人做的事让程序做，最终人仅是触发而已。

个人见解，探讨可加QQ群：98488045

# 公众号：
![sealyun](https://sealyun.com/kubernetes-qrcode.jpg)

### 微信群：
![](/wechatgroup1.png)
