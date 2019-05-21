---
title: BeautifulSoup3 编码问题总结
date: 2013-03-28 23:51:00
tags: [原创, 爬虫, Python]
---

关于 BeautifulSoup3 对 `gb2312` 编码的网页解析的乱码问题，【[这篇文章](http://leeon.me/a/beautifulsoup-chinese-page-resolve)】提出了一个勉强能用的解决方法。即如果中文页面编码是 `gb2312`，`gbk`，在 BeautifulSoup 构造器中传入 `fromEncoding="gb18030"` 参数即可解决乱码问题，即使分析的页面是 `utf8` 的页面使用 `gb18030` 也不会出现乱码问题！如：

<!-- more -->

``` python
from urllib2 import urlopen
from BeautifulSoup import BeautifulSoup

page = urllib2.urlopen('http://www.baidu.com');
soup = BeautifulSoup(page,fromEncoding="gb18030")

print soup.originalEncoding
```

为什么网页是 `utf8` 传入 `gb18030` 依然能够正常解析呢？

这是由于，BeautifulSoup 的编码检测顺序为：

1. 创建 Soup 对象时传递的 `fromEncoding` 参数；  
2. XML/HTML 文件自己定义的编码；  
3. 文件开始几个字节所表示的编码特征，此时能判断的编码只可能是以下编码之一：UTF-#，EBCDIC 和 ASCII；  
4. 如果你安装了 `chardet`，BeautifulSoup 就会用 `chardet` 检测文件编码；  
5. UTF-8；  
6. Windows-1252。

因此，当传入 `fromEncoding="gb18030"` 编码参数与 html 文件编码不匹配时，BeautifulSoup 并不会抛出异常，而是按照预定义的编码检测顺序，按照 utf8 来解析，因此也可以勉强得到正确结果！