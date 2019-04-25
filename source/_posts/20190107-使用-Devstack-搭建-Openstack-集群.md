---
title: 使用 Devstack 搭建 Openstack 集群
tags:
  - 原创
  - Openstack
  - 云计算
originContent: ''
categories: []
toc: true
date: 2019-01-07 15:22:00
---

## 环境搭建

多节点搭建步骤：

[https://docs.openstack.org/devstack/rocky/guides/multinode-lab.html](https://docs.openstack.org/devstack/rocky/guides/multinode-lab.html)


要配置 kvm，否则使用默认的 qemu 跑 vm 性能会很差：

[https://docs.openstack.org/devstack/rocky/guides/devstack-with-nested-kvm.html](https://docs.openstack.org/devstack/rocky/guides/devstack-with-nested-kvm.html)

control 节点配置:

``` ini
[[local|localrc]]
HOST_IP=10.20.102.37
FLAT_INTERFACE=bond0
FIXED_RANGE=10.4.128.0/20
FIXED_NETWORK_SIZE=4096
FLOATING_RANGE=10.20.102.223/27
MULTI_HOST=1
LOGFILE=/opt/stack/logs/stack.sh.log
ADMIN_PASSWORD=
DATABASE_PASSWORD=
RABBIT_PASSWORD=
SERVICE_PASSWORD=
LIBVIRT_TYPE=kvm
IP_VERSION=4
```

compute 节点配置: 

``` ini
[[local|localrc]]
HOST_IP=10.20.102.38 # change this per compute node
FLAT_INTERFACE=bond0
FIXED_RANGE=10.4.128.0/20
FIXED_NETWORK_SIZE=4096
FLOATING_RANGE=10.20.102.223/27
MULTI_HOST=1
LOGFILE=/opt/stack/logs/stack.sh.log
ADMIN_PASSWORD=
DATABASE_PASSWORD=
RABBIT_PASSWORD=
SERVICE_PASSWORD=
DATABASE_TYPE=mysql
SERVICE_HOST=10.20.102.37
MYSQL_HOST=$SERVICE_HOST
RABBIT_HOST=$SERVICE_HOST
GLANCE_HOSTPORT=$SERVICE_HOST:9292
ENABLED_SERVICES=n-cpu,q-agt,n-api-meta,c-vol,placement-client
NOVA_VNC_ENABLED=True
NOVNCPROXY_URL="http://$SERVICE_HOST:6080/vnc_auto.html"
VNCSERVER_LISTEN=$HOST_IP
VNCSERVER_PROXYCLIENT_ADDRESS=$VNCSERVER_LISTEN
LIBVIRT_TYPE=kvm
IP_VERSION=4
```

- `FIXED_RANGE` 是 vm 实例的内网地址，供 vm 之间访问，vm 创建时便会分配一个，创建后一般不能更改。
- `FLOATING_RANGE` 是 vm 实例的外网地址，供物理机访问 vm，以及 vm 访问物理机，可以在实例创建后进行绑定和解绑。这个网段一般设置为物理机 IP 的子网段。


如果需要 ipv6，则需要修改以下参数：

``` shell
net.ipv6.conf.all.disable_ipv6=0
net.ipv6.conf.default.disable_ipv6=0
net.ipv6.conf.lo.disable_ipv6=0

sysctl -p
```

不要按照 devstack 官方文档创建 `local.sh`。因为 openstack rocky 已经默认使用 neutron 了，这个脚本对 neutron 没有什么作用。[https://bugs.launchpad.net/devstack/+bug/1783576](https://bugs.launchpad.net/devstack/+bug/1783576)

```
for i in `seq 2 10`; do /opt/stack/nova/bin/nova-manage fixed reserve 10.4.128.$i; done
```

多节点如果出现调度错误，需要执行：

``` shell
./tools/discover_hosts.sh
```

或者：

``` shell
nova-manage cell_v2 discover_hosts --verbose
```

如果如果遇到一些未知的问题，尝试拆除环境，清除所有资源后重试：

``` shell
./unstack.sh
./clean.sh
./stack.sh
```

## 镜像创建

``` shell
openstack image create --public --disk-format qcow2 --container-format bare --file xenial-server-cloudimg-amd64-disk1.img ubuntu-xenial-server-amd64
```

## 实例创建

首先进行 admin 认证鉴权：

```
sudo su - stack
cd /opt/stack/devstack
source openrc
```

创建安全组规则，允许 ping 和 ssh：

``` shell
openstack security group rule create --proto icmp default
openstack security group rule create --proto tcp --dst-port 22 default
```

创建测试实例：

``` shell
openstack server create --flavor m1.tiny \
--image $(openstack image list | grep cirros | cut -f3 -d '|') \
--nic net-id=$(openstack network list | grep private | cut -f2 -d '|' | tr -d ' ') \
--security-group default vm 
```

创建 floating IP：

```
openstack floating ip create public
```

将 floating IP 与实例绑定：

``` shell
openstack server add floating ip vm 10.20.102.238
```

就可以通过 floating IP 登录 vm 实例了，用户名密码是：

```
cirros
cubswin:)
```

vm 如果需要上外网，需要配置 nat。在物理机上执行：

``` shell
#ifconfig br-ex 10.20.102.223/27
iptables -t nat -I POSTROUTING -s 10.20.102.223/27 -j MASQUERADE
iptables -I FORWARD -s 10.20.102.223/27 -j ACCEPT
iptables -I FORWARD -d 10.20.102.223/27 -j ACCEPT
```

## 配置卷类型

创建 pv 和 vg：

``` shell
pvcreate /dev/sdb1
vgcreate stack-volumes-hdd /dev/sdb1
```

配置 cinder：

``` shell
vim /etc/cinder/cinder.conf
```

``` ini
[DEFAULT]
default_volume_type = hdd
enabled_backends = hdd,ssd

[hdd]
image_volume_cache_enabled = True
volume_clear = zero
lvm_type = auto
target_helper = tgtadm
volume_group = stack-volumes-hdd
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver
volume_backend_name = hdd
```

重启 openstack：

``` shell
systemctl restart devstack@*
```

创建卷类型：

``` shell
openstack volume type create hdd
openstack volume type set hdd --property volume_backend_name=hdd
```

## 常见问题

### volume 无法创建

- 排查

``` shell
sudo journalctl -f --unit devstack@c-vol
```

```
Mar 06 14:59:18 kirk-system cinder-volume[27813]: ERROR oslo_service.service [None req-e1391562-6252-4b98-ba3a-6420edbafffe None None] Error starting thread.: DetachedInstanceError: Parent instance <VolumeAttachment at 0x7f6455ffee90> is not bound to a Session; lazy load operation of attribute 'volume' cannot proceed (Background on this error at: http://sqlalche.me/e/bhk3)
```

- 解决

[https://ask.openstack.org/en/question/103315/cinder-volume-attached-to-a-terminated-server-now-i-cant-delete-it/](https://ask.openstack.org/en/question/103315/cinder-volume-attached-to-a-terminated-server-now-i-cant-delete-it/)


### ubuntu 18.04 切换到 /etc/network/interface

[https://askubuntu.com/questions/1031709/ubuntu-18-04-switch-back-to-etc-network-interfaces](https://askubuntu.com/questions/1031709/ubuntu-18-04-switch-back-to-etc-network-interfaces)

## 参考文档

- golang SDK：[http://gophercloud.io/docs/compute/#servers](http://gophercloud.io/docs/compute/#servers)

- terraform：[https://www.terraform.io/docs/providers/openstack/](https://www.terraform.io/docs/providers/openstack/)

- 获取 Openstack 镜像：[https://docs.openstack.org/image-guide/obtain-images.html](https://docs.openstack.org/image-guide/obtain-images.html)

- 使用 systemd 管理 devstack：[https://docs.openstack.org/devstack/rocky/systemd.html](https://docs.openstack.org/devstack/rocky/systemd.html)

- devstack networking：

    - [https://docs.openstack.org/devstack/rocky/networking.html](https://docs.openstack.org/devstack/rocky/networking.html)
    - [https://wiki.openstack.org/wiki/OpsGuide-Network-Troubleshooting](https://wiki.openstack.org/wiki/OpsGuide-Network-Troubleshooting)

- neutron 相关：

    - [https://docs.openstack.org/devstack/rocky/guides/neutron.html](https://docs.openstack.org/devstack/rocky/guides/neutron.html)
    - [https://www.ibm.com/developerworks/cn/cloud/library/1402_chenhy_openstacknetwork/](https://www.ibm.com/developerworks/cn/cloud/library/1402_chenhy_openstacknetwork/)



## 附

neutron+vlan 模式配置：

``` ini
[[local|localrc]]
HOST_IP=10.20.102.37
PUBLIC_INTERFACE=bond1
LOGFILE=/opt/stack/logs/stack.sh.log
ADMIN_PASSWORD=
DATABASE_PASSWORD=
RABBIT_PASSWORD=
SERVICE_PASSWORD=
LIBVIRT_TYPE=kvm

## Neutron options
IP_VERSION=4
Q_USE_SECGROUP=True
ENABLE_TENANT_VLANS=True
TENANT_VLAN_RANGE=3001:4000
PHYSICAL_NETWORK=default
OVS_PHYSICAL_BRIDGE=br-ex
Q_USE_PROVIDER_NETWORKING=True
disable_service q-l3

## Neutron Networking options used to create Neutron Subnets
IPV4_ADDRS_SAFE_TO_USE="203.0.113.0/24"
NETWORK_GATEWAY=203.0.113.1
PROVIDER_SUBNET_NAME="provider_net"
PROVIDER_NETWORK_TYPE="vlan"
SEGMENTATION_ID=2010
USE_SUBNETPOOL=False
```


``` ini
[[local|localrc]]
HOST_IP=10.20.102.38 # change this per compute node
LOGFILE=/opt/stack/logs/stack.sh.log
ADMIN_PASSWORD=
DATABASE_PASSWORD=
RABBIT_PASSWORD=
SERVICE_PASSWORD=
DATABASE_TYPE=mysql
SERVICE_HOST=10.20.102.37
MYSQL_HOST=$SERVICE_HOST
RABBIT_HOST=$SERVICE_HOST
GLANCE_HOSTPORT=$SERVICE_HOST:9292
ENABLED_SERVICES=n-cpu,q-agt,n-api-meta,c-vol,placement-client
NOVA_VNC_ENABLED=True
NOVNCPROXY_URL="http://$SERVICE_HOST:6080/vnc_auto.html"
VNCSERVER_LISTEN=$HOST_IP
VNCSERVER_PROXYCLIENT_ADDRESS=$VNCSERVER_LISTEN
LIBVIRT_TYPE=kvm

# Services that a compute node runs
ENABLED_SERVICES=n-cpu,rabbit,q-agt

## Open vSwitch provider networking options
IP_VERSION=4
PHYSICAL_NETWORK=default
OVS_PHYSICAL_BRIDGE=br-ex
PUBLIC_INTERFACE=bond1
Q_USE_PROVIDER_NETWORKING=True
```
