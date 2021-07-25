---
title: K8s Node Docker devicemapper 设备初始化方法
tags:
  - Kubernetes
  - K8S
  - Docker
  - devicemapper
  - 存储
  - 运维
  - 原创
categories: []
toc: true
date: 2019-01-01 00:00:00
---


## 步骤

1. drain 掉节点上所有的 pod

```
kubectl drain <node-name> --ignore-daemonsets --delete-local-data --force
```

2. 停止 kubelet

```
systemctl stop kubelet
```

3. 停止所有容器

```
docker stop $(docker ps -a -q)
docker rm $(docker ps -a -q)
```

4. 停止 docker daemon

```
systemctl stop docker
```

<!-- more -->

6. 创建 lvm

```
pvcreate -y /dev/sdX1
vgcreate docker /dev/sdX1
lvcreate --wipesignatures y -n thinpool docker -l 95%VG
lvcreate --wipesignatures y -n thinpoolmeta docker -l 1%VG
lvconvert -y --zero n -c 512k --thinpool docker/thinpool --poolmetadata docker/thinpoolmeta
```

`vim /etc/lvm/profile/docker-thinpool.profile`

*配置见附录*

```
lvchange --metadataprofile docker-thinpool docker/thinpool
lvs -o+seg_monitor
```

`vim /etc/docker/daemon.json`

*配置见附录*

7. 删除旧的 docker 相关文件

```
rm -rf /var/lib/docker/*
```

8. 启动 docker

```
systemctl start docker
```

9. 查看是否成功转换

```
docker info
```

10. 启动 kubelet

```
systemctl start kubelet
```

11. uncordon 节点

```
kubectl uncordon <node-name>
```

## 附录

`/etc/lvm/profile/docker-thinpool.profile`

```
activation {
  thin_pool_autoextend_threshold=80
  thin_pool_autoextend_percent=20
}
```

`/etc/docker/daemon.json`

```
{
  "log-level": "debug",
  "live-restore": true,
  "icc": false,
  "storage-driver": "devicemapper",
  "storage-opts": [
    "dm.thinpooldev=/dev/mapper/docker-thinpool",
    "dm.use_deferred_removal=true",
    "dm.use_deferred_deletion=true",
    "dm.basesize=20G"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "512m",
    "max-file": "3"
  }
}
```

## 参考

[Use the Device Mapper storage driver](https://docs.docker.com/storage/storagedriver/device-mapper-driver/#configure-direct-lvm-mode-for-production)
