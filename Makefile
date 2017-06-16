SHELL:=/bin/bash
VERIFY_INSTALL_DISTROS:=$(addprefix verify-install-,centos-7 fedora-24 fedora-25 debian-wheezy debian-jessie debian-stretch ubuntu-trusty ubuntu-xenial ubuntu-yakkety ubuntu-zesty)
EXPECTED_VERSION?=
EXPECTED_GITCOMMIT?=

needs_version:
ifndef EXPECTED_VERSION
	$(error EXPECTED_VERSION is undefined)
endif

needs_gitcommit:
ifndef EXPECTED_GITCOMMIT
	$(error EXPECTED_GITCOMMIT is undefined)
endif

check: $(VERIFY_INSTALL_DISTROS)

clean:
	$(RM) *.log

verify-install-%.log: needs_version needs_gitcommit
	set -o pipefail && docker run \
		--rm \
		-v $(CURDIR):/v \
		-w /v \
		$(subst -,:,$*) \
		bash verify-docker-install "$(EXPECTED_VERSION)" "$(EXPECTED_GITCOMMIT)" | tee $@

# TODO: Add a target for uploading final script to s3
