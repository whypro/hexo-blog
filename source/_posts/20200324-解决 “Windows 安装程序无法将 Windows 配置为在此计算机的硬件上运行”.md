---
title: 解决 “Windows 安装程序无法将 Windows 配置为在此计算机的硬件上运行”
tags:
  - 原创
  - NAS
  - Windows
  - Intel
  - 固态硬盘
  - SSD
categories: []
toc: true
date: 2020-03-24 00:39:00
---


我的 NAS 的配置是 HP Gen8 + Intel 志强 1220L v2，之前用 1T 的机械硬盘作为系统盘，因为感觉日常 IO 速度有些慢，恰好台式电脑淘汰下一个 Samsung 860 EVO SSD，所以决定替换磁盘。而此前一直是 Debian 10 + Windows Server 2008 R2 双系统，Linux 备份还原很简单，`dd` 命令使用起来非常方便，用 LiveCD chroot 刷新一次 grub 即可，但 Windows 就要重新安装和配置了。

因为 Windows 安装程序会覆盖掉硬盘的主引导记录 (MBR)，所以一般是先安装 Windows，再安装 Linux 用 grub 重写 MBR。


然而，当我认为一切尽在掌握之时，Windows Server 2008 R2 的安装程序在复制完文件重启配置时弹出“Windows 安装程序无法将 Windows 配置为在此计算机的硬件上运行”错误，然后就中断重启了。

{% asset_img error.jpg %}

<!-- more -->

之前从来没有遇到过这个问题，于是在网上查了很多帖子，尝试了以下几个方法：

首先尝试了[这个方法](https://www.dell.com/support/article/zh-cn/sln293812/windows-7-%E6%88%96-windows-10-%E5%AE%89%E8%A3%85%E6%9C%9F%E9%97%B4-windows-%E5%AE%89%E8%A3%85%E7%A8%8B%E5%BA%8F%E6%97%A0%E6%B3%95%E9%85%8D%E7%BD%AE%E4%B8%BA%E5%9C%A8%E6%AD%A4%E8%AE%A1%E7%AE%97%E6%9C%BA%E7%9A%84%E7%A1%AC%E4%BB%B6%E4%B8%8A%E8%BF%90%E8%A1%8C-%E9%94%99%E8%AF%AF?lang=zh)：

1. 在错误屏幕中, 按 `Shift + F10` 打开命令提示符 (或在 Windows 搜索栏中键入 `cmd`, 并从搜索结果菜单中选择 "命令提示符")。
2. 键入 `cd \` , 然后按 `enter` 键。
3. 键入 `cd x:\windows\system32\oobe` ( `x` 是安装 Windows 的驱动器号, 例如 `c:\windows\system32\oobe`), 然后按 `enter` 键。
4. 键入 `msoobe` , 然后按 `enter` 键。安装过程现在应该会自动继续。
5. 卸下安装介质, 系统应完成安装并引导至 Windows。


按这种方法操作后虽然安装程序继续进行了，但是重启后蓝屏。


有说分区问题的，我的硬盘是 250G，我用了 MBR 分区表，分了两个主分区，第一个分区是 Linux ext4 bootable，第二个分区是 Windows NTFS。我用 fdisk 重新分区，将分区互换，将 NTFS 分区放在了第一个分区，依然没用。


正在一筹莫展时，发现了这两篇文章：

https://www.cnblogs.com/niray/p/3931419.html

http://blog.sina.com.cn/s/blog_495113340100ovfe.html

这两篇文章都提到了 Intel RST 驱动，觉得分析的有点道理，可能是新版本的 SSD 造成了安装程序无法识别。

但这个驱动芯片组不同一般不能通用。查了相关文档，我的 Gen8 主板是 Intel C204 芯片组，也就是 Intel 6 Series/C200 系列芯片组，对应的 RST 版本应该是 [12.8.0.1016](https://www.techspot.com/drivers/driver/file/information/17341/)。很遗憾，不管是 Intel [中文](https://downloadcenter.intel.com/zh-cn/download/29339/-RST-)还是[英文](https://downloadcenter.intel.com/download/29094/Intel-Rapid-Storage-Technology-Intel-RST-User-Interface-and-Driver)官网都没有找到该版本的驱动程序。


正在要放弃的时候，发现了一根[救命稻草](https://www.chiphell.com/forum.php?mod=redirect&goto=findpost&ptid=1037686&pid=23415933)，这里分享了一个地址： http://pan.baidu.com/s/1ntLTF65 。赶紧下载下来，将 exe 解压（注意不要直接打开安装），找到 `Chipset_Intel_9.3.0.1025\Intel\All\cougahci.cat` 和 `cougahci.inf`，将这两个文件拷出来放到 U 盘或者用 iLO 加载至可移动设备，在 Windows 安装分区选择界面加载驱动程序时加载进去，再安装，问题完美解决，系统成功安装！（但这个驱动版本并不是 `12.8.0.1016`，只要 AHCI 驱动兼容就可以了。）
