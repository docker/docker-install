TEST_IMAGE?=ubuntu:18.04
VERSION?=
CHANNEL?=

VOLUME_MOUNTS=-v "$(CURDIR)":/v
SHELLCHECK_EXCLUSIONS=$(addprefix -e, SC1091 SC1117)
SHELLCHECK=docker run --rm $(VOLUME_MOUNTS) -w /v koalaman/shellcheck $(SHELLCHECK_EXCLUSIONS)

ENVSUBST_VARS=LOAD_SCRIPT_COMMIT_SHA

.PHONY: build
build: build/install.sh

build/install.sh: install.sh
	mkdir -p $(@D)
	LOAD_SCRIPT_COMMIT_SHA='$(shell git rev-parse HEAD)' envsubst '$(addprefix $$,$(ENVSUBST_VARS))' < $< > $@

.PHONY: shellcheck
shellcheck: build/install.sh
	$(SHELLCHECK) $<

.PHONY: test
test: build/install.sh
	docker run --rm -i \
		$(VOLUME_MOUNTS) \
		-w /v \
		-e VERSION \
		-e CHANNEL \
		$(TEST_IMAGE) \
		sh "$<"

.PHONY: clean
clean:
	$(RM) -r build/
