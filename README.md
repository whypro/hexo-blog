# Hexo Blog

## Install

```sh

git submodule init
git submodule update

```

```sh
docker build -t hexo:dev .
docker run -it -v ${PWD}:/hexo-blog -v ${HOME}/.ssh:/home/node/.ssh -v ~/.gitconfig:/etc/gitconfig -w /hexo-blog -p 4000:4000 -u ${UID}:${GID} hexo:dev
```

## Use

### Generate

```sh
hexo clean
hexo generate
```

### Local Serve

```sh
hexo serve
```

### Deploy

```sh
hexo deploy
```

## Dependencies

- [hexo-theme-icarus](https://github.com/ppoffice/hexo-theme-icarus)

- [hexo-all-minifier](https://github.com/chenzhutian/hexo-all-minifier)

- hexo-tag-bootstrap (Optinal): [hexo-theme-freemind.386](https://github.com/blackshow/hexo-theme-freemind.386)

- hexo-generator-search (Optinal): [hexo-theme-freemind.386](https://github.com/blackshow/hexo-theme-freemind.386)

- hexo-renderer-stylus (Optinal): [hexo-theme-melody](https://github.com/Molunerfinn/hexo-theme-melody)

- hexo-renderer-pug (Optinal): [hexo-theme-melody](https://github.com/Molunerfinn/hexo-theme-melody)
