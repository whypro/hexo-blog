FROM node:12
#RUN npm install
RUN npm install -g hexo-cli
# hexo-all-minifier dependencies
RUN sed -i -E 's/(deb|security).debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list \
  && apt update \
  && apt install -y --no-install-recommends libtool automake autoconf nasm libjpeg-dev
#RUN npm install hexo
#RUN npm install hexo-server
#RUN npm install hexo-deployer-git
#WORKDIR /hexo
