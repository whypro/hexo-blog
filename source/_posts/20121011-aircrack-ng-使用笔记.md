---
title: aircrack-ng 使用笔记
date: 2012-10-11 00:08:00
tags: [黑客技术, 原创]
---


**1. airmon-ng：激活网卡监听**

```
airmon-ng start wlan0
```

**2. airodump-ng：捕获802.11数据报文，以便于破解**

无参数启动 airodump-ng 可查看所有接收范围内的AP、Client信息

```
airodump-ng \[-w filename\] \[-c channel\] mon0
```

其中，-w 后的参数为保存的文件名，-c 后的参数为频段

**3. aireplay-ng：根据需要创建特殊的无线网络数据报文**

_**aireplay-ng -9：注入攻击链路质量测试**_

**WEP:**

_**aireplay-ng -1：伪认证联机请求攻击**_

伪认证联机请求并发送保持在线数据

```
aireplay-ng -1 6000 -o 1 -q 10 -e (bssid) -a (AP Mac) -h (Host Mac) mon0
```

_**aireplay-ng -3：ARP 攻击**_

监听 ARP 报文，一旦出现就不断将该报文重发，使目标机器产生实际回应数据，发回更多IV数据。

**对于无机器连接的 WEP：**

_**aireplay-ng -5：Fragmenation 攻击**_

监听一个 AP 广播出来的数据包，并抽离有效的伪随机数据(PRGA)，保存到 fragment-XXXX-XXXXX.xor 文件供下一步使用。

有时监听到的不是广播包，转发攻击后 AP 没有回应，一系列重试后程序会重新监听；有时候可能需要不少时间，加 –F 参数可以自动应答。

_**aireplay-ng -4：chopchop 攻击**_

上述攻击不奏效可试，相同作用。

**WPA/WPA2:**

_**aireplay-ng -0：Deauthentication 攻击**_

往已经连接到 AP 的一个客户端伪造一个离线包，使其离线重连以便捕捉 handshake。注意要收到 ACK，才表明被攻击客户端收到，才会下线；发送离线不宜过密过多。

**4. aircrack-ng：暴力破解**

```
aircrack-ng \[-w dictionary\] *.cap
```

暴力破解。其中，-w 参数为密码字典，破解的成功率取决于字典的覆盖程度以及机器的速度。