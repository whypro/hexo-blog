---
title: 在本地运行 Kubernetes e2e 测试
tags:
  - Kubernetes
  - K8S
  - e2e
  - 原创
categories: []
toc: true
date: 2021-03-06 18:48:51
updated: 2021-03-06 23:19:28
---

## 安装 kubetest

https://github.com/kubernetes/test-infra/tree/master/kubetest#installation

```
go install k8s.io/test-infra/kubetest
```

或者

```sh
GO111MODULE=on go install ./kubetest
```

## 构建二进制

```sh
kubetest --build
```

## 启动本地集群

```sh
./hack/local-up-cluster.sh
```

如果没有安装 etcd 需要先安装

```sh
./hack/install-etcd.sh
```

使用 kubectl 访问

<!-- more -->

```sh
cluster/kubectl.sh config set-cluster local --server=https://localhost:6443 --certificate-authority=/var/run/kubernetes/server-ca.crt
cluster/kubectl.sh config set-credentials myself --client-key=/var/run/kubernetes/client-admin.key --client-certificate=/var/run/kubernetes/client-admin.crt
cluster/kubectl.sh config set-context local --cluster=local --user=myself
cluster/kubectl.sh config use-context local
cluster/kubectl.sh
```

## 启动 e2e test

```sh
kubetest --provider=local --test --test_args="--ginkgo.focus=XXX"
```

## 快速编译 e2e test

```sh
make WHAT=test/e2e/e2e.test
```


## 参考
https://github.com/kubernetes/community/blob/master/contributors/devel/sig-testing/e2e-tests.md
