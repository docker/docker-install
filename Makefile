TEST_IMAGE?=ubuntu:22.04
VERSION?=
CHANNEL?=

VOLUME_MOUNTS=-v "$(CURDIR)":/v
SHELLCHECK_EXCLUSIONS=$(addprefix -e, SC1091 SC1117 SC2317 SC2329)
SHELLCHECK=docker run --rm $(VOLUME_MOUNTS) -w /v koalaman/shellcheck:stable $(SHELLCHECK_EXCLUSIONS)

ENVSUBST_VARS=LOAD_SCRIPT_COMMIT_SHA

# Define the channels we want to build for
CHANNELS=test stable

FILES=build/test/install.sh build/stable/install.sh build/stable/rootless-install.sh

.PHONY: build
build: $(FILES)

build/%/install.sh: install.sh
	mkdir -p $(@D)
	sed 's/DEFAULT_CHANNEL_VALUE="stable"/DEFAULT_CHANNEL_VALUE="$*"/' $< | \
		LOAD_SCRIPT_COMMIT_SHA='$(shell git rev-parse HEAD)' envsubst '$(addprefix $$,$(ENVSUBST_VARS))' > $@

build/%/rootless-install.sh: rootless-install.sh
	mkdir -p $(@D)
	sed 's/DEFAULT_CHANNEL_VALUE="stable"/DEFAULT_CHANNEL_VALUE="$*"/' $< | \
		LOAD_SCRIPT_COMMIT_SHA='$(shell git rev-parse HEAD)' envsubst '$(addprefix $$,$(ENVSUBST_VARS))' > $@

.PHONY: shellcheck
shellcheck: $(FILES)
	$(SHELLCHECK) $^

.PHONY: test
test: $(foreach channel,$(CHANNELS),build/$(channel)/install.sh)
	for file in $^; do \
		(set -eux; docker run --rm -i \
			$(VOLUME_MOUNTS) \
			--privileged \
			-e HOME=/tmp \
			-v /var/lib/docker \
			-w /v \
			-e VERSION \
			-e CHANNEL \
			$(TEST_IMAGE) \
			sh $$file) || exit $$?; \
	done

AWS?=docker run \
	-v ./build:/build \
	-e AWS_ACCESS_KEY_ID \
	-e AWS_SECRET_ACCESS_KEY \
	-e AWS_SESSION_TOKEN \
	--rm amazon/aws-cli

.PHONY: deploy
deploy: build/$(CHANNEL)/install.sh build/$(CHANNEL)/rootless-install.sh
ifeq ($(S3_BUCKET),)
	$(error S3_BUCKET is empty.)
endif
ifeq ($(CF_DISTRIBUTION_ID),)
	$(error CF_DISTRIBUTION_ID is empty.)
endif
ifeq ($(CHANNEL),)
	$(error CHANNEL is empty.)
endif
	$(AWS) s3 cp --acl public-read --content-type 'text/plain' /build/$(CHANNEL)/install.sh s3://$(S3_BUCKET)/index
ifeq ($(CHANNEL),stable)
	$(AWS) s3 cp --acl public-read --content-type 'text/plain' /build/$(CHANNEL)/rootless-install.sh s3://$(S3_BUCKET)/rootless
endif

	$(AWS) cloudfront create-invalidation --distribution-id $(CF_DISTRIBUTION_ID) --paths '/*'

.PHONY: diff
diff: build/$(CHANNEL)/install.sh build/$(CHANNEL)/rootless-install.sh
ifeq ($(CHANNEL),)
	$(error CHANNEL is empty.)
endif
	./diff.sh $(CHANNEL) || true

.PHONY: clean
clean:
	$(RM) -r build/
