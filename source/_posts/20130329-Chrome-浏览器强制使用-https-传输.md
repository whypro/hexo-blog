---
title: Chrome 浏览器强制使用 https 传输
date: 2013-03-29 19:33:00
tags: [原创]
toc: true
---

在日常工作和生活中，一些网站的访问很容易受到“不可抗拒因素”的影响，这大多都是因为 http 请求是明文传输，这样很容易受到某些防火墙的干扰，比如“101 CONNECT_RESET”。而 Chrome 强制使用 https 协议访问这些站点一般来说可以解决此问题，设置方法如下：

<!-- more -->

在 Chrome 地址栏输入 chrome://net-internals/#hsts ，如图，在 Domain（域名）中输入地址，如 google.com 或 facebook.com，选中 Include subdomains（包含子域名），点击 Add（添加）。

{% asset_img 193105_VZ7R_730461.png %}

<!--
![](http://static.oschina.net/uploads/space/2013/0329/193105_VZ7R_730461.png)
-->

再访问这些站点，就会发现强制使用 https 了。