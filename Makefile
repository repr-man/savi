PHONY:

# Prepare a docker container that has everything needed for development.
# It runs in the background indefinitely, waiting for `docker exec` commands.
ready: PHONY Dockerfile
	docker build --tag mare-dev .
	docker rm -f mare-dev || echo "the mare-dev container wasn't running"
	docker run --name mare-dev -v $(shell pwd):/opt/code -d --rm mare-dev tail -f /dev/null
	@echo "the mare-dev container is ready!"

# Run the test suite.
test: PHONY
	docker exec -ti mare-dev make test.inner
/tmp/bin/spec: $(shell find src) $(shell find spec)
	mkdir -p /tmp/bin
	crystal build --debug --link-flags="-lponyrt" spec/spec_helper.cr -o $@
test.inner: PHONY /tmp/bin/spec
	echo && /tmp/bin/spec

# Compile and run the mare binary in the `example` subdirectory.
example: PHONY
	docker exec -ti mare-dev make example.inner
/tmp/bin/mare: main.cr $(shell find src)
	mkdir -p /tmp/bin
	crystal build --debug --link-flags="-lponyrt" main.cr -o $@
example.inner: PHONY /tmp/bin/mare
	echo && cd example && /tmp/bin/mare
