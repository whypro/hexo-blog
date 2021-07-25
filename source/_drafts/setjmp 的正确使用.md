Title: setjmp 的正确使用
Date: 2016-09-09 00:30:35
Modified: 2016-09-09 00:31:11
Category: Linux
<!-- Tags: pelican, publishing -->
Slug: usage-of-setjmp
<!-- Authors: Alexis Metaireau, Conan Doyle -->
<!-- Summary: Short version for index and feeds -->

`setjmp` 是 C 语言解决 `exception` 的标准方案。我个人认为，`setjmp/longjmp` 这组 api 的名字没有取好，导致了许多误解。名字体现的是其行为：跳转，却没能反映其功能：`exception` 的抛出和捕获。

`longjmp` 从名字上看，叫做长距离跳转。实际上它能做的事情比名字上看起来的要少得多。跳转并非从静止状态的代码段的某个点跳转到另一个位置（类似在汇编层次的 jmp 指令做的那样），而是在运行态中向前跳转。C 语言的运行控制模型，是一个基于栈结构的指令执行序列。表示出来就是 `call/return` ：调用一个函数，然后用 `return` 指令从一个函数返回。`setjmp/longjmp` 实际上是完成的另一种调用返回的模型。`setjmp` 相当于 `call`，`longjmp` 则是 `return`。

重要的区别在于：`setjmp` 不具备函数调用那样灵活的入口点定义；而 `return` 不具备 `longjmp` 那样可以灵活的选择返回点。其次，第一、`setjmp` 并不负责维护调用栈的数据结构，即，你不必保证运行过程中 `setjmp` 和 `longjmp` 层次上配对。如果需要这种层次，则需要程序员自己维护一个调用栈。这个调用栈往往是一个 `jmp_buf` 的序列；第二、它也不提供调用参数传递的功能，如果你需要，也得自己来实现。

以库形式提供的 `setjmp/longjmp` 和以语言关键字 `return` 提供的两套平行的运行流控制放在一起，大大拓展了 C 语言的能力。把 `setjmp/longjmp` 嵌在单个函数中使用，可以模拟 `pascal` 中嵌套函数定义：即在函数中定义一个局部函数。ps. GNUC 扩展了 C 语言，也在语法上支持这种定义方法。这种用法可以让几个局部函数有访问和共享 `upvalue` 的能力。把 `setjmp/longjmp` 放在大框架上，则多用来模拟 `exception` 机制。

`setjmp` 也可以用来模拟 `coroutine` 。但是会遇到一个难以逾越的难点：正确的 `coroutine` 实现需要为每个 `coroutine` 配备一个独立的数据栈，这是 `setjmp` 无法做到的。虽然有一些 C 的 `coroutine` 库用 `setjmp/longjmp` 实现。但使用起来都会有一定隐患。多半是在单一栈上预留一块空间，然后给另一个 `coroutine` 运行时覆盖使用。当数据栈溢出时，程序会发生许多怪异的现象，很难排除这种溢出 bug 。要正确的实现 `coroutine` ，还需要 `setcontext` 库 ，这已经不是 C 语言的标准库了。

在使用 `setjmp` 时，最常见的一个错误用法就是对 `setjmp` 做封装，用一个函数去调用它。比如：
    
    :::c
    int try(breakpoint bp)
    {
        return setjmp(bp->jb);
    }
    
    void throw(breakpoint bp)
    {
        longjmp(bp->jb,1);
    }

`setjmp` 不应该封装在一个函数中。这样写并不讳引起编译错误。但十有八九会引起运行期错误。错误的起源在于 `longjmp` 的跳转返回点，必须在运行流经过并有效的位置。而如果对 setjmp 做过一层函数调用的封装后。上例中的 `setjmp` 设置的返回点经过 `try` 的调用返回后，已经无效。如果要必要封装的话，应该使用宏。

`setjmp/longjmp` 对于大多数 C 程序员来说比较陌生。正是在于它的定义含糊不清，不太容易弄清楚。使用上容易出问题，运用场合也就变的很狭窄，多用于规模较大的库或框架中。和 C++ 语言提供的 `execption` 机制一样，很少有构架师愿意把它暴露到外面，那需要对二次开发的程序员有足够清晰的头脑，并充分理解其概念才不会用错。这往往是不可能的。

另外，`setjmp/longjmp` 的理念和 C++ 本身的 RAII 相冲突。虽然许多编译器为防止 C++ 程序员错误使用 `setjmp` 都对其做了一定的改进。让它可以正确工作。但大多数情况下，还是在文档中直接声明不推荐在 C++ 程序中使用这个东西。

btw，关于 RAII ，的确是个好东西。但和诸多设计模式一样，不是真理。如果你是一个从 C++ 进化来的 C 程序员，则更应该警惕思维的禁锢，RAII 是一种避免资源泄露的好方案，但不是唯一方案。

原文地址：[http://blog.codingnow.com/2010/05/setjmp.html](http://blog.codingnow.com/2010/05/setjmp.html)
