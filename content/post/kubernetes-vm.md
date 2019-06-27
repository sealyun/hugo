+++
author = "fanux"
date = "2019-06-22T10:54:24+02:00"
draft = false
title = "强隔离容器那些事"
tags = ["event","dotScale","sketchnote"]
comments = true     # set false to hide Disqus comments
share = true        # set false to share buttons
menu = ""           # set "main" to add this content to the main menu
+++

探讨可加QQ群：98488045

强隔离容器的那些事

原创： sealnux  sealyun  今天
| 为什么需要强隔离容器

      我们在生产环境中运行容器已久，第一次对强隔离容器诉求是java类应用引起的，如果不配置jvm参数，java虚拟机会根据系统资源信息进行内存gc线程数等配置，在不给容器配额的情况下问题不大，一旦配额了。。。

     普通的容器在容器中看到的资源还是宿主机的资源，那么假设宿主机128G而你给容器配额2G，此时堆内存按照128G去分，可想而知后果，同理还有gc线程数等

| 给jvm配置参数就行了呗

   我们很难改变用户行为，让用户都去改动参数不太现实。

| lxcfs一定程度上解决了这个问题

![](/lxcfs.jpg)

     lxcfs可以让容器有更好的资源可视性，如内存，cpuset等，原理也非常简单，就是把proc下的一些文件还在给容器，容器内进程读取资源信息时系统调用会被lxcfs拦截，然后到cgroup下去查该进程资源配额信息进行计算，大部分场景可以通过这个方式修修补补

![](/lxcfs1.jpg)


| 然鹅，lxcfs的缺陷

第一，支持lxcfs的运行时甚少
第二，用户使用时不透明，需要自行挂载很多文件不友好
第三，由于第二点，你就得去开发一些特性去支持它，主流方式有几种
    1.k8s上监听一些对象的创建，进行修改
    2.修改kubelet，在volume里默认加上，我们就是这样做的，正在把这个特性PR给社区
    3.修改runtime，或者直接选择支持这个特性的运行时，如pouch
第四，cpushare的方式，我们也正在把这个特性pr给社区，通过计算占比把计算后的cpu核数上报给进程
第五，很多应用从system下面去读取资源信息，而非proc，这样又是一大波定制需求。。。还有remout等等问题

   总体来说都是修修补补，不能从彻底上解决问题

这让我越来越看好轻量级虚拟化技术

      kata runv等技术的出现真的是把虚拟机容器的优势强强结合，容器的调度编排管理生态，镜像标准，再加上虚拟机的强隔离

![](/kata.jpg)


   下面开始一大波名词解释以及他们之间的关系

    containerd地位难以撼动，真正管理容器的守护进程，k8s和docker都可以通过unix socket去调用它，然后每起一个容器containerd会去调用runc runv kata等

  kata runv qemu firecracker rust-vmm都是啥关系

   kata和runv都是可以被containerd调用然后调用qemu命令去启动虚拟机

      qemu 和firecracker是一个级别，真正去启动虚拟机的，和张磊大佬交流时这里引用大佬一句话:qemu是在一大坨功能上做减法，firecracker是在非常核心简单的功能上做加法。

      那么我们到底因该选qemu还是firecracker呢，那肯定是与场景相关了，比如我们希望用重量级虚拟机，有状态，需要迁移，需要systemd sshd等，那么肯定还是走qemu libvirt， 如果我们走轻量级虚拟机firecracker是个非常不错的选择，而且潜力巨大，毕竟是来跑亚马逊函数计算的，不是盖的。看下firecracker api就发现真简单，再去看qemu文档。。。。什么**鸟玩意儿。。。  

     qemu大神别喷我，我承认其强大，但是很多时候遇到问题有点无从下手，很多使用方法我也是从源码中摸索出来的，个人还是喜欢更轻量级的东西。不过我依然还是对学习qemu有很大热情。

    顺便提一下libvirt，既然重，那不如再重一点，libvirt能让你更方便的管理qemu虚拟机和qemu开发，细节不赘述了

    rust-vmm是个更底层的一系列组件，大佬说是政治产物，自己如果对写hypervisor有兴趣可以抱着学习态度去开发玩，生产中直接firecracker就好了，所以rust的潜力还是巨大的，为了写虚拟机为了写操作系统，和我一起学rust🤪🤪
 
