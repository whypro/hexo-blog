---
title: youtube-dl 配置备忘
tags:
  - Youtube
  - youtube-dl
  - 运维
  - 原创
categories: []
toc: true
date: 2021-01-22 22:53:16
updated: 2021-03-13 18:12:18
---

youtube-dl 下载配置：

`/etc/youtube-dl.conf`

```
-f bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio
--merge-output-format mp4
--add-metadata
--embed-thumbnail --embed-subs --all-subs --xattrs
--yes-playlist
--write-info-json
--output "%(uploader)s/%(playlist).40s/[%(upload_date)s] %(title).68s [%(id)s].%(ext)s"
--output-na-placeholder ""
--ignore-errors
```

<!-- more -->

创建 systemd 定时任务，每一小时执行一次：

`/usr/lib/systemd/system/youtube-dl.timer` 或 `/etc/systemd/system/youtube-dl.timer`

```
[Unit]
Description=youtube-dl timer

[Timer]
OnUnitActiveSec=1h
Unit=youtube-dl.service

[Install]
WantedBy=multi-user.target
```

创建 systemd 服务：

`/usr/lib/systemd/system/youtube-dl.service` 或 `/etc/systemd/system/youtube-dl.service`
```
[Unit]
Description=youtube-dl

[Service]
WorkingDirectory=/home/whypro/youtube-dl
Environment=http_proxy=http://127.0.0.1:1080
Environment=https_proxy=http://127.0.0.1:1080
#ExecStart=/usr/bin/youtube-dl --batch-file=todo.txt --download-archive=archive.txt
ExecStart=/usr/local/bin/youtube-dl --batch-file=/home/whypro/youtube-dl/todo.txt --download-archive=/home/whypro/youtube-dl/
User=whypro
Group=whypro

[Install]
WantedBy=multi-user.target
```

参考：
[Systemd 定时器教程 - 阮一峰的网络日志](http://www.ruanyifeng.com/blog/2018/03/systemd-timer.html)
