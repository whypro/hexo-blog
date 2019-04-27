---
title: Kubernetes APIServer 证书的手动签发
tags:
  - 原创
  - Kubernetes
  - K8S
  - 云计算
originContent: ''
categories: []
toc: true
date: 2017-12-06 20:13:00
---

## 背景

有时我们需要将自定义的域名或 IP 加入到 apiserver 的证书中，以通过 kubectl 或 kubelet 等客户端的验证，这个时候就需要对 apiserver 证书中包含的 IP 和 DNS 信息做些修改。

## 概念

首先介绍几个概念：

- KEY: 私钥
- CSR: Certificate Signing Request 证书签名请求（公钥）
- CRT: Certificate 证书
- x.509: 一种证书格式
- PEM: X.509 证书文件具体的存储格式（有时候用 pem 代替 crt 后缀）

## 步骤

重新生成 apiserver 证书的步骤：

1. 创建 2048bit 的 `ca.key` （`/etc/kubernetes/pki` 目录已经存在可跳过）

``` sh
openssl genrsa -out ca.key 2048
```

2. 基于 `ca.key` 创建 `ca.crt` （`/etc/kubernetes/pki` 已经存在可跳过）

``` sh
openssl req -x509 -new -nodes -key ca.key -subj "/CN=kube-apiserver" -days 10000 -out ca.crt
```

3. 创建 2048bit 的 `server.key` （`/etc/kubernetes/pki` 已经存在可跳过）

```
openssl genrsa -out apiserver.key 2048
```

4. 编辑创建 csr 需要的配置文件

根据需要添加或修改相应字段

``` ini
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn
 
[ dn ]
CN = kube-apiserver
 
[ req_ext ]
subjectAltName = @alt_names
 
[alt_names]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
DNS.5 = haoyu-k8s-1
IP.1 = 10.96.0.1
IP.2 = 172.21.1.13
IP.3 = 183.2.220.210
 
[ v3_ext ]
keyUsage=critical, digitalSignature, keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=@alt_names
```

5. 创建 `server.csr`

``` sh
openssl req -new -key apiserver.key -out apiserver.csr -config csr.conf
```

6. 基于 `ca.key` `ca.crt` `server.csr` 创建 `server.crt`

``` sh
openssl x509 -req -in apiserver.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out apiserver.crt -days 10000 -extensions v3_ext -extfile csr.conf
```

7. 查看生成的 `server.crt`

```
openssl x509  -noout -text -in ./apiserver.crt
```

最好和原证书 diff 一下，以保证其他字段一致


对于多个 apiserver 高可用的场景，方便起见可以将生成的 `apiserver.crt` 和 `apiserver.key` 一同拷贝到多个节点的 `/etc/kubernetes/pki` 目录下（使用同一份私钥和证书）。

## 示例

`csr.conf`:

主要关注 alt_names 的 DNS 和 IP 字段：

``` ini
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn
 
[ dn ]
CN = kube-apiserver
 
[ req_ext ]
subjectAltName = @alt_names
 
[alt_names]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
DNS.5 = kubernetes.kube-system.svc.cluster.local
DNS.6 = host1
DNS.7 = host2
DNS.8 = host3
 
IP.1 = 172.16.0.1
IP.2 = 10.200.20.11
IP.3 = 10.200.20.12
IP.4 = 10.200.20.13
IP.5 = 10.200.20.200
 
[ v3_ext ]
keyUsage=critical, digitalSignature, keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=@alt_names
```

`cert.sh`:

根据 `csr.conf` 自动签发 `apiserver.crt`，并拷贝至 `/etc/kubernetes/pki` 目录：

``` sh
openssl req -new -key /etc/kubernetes/pki/apiserver.key -out apiserver.csr -config csr.conf
openssl x509 -req -in apiserver.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out apiserver.crt -days 10000 -extensions v3_ext -extfile csr.conf
 
openssl x509  -noout -text -in /etc/kubernetes/pki/apiserver.crt > apiserver.crt.old.txt
openssl x509  -noout -text -in apiserver.crt > apiserver.crt.txt
diff apiserver.crt.txt apiserver.crt.old.txt
 
mv /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.crt.bak.$(date +%Y%m%d%H%M%S)
cp apiserver.crt /etc/kubernetes/pki/apiserver.crt
chmod 400 /etc/kubernetes/pki/apiserver.crt
```

## 参考

- [https://kubernetes.io/docs/concepts/cluster-administration/certificates/](https://kubernetes.io/docs/concepts/cluster-administration/certificates/)