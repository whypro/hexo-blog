---
title: Power Designer 连接 PostgreSQL 逆向工程若干问题解决笔记
tags:
  - Power Designer
  - PostgreSQL
  - 原创
categories: []
toc: true
date: 2016-04-13 19:56:00
modified: 2016-04-13 19:56:00
slug: power-design-postgresql-reverse-engineering
---

首先说说系统环境，Windows 7 64 位系统，PowerDesigner 16.5，远程 PostgreSQL 9.4 数据库，JDK 为 64 位的 Java 8。

笔者依次点击：

`Database->Configure Connections...->Connection Profiles->Add Datasource`

输入以下配置：

```
Connection type: JDBC
DBMS type: PostgreSQL
JDBC driver class: org.postgresql.Driver
JDBC connection URL: jdbc:postgresql://<your_host>:5432/<your_database>
```

但是点击 Test connection 时出现了问题。

## Could not Initialize JavaVM!

### 原因分析

这个原因很简单，笔者安装的是 64 位的 JDK 和 JRE，而 Power Designer 是 32 位的，其 JDBC 无法在 64 位的 Java 虚拟机上运行。

### 解决

从 Oracle 官网上下载 32 位的 JDK，安装时不要自动配置环境变量，因为笔者系统里的其他程序还要运行在 64 位虚拟机上，能不能只让 Power Designer 在 32 位虚拟机上运行呢？下一步将完美解决这个问题。

## Non SQL Error : Could not load class org.postgresql.Driver

### 原因分析

原因是找不到 PostgreSQL 的 Java 驱动。

### 解决

访问 http://jdbc.postgresql.org/download.html，下载对应的 jar 包（笔者下载的是 `postgresql-9.4.1208.jar`）。

将下载下来的 jar 包放入某个目录，笔者放在了 `D:\Tools\Sybase\PowerDesigner 16\SQL Anywhere 12 drivers` 这个目录，当然你可以放到任意目录。

然后在 Power Designer 安装目录新建一个 `PowerDesigner.bat` 文件，输入以下内容：

```bat
set JAVA_HOME="C:\Program Files (x86)\Java\jdk1.8.0_77"
set CLASSPATH="%JAVA_HOME%\lib\jt.jar;%JAVA_HOME%\lib\tools.jar;D:\Tools\Sybase\PowerDesigner 16\SQL Anywhere 12 drivers\postgresql-9.4.1208.jar"
cd "D:\Tools\Sybase\PowerDesigner 16"
start /b PdShell16.exe
exit
```

其中 JAVA_HOME 是上一步安装的 32 位 JDK 的目录，CLASSPATH 包含那个 postgresql 的 Java 驱动 jar 包。

保存后，右键发送到桌面快捷方式即可，也可以给它换个图标，以后运行时双击这个快捷方式就可以了。

## Unable to list the columns. SQLSTATE = 22003不良的类型值 short : t

然而成功连接数据库后建模时出现了“不良的类型值问题”，解决方法如下：

依次点击 

`Database->Edit Current DBMS...->General Tab->PostgreSQL 9.x->Script->Objects`

或者 

`Tools->Edit Current DBMS->PostgreSQL 9.x->Script->Objects`

将 Column->SqlListQuery 选项里 `SELECT` 中的 `c.attnotnull` 替换为 `cast(nullif(c.attnotnull, false) as varchar(1))`

将 Key->SqlListQuery 选项里 `SELECT` 中的 `x.indisprimary` 替换为 `cast(nullif(x.indisprimary, false) as varchar(1))`

保存即可。

---

参考文章：
- [用PowerDesigner远程连接PostgreSQL数据库](http://www.bixuda.com/2010/08/27/%E7%94%A8powerdesigner%E8%BF%9C%E7%A8%8B%E8%BF%9E%E6%8E%A5postgresql%E6%95%B0%E6%8D%AE%E5%BA%93/)
- [PowerDesigner 16.5 反向PostgreSQL9.01 中 Unable to list the columns. SQLSTATE = 22003不良的类型值 short : t 解决方法](http://www.cnblogs.com/ITbbs/p/4441693.html)
