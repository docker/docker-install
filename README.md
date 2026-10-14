# docker/docker-install
Home of the script that lives at `get.docker.com` and `test.docker.com`!

The purpose of the install script is for a convenience for quickly
installing the latest Docker-CE releases on the supported linux
distros. It is not recommended to depend on this script for deployment
to production systems. For more thorough instructions for installing
on the supported distros, see the [install
instructions](https://docs.docker.com/engine/install/).

This repository is solely maintained by Docker, Inc.

## Usage:

From `https://get.docker.com`:
```shell
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh
```

From `https://test.docker.com`:
```shell
curl -fsSL https://test.docker.com -o test-docker.sh
sh test-docker.sh
rm test-docker.sh
```

From the source repo (This will install latest from the `stable` channel):
```shell
sh install.sh
```

## Testing:

To verify that the install script works amongst the supported operating systems run:

```shell
make shellcheck
```

### APT dpkg lock waiting

APT prerequisite and Engine installations, and the rootless installer's suggested
`uidmap`/`iptables` installation commands, use `DPkg::Lock::Timeout=60`. On APT
1.9.11 and later, this bounds waiting for the dpkg frontend and administration
locks to 60 seconds; contention that outlasts the timeout still fails. Older APT
versions do not provide this waiting behavior. This is a lock-acquisition timeout,
not a timeout for the full installation. See the [APT implementation history](https://bugs.debian.org/864681).

The option does not cover the lists lock used by `apt-get update`; those commands
retain their existing behavior. See the [APT lists-lock report](https://bugs.debian.org/1069167).

Run the command-generation regression checks without installing packages:

```shell
python3 scripts/test-apt-lock-wait.py
```

The dedicated CI job also checks real `fcntl` locks in disposable Ubuntu 22.04,
Ubuntu 24.04, and Debian 12 containers. To run the same live checks locally:

```shell
docker run --rm -v "$PWD:/v:ro" -w /v \
  -e DOCKER_INSTALL_LOCK_TEST_CONTAINER=1 ubuntu:24.04 sh -ec '
    apt-get -qq update
    DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=60 -y -qq install --no-install-recommends python3 >/dev/null
    python3 scripts/test-apt-lock-wait.py --live
  '
```

Live checks include a real 60-second timeout; total runtime also depends on APT
processing and the container runtime. They verify a
fail-fast control, successful waiting after lock release, a real 60-second
timeout, CLI precedence over a zero-second configuration default, and the lists
lock limitation. They pin the already-installed `bash` version with downloads
disabled; they do not install Docker or validate package/service compatibility.

## Legal
*Brought to you courtesy of our legal counsel. For more context,
please see the [NOTICE](NOTICE) document in this repo.*

Use and transfer of Docker may be subject to certain restrictions by the
United States and other governments.

It is your responsibility to ensure that your use and/or transfer does not
violate applicable laws.

For more information, please see https://www.bis.doc.gov

## Reporting security issues

The maintainers take security seriously. If you discover a security issue,
please bring it to their attention right away!

Please **DO NOT** file a public issue, instead send your report privately to
[security@docker.com](mailto:security@docker.com).

Security reports are greatly appreciated and we will publicly thank you for it.
We also like to send gifts—if you're into Docker schwag, make sure to let
us know. We currently do not offer a paid security bounty program, but are not
ruling it out in the future.

## Licensing

docker/docker-install is licensed under the Apache License, Version 2.0.
See [LICENSE](LICENSE) for the full license text.

## Contributing

Make sure you have read and understood our [contributing
guidelines](https://github.com/docker/cli/blob/master/CONTRIBUTING.md).

**Make sure all your commits are signed off and include a signature generated
with `git commit -s`.**
