---
title: 为树莓派制作 Arch Linux SD 卡
date: 2015-04-08 18:27:00
tags: [树莓派, Arch Linux, 转载]
toc: true
---

> *该文为译文，原文地址：* http://archlinuxarm.org/platforms/armv6/raspberry-pi

将下面的 `sdX` 替换成你的 SD 卡的设备名。

1. 使用 fdisk 为 SD 卡分区：

    ``` sh
    fdisk /dev/sdX
    ```

<!-- more -->

2. 根据 fdisk 的提示删除旧分区。然后创建一个新分区：

    1. 输入 `o`。这将清除驱动器上的所有分区。
    2. 输入 `p` 列出分区。列表中应该没有任何分区了。
    3. 输入 `n`，然后 `p` 设置为主分区，`1` 设置为驱动器第一个分区，按 `回车` 不更改起始扇区的默认值，输入 `+100M` 设置结束扇区。
    4. 输入 `t`，然后 `c` 将第一个分区设为 W95 FAT32 (LBA) 格式。
    5. 输入 `n`，然后 `p` 设置为主分区，`2` 设置为驱动器第二个分区，按 `回车` 不更改起始扇区和结束扇区的默认值。
    6. 输入 `w` 保存分区表退出。

3. 创建并挂载 FAT 文件系统：

    ``` sh
    mkfs.vfat /dev/sdX1
    mkdir boot
    mount /dev/sdX1 boot
    ```

4. 创建并挂载 ext4 文件系统：

    ``` sh
    mkfs.ext4 /dev/sdX2
    mkdir root
    mount /dev/sdX2 root
    ```

5. 下载并解压 root 文件系统（用 root 身份，而不是 sudo）：

    ``` sh
    wget http://archlinuxarm.org/os/ArchLinuxARM-rpi-2-latest.tar.gz
    bsdtar -xpf ArchLinuxARM-rpi-2-latest.tar.gz -C root
    sync
    ```

6. 将 boot 文件移动至第一个分区：

    ``` sh
    mv root/boot/* boot
    ```

7. 卸载这两个分区：

    ``` sh
    umount boot root
    ```

8. 将 SD 卡插入树莓派，连接至以太网，提供 5V 电源。

9. 使用串口终端或者 SSH 访问路由器提供的树莓派 IP 地址，默认 root 密码为 `root`。
