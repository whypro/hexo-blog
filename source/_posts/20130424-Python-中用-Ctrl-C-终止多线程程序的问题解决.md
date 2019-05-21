---
title: Python 中用 Ctrl+C 终止多线程程序的问题解决
date: 2013-04-24 21:02:00
tags: [原创, Python]
---

花了一天时间用python为服务写了个压力测试。很简单，多线程向服务器发请求。但写完之后发现如果中途想停下来，按Ctrl+C达不到效果，自然想到要用信号处理函数捕捉信号，使线程都停下来，问题解决的方法请往下看：

<!-- more -->

``` python
#!/bin/env python
# -*- coding: utf-8 -*-
#filename: peartest.py

import threading, signal

is_exit = False

def doStress(i, cc):
    global is_exit
    idx = i
    while not is_exit:
    if (idx < 10000000):
        print "thread[%d]: idx=%d"%(i, idx)
        idx = idx + cc
    else:
        break
    print "thread[%d] complete."%i

def handler(signum, frame):
    global is_exit
    is_exit = True
    print "receive a signal %d, is_exit = %d"%(signum, is_exit)

if __name__ == "__main__":
    signal.signal(signal.SIGINT, handler)
    signal.signal(signal.SIGTERM, handler)
    cc = 5
    for i in range(cc):
        t = threading.Thread(target=doStress, args=(i,cc))
        t.start()
```

上面是一个模拟程序，并不真正向服务发送请求，而代之以在一千万以内，每个线程每隔并发数个（cc个）打印一个整数。很明显，当所有线程都完成自己的任务后，进程会正常退出。但如果我们中途想退出（试想一个压力测试程序，在中途已经发现了问题，需要停止测试），该肿么办？你当然可以用ps查找到进程号，然后kill -9杀掉，但这样太繁琐了，捕捉Ctrl+C是最自然的想法。上面示例程序中已经捕捉了这个信号，并修改全局变量is_exit，线程中会检测这个变量，及时退出。

但事实上这个程序并不work，当你按下Ctrl+C时，程序照常运行，并无任何响应。网上搜了一些资料，明白是python的子线程如果不是daemon的话，主线程是不能响应任何中断的。但设为daemon后主线程会随之退出，接着整个进程很快就退出了，所以还需要在主线程中检测各个子线程的状态，直到所有子线程退出后自己才退出，因此上例29行之后的代码可以修改为：

``` python
threads=[]
for i in range(cc):
    t = threading.Thread(target=doStress, args=(i, cc))
    t.setDaemon(True)
    threads.append(t)
    t.start()
for i in range(cc):
    threads[i].join()
```

重新试一下，问题依然没有解决，进程还是没有响应Ctrl+C，这是因为join()函数同样会waiting在一个锁上，使主线程无法捕获信号。因此继续修改，调用线程的isAlive()函数判断线程是否完成：

``` python
while 1:
    alive = False
    for i in range(cc):
        alive = alive or threads[i].isAlive()
    if not alive:
    break
```

这样修改后，程序完全按照预想运行了：可以顺利的打印每个线程应该打印的所有数字，也可以中途用Ctrl+C终结整个进程。完整的代码如下：

``` python
#!/bin/env python
# -*- coding: utf-8 -*-
#filename: peartest.py

import threading, signal

is_exit = False

def doStress(i, cc):
    global is_exit
    idx = i
    while not is_exit:
        if (idx < 10000000):
            print "thread[%d]: idx=%d"%(i, idx)
            idx = idx + cc
        else:
            break
    if is_exit:
        print "receive a signal to exit, thread[%d] stop."%i
    else:
        print "thread[%d] complete."%i

def handler(signum, frame):
    global is_exit
    is_exit = True
    print "receive a signal %d, is_exit = %d"%(signum, is_exit)

if __name__ == "__main__":
    signal.signal(signal.SIGINT, handler)
    signal.signal(signal.SIGTERM, handler)
    cc = 5
    threads = []
    for i in range(cc):
    t = threading.Thread(target=doStress, args=(i,cc))
    t.setDaemon(True)
    threads.append(t)
    t.start()
    while 1:
        alive = False
        for i in range(cc):
            alive = alive or threads[i].isAlive()
        if not alive:
            break
```

其实，如果用python写一个服务，也需要这样，因为负责服务的那个线程是永远在那里接收请求的，不会退出，而如果你想用Ctrl+C杀死整个服务，跟上面的压力测试程序是一个道理。

总结一下，python多线程中要响应Ctrl+C的信号以杀死整个进程，需要：

1. 把所有子线程设为Daemon；  
2. 使用isAlive()函数判断所有子线程是否完成，而不是在主线程中用join()函数等待完成；  
3. 写一个响应Ctrl+C信号的函数，修改全局变量，使得各子线程能够检测到，并正常退出。