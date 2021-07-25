Title: Linux 信号 signal 和 sigaction 理解
Date: 2016-09-09 00:30:11
Modified: 2016-09-09 00:31:12
Category: Linux
<!-- Tags: pelican, publishing -->
Slug: linux-signal-and-sigaction
<!-- Authors: Alexis Metaireau, Conan Doyle -->
<!-- Summary: Short version for index and feeds -->

今天看到UNP时发现之前对signal到理解实在浅显，今天拿来单独学习讨论下。

## signal
`signal`，此函数相对简单一些，给定一个信号，给出信号处理函数则可，当然，函数简单，其功能也相对简单许多，简单给出个函数例子如下：

    :::c
    #include <signal.h>  
    #include <stdio.h>  
    #include <unistd.h>  
      
    void ouch(int sig)  
    {  
        printf("I got signal %d\n", sig);  
        // (void) signal(SIGINT, SIG_DFL);  
        //(void) signal(SIGINT, ouch);  
      
    }  


    int main()  
    {  
        (void) signal(SIGINT, ouch);  
      
        while(1)  
        {  
            printf("hello world...\n");  
            sleep(1);  
        }  
    }

当然，实际运用中，需要对不同到 `signal` 设定不同的到信号处理函数，`SIG_IGN忽略/SIG_DFL默认`，这俩宏也可以作为信号处理函数。同时 `SIGSTOP/SIGKILL` 这俩信号无法捕获和忽略。注意，经过实验发现，`signal` 函数也会堵塞当前正在处理的 `signal`，但是没有办法阻塞其它 `signal`，比如正在处理 `SIG_INT`，再来一个 `SIG_INT` 则会堵塞，但是来 `SIG_QUIT` 则会被其中断，如果 `SIG_QUIT` 有处理，则需要等待 `SIG_QUIT` 处理完了，`SIG_INT` 才会接着刚才处理。

## sigaction
`sigaction`，这个相对麻烦一些，函数原型如下：

    :::c
    int sigaction(int sig, const struct sigaction *act, struct sigaction *oact)；

函数到关键就在于 `struct sigaction`

    :::c
    stuct sigaction  
    {  
          void (*)(int) sa_handle;  
          sigset_t sa_mask;  
          int sa_flags;  
    }  


    :::c
    #include <signal.h>  
    #include <stdio.h>  
    #include <unistd.h>  
      
      
    void ouch(int sig)  
    {  
        printf("oh, got a signal %d\n", sig);  
      
        int i = 0;  
        for (i = 0; i < 5; i++)  
        {  
            printf("signal func %d\n", i);  
            sleep(1);  
        }  
    }  
      
      
    int main()  
    {  
        struct sigaction act;  
        act.sa_handler = ouch;  
        sigemptyset(&act.sa_mask);  
        sigaddset(&act.sa_mask, SIGQUIT);  
        // act.sa_flags = SA_RESETHAND;  
        // act.sa_flags = SA_NODEFER;  
        act.sa_flags = 0;  
      
        sigaction(SIGINT, &act, 0);  
      
      
        struct sigaction act_2;  
        act_2.sa_handler = ouch;  
        sigemptyset(&act_2.sa_mask);  
        act.sa_flags = 0;  
        sigaction(SIGQUIT, &act_2, 0);  
      
        while(1)  
        {  
             sleep(1);  
        }  
        return;
    }  

1. 阻塞，`sigaction` 函数有阻塞的功能，比如 `SIGINT` 信号来了，进入信号处理函数，默认情况下，在信号处理函数未完成之前，如果又来了一个 `SIGINT` 信号，其将被阻塞，只有信号处理函数处理完毕，才会对后来的 `SIGINT` 再进行处理，同时后续无论来多少个 `SIGINT`，仅处理一个 `SIGINT`，`sigaction` 会对后续 `SIGINT` 进行排队合并处理。

2. sa_mask，信号屏蔽集，可以通过函数 `sigemptyset/sigaddset` 等来清空和增加需要屏蔽的信号，上面代码中，对信号 `SIGINT` 处理时，如果来信号 `SIGQUIT`，其将被屏蔽，但是如果在处理 `SIGQUIT`，来了 `SIGINT`，则首先处理 `SIGINT`，然后接着处理 `SIGQUIT`。

3. sa_flags 如果取值为 0，则表示默认行为。还可以取如下俩值，但是我没觉得这俩值有啥用。

    - SA_NODEFER，如果设置来该标志，则不进行当前处理信号到阻塞

    - SA_RESETHAND，如果设置来该标志，则处理完当前信号后，将信号处理函数设置为 `SIG_DFL` 行为

下面单独来讨论一下信号屏蔽，记住是屏蔽，不是消除，就是来了信号，如果当前是 `block`，则先不传递给当前进程，但是一旦 `unblock`，则信号会重新到达。

    :::c
    #include <signal.h>  
    #include <stdio.h>  
    #include <unistd.h>  

    static void sig_quit(int);  
      
    int main (void) {  
        sigset_t new, old, pend;  
          
        signal(SIGQUIT, sig_quit);  
      
        sigemptyset(&new);  
        sigaddset(&new, SIGQUIT);  
        sigprocmask(SIG_BLOCK, &new, &old);  
      
        sleep(5);  
      
        printf("SIGQUIT unblocked\n");  
        sigprocmask(SIG_SETMASK, &old, NULL);  
      
        sleep(50);  
        return 1;  
    }  
      
    static void sig_quit(int signo) {  
        printf("catch SIGQUIT\n");  
        signal(SIGQUIT, SIG_DFL);  
    }  

    :::shell
    gcc -g -o mask mask.c 
    ./mask

    ========这个地方按多次 ctrl+\

    SIGQUIT unblocked

    catch SIGQUIT
    Quit (core dumped)

    ======================

注意观察运行结果，在 `sleep` 的时候，按多次 `ctrl+\`，由于 `sleep` 之前 `block` 了 `SIG_QUIT`，所以无法获得 `SIG_QUIT`，但是一旦运行 `sigprocmask(SIG_SETMASK, &old, NULL);` 则 `unblock` 了 `SIG_QUIT`，则之前发送的 `SIG_QUIT` 随之而来。

由于信号处理函数中设置了 `DFL`，所以再发送 `SIG_QUIT`，则直接 `coredump`。

原文地址：[http://blog.csdn.net/beginning1126/article/details/8680757](http://blog.csdn.net/beginning1126/article/details/8680757)