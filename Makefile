SHELL:=/bin/bash
VERIFY_INSTALL_DISTROS:=$(addprefix verify-install-,centos-7 fedora-24 fedora-25 debian-wheezy debian-jessie debian-stretch ubuntu-trusty ubuntu-xenial ubuntu-yakkety ubuntu-zesty)
CHANNEL_TO_TEST?=test
EXPECTED_VERSION?=
EXPECTED_GITCOMMIT?=

.PHONY: needs_version
needs_version:
ifndef EXPECTED_VERSION
	$(error EXPECTED_VERSION is undefined)
endif

.PHONY: needs_gitcommit
needs_gitcommit:
ifndef EXPECTED_GITCOMMIT
	$(error EXPECTED_GITCOMMIT is undefined)
endif

.PHONY: check
check: $(VERIFY_INSTALL_DISTROS)

.PHONY: clean
clean:
	$(RM) *.log

verify-install-%.log: needs_version needs_gitcommit
	mkdir -p build
	sed 's/DEFAULT_CHANNEL_VALUE="test"/DEFAULT_CHANNEL_VALUE="$(CHANNEL_TO_TEST)"/' install.sh > build/install.sh
	set -o pipefail && docker run \
		--rm \
		-v $(CURDIR):/v \
		-w /v \
		$(subst -,:,$*) \
		/v/verify-docker-install "$(EXPECTED_VERSION)" "$(EXPECTED_GITCOMMIT)" | tee $@
