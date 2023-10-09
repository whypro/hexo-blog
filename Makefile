CURRENT_UID := $(shell id -u):$(shell id -g)

build:
	docker build -t hexo:dev .

run:
	export UID=1000
	export GID=1000
	docker run -it -v ${PWD}:/hexo-blog -v ${HOME}/.ssh:/home/node/.ssh -v ~/.gitconfig:/etc/gitconfig -w /hexo-blog -p 4000:4000 -u $(CURRENT_UID) hexo:dev
