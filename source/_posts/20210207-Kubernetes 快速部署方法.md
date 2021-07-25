---
title: Kubernetes 快速部署方法
tags:
  - Kubernetes
  - K8S
  - 运维
  - 原创
categories: []
toc: true
date: 2021-02-07 23:36:11
updated: 2021-02-08 21:36:44
---

## 安装 Docker

https://kubernetes.io/docs/setup/production-environment/container-runtimes/#docker

### 国内加速替换软件源

http://mirrors.ustc.edu.cn/

``` sh
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key --keyring /etc/apt/trusted.gpg.d/docker.gpg add -

sudo add-apt-repository \
  "deb [arch=amd64] http://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/ \
  $(lsb_release -cs) \
  stable"
```

## 安装 kubeadm

https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

<!-- more -->

### 国内加速替换软件源

``` sh
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb http://mirrors.ustc.edu.cn/kubernetes/apt/ kubernetes-xenial main
EOF
```

## 使用 kubeadm 创建集群

https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/


```yaml
apiVersion: kubeadm.k8s.io/v1beta2
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: abcdef.0123456789abcdef
  ttl: 24h0m0s
  usages:
  - signing
  - authentication
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 192.168.122.11
  bindPort: 6443
nodeRegistration:
  criSocket: /var/run/dockershim.sock
  taints: []
---
apiServer:
  timeoutForControlPlane: 4m0s
apiVersion: kubeadm.k8s.io/v1beta2
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
controllerManager: {}
dns:
  type: CoreDNS
etcd:
  local:
    dataDir: /var/lib/etcd
imageRepository: registry.aliyuncs.com/google_containers
kind: ClusterConfiguration
kubernetesVersion: v1.20.0
networking:
  dnsDomain: cluster.local
  serviceSubnet: 10.96.0.0/12
  podSubnet: 172.16.0.0/16
scheduler: {}

```

## 安装网络插件 (calico)

https://docs.projectcalico.org/getting-started/kubernetes/self-managed-onprem/onpremises#install-calico-with-kubernetes-api-datastore-50-nodes-or-less

## 安装 Helm

https://helm.sh/docs/intro/install/

## 安装 Ingress Controller (ingress-nginx)

https://kubernetes.github.io/ingress-nginx/deploy/#using-helm

``` sh
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx -f ingress-nginx-values.yaml
```

## 安装存储插件 (local-volume-provisioner)

``` sh
helm install local-volume-provisioner . -f values_local.yaml -n kube-system
```

``` sh
mkdir /mnt/fast-disks/pv{0..3}
for i in {0..3}; do mount --bind /mnt/fast-disks/pv$i /mnt/fast-disks/pv$i; done
```

`/etc/fstab`

```
/mnt/fast-disks/pv0 /mnt/fast-disks/pv0 none defaults,bind 0 0
/mnt/fast-disks/pv1 /mnt/fast-disks/pv1 none defaults,bind 0 0
/mnt/fast-disks/pv2 /mnt/fast-disks/pv2 none defaults,bind 0 0
/mnt/fast-disks/pv3 /mnt/fast-disks/pv3 none defaults,bind 0 0
```
