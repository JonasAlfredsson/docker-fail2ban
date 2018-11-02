# If we have `--squash` support, then use it!
ifneq ($(shell docker build --help 2>/dev/null | grep squash),)
DOCKER_BUILD = docker build --squash
else
DOCKER_BUILD = docker build
endif

all: build

build: Makefile Dockerfile
	$(DOCKER_BUILD) -t jonasal/fail2ban .
	@echo "Done!  Use docker run jonasal/fail2ban to run"

release:
	$(DOCKER_BUILD) -t jonasal/fail2ban --pull --no-cache .

push:
	docker push jonasal/fail2ban
