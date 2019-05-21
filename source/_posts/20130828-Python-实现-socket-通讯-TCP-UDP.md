---
title: 'Python 实现 socket 通讯 (TCP/UDP) '
tags:
  - 原创
  - Python
  - 网络
originContent: ''
categories: []
toc: false
date: 2013-08-28 11:50:00
---

# 1. TCP

## 1.1 TCP-Server

``` python
# -*- coding: utf-8 -*-
# TCP-Server

import socket

# 1. 创建 socket 对象
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

# 2. 将 socket 绑定到指定地址
address = ('127.0.0.1', 10140) 
s.bind(address)

# 3. 接收连接请求
s.listen(5)

# 4. 等待客户请求一个连接
# 调用 accept 方法时，socket 会进入 "waiting" 状态。
# accept方法返回一个含有两个元素的元组 (connection, address)。
# 第一个元素 connection 是新的 socket 对象，服务器必须通过它与客户通信；
# 第二个元素 address 是客户的 Internet 地址。
ss, addr = s.accept()
print 'got connect from', addr

# 5. 处理：服务器和客户端通过 send 和 recv 方法通信
# send 方法返回已发送的字节个数。
# 调用 recv 时，服务器必须指定一个整数，它对应于可通过本次方法调用来接收的最大数据量。
# recv方法在接收数据时会进入 "blocked" 状态，最后返回一个字符 串，用它表示收到的数据。
# 如果发送的数据量超过了recv 所允许的，数据会被截短。
# 多余的数据将缓冲于接收端。以后调用recv时，多余的数据会从缓冲区删除。
while True:
    ra = ss.recv(512)
    print 'client:', ra
    ss.send('received')

# 6. 传输结束，关闭连接
ss.close()
s.close()
```

<!-- more -->

## 2.2 TCP-Client

``` python
# -*- coding: utf-8 -*-
# TCP-Client

import socket

address = ('127.0.0.1', 10140)
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(address)

while True:
    message = raw_input()
    if not message:
        break
    s.send(message)
    data = s.recv(512)
    print 'server:', data

s.close()
```

# 2. UDP

## 2.1 UDP-Server

``` python
# -*- coding: utf-8 -*-
# UDP-Server

import socket

address = ('127.0.0.1', 10141)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(address)

while True:
    data, addr = s.recvfrom(2048)
    print "received:", data, "from", addr

s.close()
```

## 2.2 UDP-Client

``` python
# -*- coding: utf-8 -*-
# UDP-Client

import socket  
  
address = ('127.0.0.1', 10141)  
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)  
  
while True:  
    message = raw_input()  
    if not message:  
        break  
    s.sendto(message, address)  
  
s.close()
```