铺垫的差不多了，下面正式开始:

    因为kata能支持firecracker和qemu，所以针对kata这个技术来做个具体点的介绍

| 进程模型

![](/kata2.jpg)

     所以kata runtime替代掉的是runc部分的东西，因为中间有containerd，所以上层如docker k8s感知不到运行时的变化。

![](/kata3.jpg)


      containerd会与kata的shim进程通信，shim与agent通信，agent在虚拟机里面做一些事情，如配置网卡，启动容器等。

| 虚拟化方式

![](/kata4.jpg)

      这个图虚线左边不用看，本质就是调用qemu命令创建虚拟机，右边实际上kata是把k8s pod这个壳本来是容器，换成了虚拟机，但是有很多细节：
 1.  网络任然在一个ns中，下文会讲
 2.  kata agent依然会在虚拟机中启动容器

| kata网络

![](/kata-net.jpg)

     熟悉docker默认网络模式的亲都比较清楚设备对还没变，设备对的另外一端与虚拟机连接是由kata负责，用的技术叫macvtap，它可以让一个接口拥有多个mac地址。

创建macvtap设备：
ip link add link eth0 name macvtap0 type macvtap mode bridge
ip link set macvtap0 address 1a:46:0b:ca:bc:7b up
cat /sys/class/net/macvtap0/ifindex
cat /sys/class/net/macvtap0/address
通过qemu启动：
qemu-system-x86_64 -enable-kvm centos.qcow2 \
 -cdrom CentOS-7-x86_64-Minimal-1810.iso \
 -netdev tap,fd=30,id=hostnet0,vhost=on,vhostfd=4 30<>/dev/tap2 4<>/dev/vhost-net \
 -device virtio-net-pci,netdev=hostnet0,id=net0,mac=1a:46:0b:ca:bc:7b   \
 -monitor telnet:127.0.0.1:5801,server,nowait
VNC server running on ::1:5900
   注意网络参数，这块很少资料介绍的比较清楚都是啥含义，我也是通过学习kata源码问了很多大牛才彻底理解的。 
/dev/tap2 这个2 是通过上面的 /sys/class/net/macvtap0/ifindex 差得的。
vhost是虚拟机网络虚拟化的一种模式，性能比较高，我们需要把vhost的fd传入给qemu

对应kata的代码，本质就是打开了这两文件，把fd传入：
func createMacvtapFds(linkIndex int, queues int) ([]*os.File, error) {
  tapDev := fmt.Sprintf("/dev/tap%d", linkIndex)
  return createFds(tapDev, queues)
}

  fds := make([]*os.File, numFds)
  for i := 0; i < numFds; i++ {
    f, err := os.OpenFile(device, os.O_RDWR, defaultFilePerms)
    if err != nil {
      utils.CleanupFds(fds, i)
      return nil, err
    }
    fds[i] = f
  }
  return fds, nil
事情还没结束，进入虚拟机会发现网卡没有地址：
[root@localhost ~]# ip addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 52:54:00:59:ee:01 brd ff:ff:ff:ff:ff:ff
    inet6 fe80::5054:ff:fe59:ee01/64 scope link 
       valid_lft forever preferred_lft forever
     因为虚拟机的eth0的地址是kata-agent去配置的，所以这里需要自己在虚拟机配置一下，ip一定要与设备对另一端的eth0一样。

     网络其它的部分就是兼容CNI标准了，本文不做过多介绍了。

| 文件系统DAX(Direct Access filesystem) 
      内核DAX功能有效地将一些主机端文件映射到来宾VM空间。特别是Kata Containers使用QEMU NVDIMM功能提供内存映射的虚拟设备，可用于将虚拟机的根文件系统DAX映射到guest内存地址空间。

![](/DAX.jpg)

