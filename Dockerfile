FROM node:12
RUN npm install -g hexo-cli
RUN sed -i -E 's/(deb|security).debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list \
  && apt update \
  && apt install -y --no-install-recommends libtool automake autoconf nasm libjpeg-dev
CMD ["bash"]
