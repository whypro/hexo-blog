---
title: Hello, Hexo.
date: 2017-09-24 01:44:27
tags: [原创]
toc: true
---

周末折腾了半天，终于将博客从 Pelican 转到了 Hexo，在此记录一下。

## 方案选择

首先说说方案选择，目前博客系统大致分为静态和动态两类，动态博客有 Wordpress、Ghost 等等，因为需要单独的主机和搭建环境，并且数据存在 DB 迁移起来比较费劲，所以放弃了这种方案；静态博客有 Pelican、Jekyll、Hexo 等等，后者很多优点，访问速度快，博客可直接用 Markdown 以文件的形式保存在 Github，借助 Github Pages 部署方便，不用自己搭建主机，总之个人觉得这些优点可以完爆动态博客。

笔者之前的博客是基于 Pelican 的，因为使用 Python 写的，而自己对 Python 有一种痴迷，因此之前选用了这种方案，但是慢慢发现缺点有很多。首先是渲染速度慢，当文章越来越多时，博客生成的时间就会让人难以忍受。另外 Pelican 的主题都不是很炫，找了半天都没有找到好看的主题，这也是促使我选用其他博客系统的一个原因。

其次了解了 Jekyll，它是用 Ruby 开发的，也是 Github 主推的博客系统，和 Github 无缝结合，可以直接在 Github 页面上配置、修改主题（[教程在此](https://pages.github.com/)），主题也很多，如果没有遇见 Hexo，也许我会选择 Jekyll。

Hexo 使用 Nodejs 开发，渲染速度相对于 Python 和 Ruby 来说很快，而且 CLI 设计也非常人性化，配置简单，支持的插件也有很多，使用 `npm` 来管理。也许正是由于开发语言的关系，Hexo 的主题质量都非常高，都非常好看，让人眼花缭乱（[https://hexo.io/themes/index.html](https://hexo.io/themes/index.html)）。老实说我是被这款名叫 [AlphaDust](https://github.com/klugjo/hexo-theme-alpha-dust) 的主题吸引了，非常有科技感，而且响应式在移动设备上也比较完美，无论是英文字体还是中文字体都支持很好，对作者的敬意油然而生。当然 [NexT](http://theme-next.iissnan.com/) 也是一款非常优秀的主题，以后有机会可以尝试一下（^_^）。

<!-- more -->

## 安装和配置

### 安装
可以参考[官方文档](https://hexo.io/docs/index.html)。

首先安装 nvm：

``` shell
$ curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.2/install.sh | bash
```

安装完成后重启终端，安装 nodejs 和 hexo：

``` shell
$ nvm install stable
$ npm install -g hexo-cli
```

创建一个新的博客项目：

``` shell
$ hexo init <folder>
$ cd <folder>
$ npm install
```

### 配置
这里要注意的是如果使用 Github Pages，URL 包含子目录时，要注意设置 `_config.yml` 中的 `url` 和 `root`。

``` yaml
url: http://whypro.github.io/hexo-blog
root: /hexo-blog/
```

文章 URL 和文件名的配置按照个人喜好来修改：

``` yaml
permalink: :year:month:day/:title/
new_post_name: :year:month:day-:title.md
```

## 部署 Github Pages

首先在配置文件中加入 Github 相关信息：

``` yaml
deploy:  
  type: git
  repository: git@github.com:<username>/<reponame>.git
  branch: gh-pages
```

然后执行：

``` shell
$ hexo generate
$ hexo deploy
```

## 后续工作

至于博客的全文搜索，可以用 [Swiftype](https://swiftype.com/) 服务，有空再研究一下。

关于代码高亮可以参考 [CSS classes reference](http://highlightjs.readthedocs.io/en/latest/css-classes-reference.html)。

## 参考文献
[1] [博客从 Ghost 迁移到 Hexo](https://www.race604.com/migrate-ghost-to-hexo/)

