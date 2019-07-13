# 离线包Changelog

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