看rootfs是这样过去的
QEMU配置了NVDIMM内存设备，内存文件后端在主机端文件中映射到虚拟NVDIMM空间。
guest虚拟机内核命令行安装此NVDIMM设备并启用DAX功能，允许直接页面映射和访问，从而绕过guest虚拟机页面缓存。这样虚拟机的根文件系统就来了。

| 内核文件
kata kernel 此连接有详细介绍
1. kata对内核做了一些patch,如内存热插拔，9pfs缓存优化，arm架构的更好支持等
2. patch完了后把编译好的内核放到kata指定的目录
make -j $(nproc) ARCH="${arch_target}"

| docker镜像转化成虚拟机镜像
     osbuilder项目专门去做这个事情，这里要解释的一个概念是initrd（或“initramfs”）压缩cpio(1)归档，由rootfs创建，加载到内存中并用作Linux启动过程的一部分。在启动期间，内核将其解压缩到一个特殊的实例中，该实例tmpfs将成为初始的根文件系统。
 
        使用方法也比较简单，这里不再赘述。

| firecracker简介

![](/firecracker.jpg)

    为什么我这么喜欢firecracker，因为你们一看它API就知道的，简单到让你怀疑人生：
以下是个网络的例子：

1. 宿主机上创建tap设备
sudo ip tuntap add tap0 mode tap
sudo ip addr add 172.16.0.1/24 dev tap0
sudo ip link set tap0 up
sudo sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i tap0 -o eth0 -j ACCEPT

2. 调用API创建虚拟机网卡
curl -X PUT \
  --unix-socket /tmp/firecracker.socket \
  http://localhost/network-interfaces/eth0 \
  -H accept:application/json \
  -H content-type:application/json \
  -d '{
      "iface_id": "eth0",
      "guest_mac": "AA:FC:00:00:00:01",
      "host_dev_name": "tap0"
    }'
3. 配置虚拟机网卡
ip addr add 172.16.0.2/24 dev eth0
ip route add default via 172.16.0.1 dev eth0
清清楚楚，干干净净

| 轻量级虚拟机其它
     现在轻量级虚拟机还是有些问题没解决，比如监控，就不能像cadvisor那样去监控容器了，所以这块kubelet采集的地方就需要定制。

| kubevirt简介
       以上都是轻量级虚拟机，然而对于亡openstack之心不死的人还是希望搞出个能管理重量级虚拟机的东西，kubevirt应运而生。 

       我们如果去基本kata去管理有状态的重量级虚拟机其实还是有很多事要去做的：
生命周期管理，k8s可没有启动停止容器这些概念，所以想要支持虚拟机的启动重启就得自己去定义CRD，然后还不够，因为kubelet不会去调用CRI的启动停止的接口，所以还得修改kubelet...
网络，一般的CNI是满足不了IP漂移以及VPC这种需求的，所以你需要ovn CNI之类的东西
虚拟机的系统盘数据盘放本地是不行了，改。。。
兼容openstack那些系统镜像，改。。。

kubevirt正是因为这个问题所以采用了这样的架构：

![](/kubevirt.jpg)

    仅资源调度时走k8s，虚拟机的生命周期管理基本已经与CRI没关系了，全走自己的agent管理，这样上面的那些问题都可以在virt-handler virt-laucher上解决，不用再去对k8s组件动刀。

     本质就是在容器里起了个虚拟机，不过启动方式与kata有所不同，它使用了libvirt，qemu更上层的一个封装，当然玩重量级虚拟机有这个还是方便很多的，很多时候我们需要调试，或者找错误，libvirt给了一系列的工具集，同时也对编程友好。

     不过每个虚拟机都会去起一个libvirtd进程的做法我觉得还是有待商榷。

| 总结
      本文虽然扯了很多，但是虚拟机还是远比容器复杂，本文也只能提个冰山一角，希望大家读完能有个整体的认识。我是希望能用一个统一的技术栈搞定容器，虚拟机，轻量级虚拟机，这样能极大的节省企业的成本，尤其是人力维护成本。 

# 公众号：
![sealyun](https://sealyun.com/kubernetes-qrcode.jpg)

### 微信群：
![](/wechatgroup1.png)
