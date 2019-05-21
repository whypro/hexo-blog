---
title: Python 多线程响应 Ctrl + C，用 Event 实现
tags:
  - 原创
  - Python
  - 多线程
originContent: ''
categories: []
toc: true
date: 2013-05-05 18:39:00
---

在用 python 编写多线程程序时，经常需要用 Ctrl + C 中止进程，可是大家都知道，在 python 中，除了主线程可以响应控制台的 Ctrl + C ，其他线程是无法捕获到的，也就是说，当主线程被中止后，其他线程也会被强制中止，这样线程们就没有机会处理自己还没有完成的工作。

而在实际应用中，我们可能会有这样的要求：

1. 当按下 Ctrl + C 时，我们希望所有线程先处理完自己的任务，再主动停止

2. 当所有线程停止后，主线程才终止

【[这篇文章](http://my.oschina.net/apoptosis/blog/125099)】提供了一种方法，我对其做了进一步改进，写了如下的代码，希望能起到抛砖引玉的作用：

<!-- more -->

``` python
# -*- coding: utf-8 -*-
import threading

class MyThread(object):
    def __init__(self, thread_num):
        self.thread_num = thread_num        # 线程个数
        self.outLock = threading.Lock()     # 控制台输出锁
        self.threads = []                   # 线程列表
        self.interruptEvent = threading.Event() # 键盘中断事件
    
    def beginTask(self):
        # 将线程加入线程列表
        for i in range(self.thread_num):
            t_name = str(i + 1)
            thread = threading.Thread(target=self.doSomething, kwargs={"t_name": t_name})
            self.threads.append(thread)

        # 启动线程
        for thread in self.threads:
            thread.start()
        self.interruptEvent.clear()             # clear
        # 用 isAlive 循环判断代替线程的 join 方法
        
        while True:
            try:
                alive = False
                for thread in self.threads:
                    alive = alive or thread.isAlive()
                if not alive:
                    break
            except KeyboardInterrupt:
                self.interruptEvent.set()           # set
    
    def doSomething(self, t_name):
        self.outLock.acquire()
        print u"线程 %s 已启动" % t_name
        self.outLock.release()
        while True:
            try:
                if self.interruptEvent.isSet():     # isSet
                    raise KeyboardInterrupt
                ########################
                # doSomething 函数代码 #
                ########################
            except KeyboardInterrupt:
                ##################
                # 处理最后的工作 #
                ##################
                self.outLock.acquire()
                print u"用户强制中止主线程，线程 %s 已中止" % t_name
                self.outLock.release()                
                break
        self.outLock.acquire()
        print u"线程 %s 已停止" % t_name
        self.outLock.release()
        
                        
if __name__ == "__main__":
    t = MyThread(5)
    t.beginTask()
```

程序启动后，如图 1 所示：

{% asset_img 184109_ddmL_730461.png %}

<!--
![](http://static.oschina.net/uploads/space/2013/0505/184109_ddmL_730461.png)  
-->

按下 Ctrl + C 后，如图 2 所示：

{% asset_img 184123_2RT2_730461.png %}

<!--
![](http://static.oschina.net/uploads/space/2013/0505/184123_2RT2_730461.png)  
-->

这样各个线程都有机会处理自己的任务后主动停止，随后主线程再终止。