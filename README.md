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

### Package mirrors

Use `--mirror` to select a Docker package mirror:

| Mirror | Download URL |
| --- | --- |
| `Aliyun` | `https://mirrors.aliyun.com/docker-ce` |
| `AzureChinaCloud` | `https://mirror.azure.cn/docker-ce` |
| `TencentCloud` | `https://mirrors.cloud.tencent.com/docker-ce` |

**Tencent Cloud environment:** use the `TencentCloud` preset on a Tencent Cloud
VM through its VPC private-network route. Keep the default Tencent Cloud VPC DNS
configuration and avoid external proxies for private-network validation.
According to [Tencent Cloud's software mirror documentation](https://cloud.tencent.com/document/product/213/8623),
`mirrors.cloud.tencent.com` is a unified public/private domain that preferentially
resolves to the internal route with the default VPC DNS. This is not a claim that
the domain can never be reached publicly. Public CI results are not evidence of
Tencent Cloud intranet connectivity; live validation must run in that environment.

On a fresh Tencent Cloud VM running a supported Linux distribution, review the
script and preview the installation before running it as root:

```shell
sh install.sh --mirror TencentCloud --dry-run
sudo sh install.sh --mirror TencentCloud
```

`--dry-run` only prints commands; it does not verify DNS, mirror reachability,
package availability, or installation success, even when run on a Tencent Cloud VM.

To configure the package repository without installing Docker packages:

```shell
sudo sh install.sh --mirror TencentCloud --setup-repo
```

The `DOWNLOAD_URL` environment variable remains available for custom mirrors.
For example, the following previews the same mirror selection:

```shell
sudo env DOWNLOAD_URL=https://mirrors.cloud.tencent.com/docker-ce \
  sh install.sh --dry-run
```

An explicit `--mirror` takes precedence over `DOWNLOAD_URL`. These options select
Docker package repositories, not Docker Hub registry mirrors. Mirror selection
does not change the supported distributions, and package availability depends on
the selected mirror.

## Testing:

To verify that the install script works amongst the supported operating systems run:

```shell
make shellcheck
```

### Offline mirror-option regression checks

Run on a supported Linux distribution, including ordinary GitHub-hosted runners:

```shell
sh scripts/test-mirrors.sh
```

This suite checks argument parsing and dry-run output for all mirror presets,
including `TencentCloud`. It does not contact any mirror or install packages.
Downloader, package-manager and service commands are guarded against accidental
execution. Output is labelled `PASS (offline)` and must not be reported as live
mirror validation. The separate CI job runs only these offline checks and syntax
checks; it does not add Tencent Cloud network access to the installation matrix.

### Opt-in Tencent Cloud intranet smoke check

**Run live checks only from a Tencent Cloud VM using the VPC private network.**
Check the VM's DNS and routing first; do not run this on ordinary GitHub-hosted
runners or enable it automatically for untrusted pull requests on private runners.
For example, inspect resolution from the VM:

```shell
getent ahostsv4 mirrors.cloud.tencent.com
```

The network script skips by default, before DNS lookup or any network request:

```shell
sh scripts/test-tencent-cloud-mirror.sh ubuntu resolute
# SKIP: Tencent Cloud network smoke check is disabled; no network requests made.
```

After confirming the Tencent Cloud private-network environment, explicitly enable
it. The following checks the Ubuntu 26.04 (`resolute`) repository:

```shell
TENCENT_CLOUD_INTRANET=1 \
  sh scripts/test-tencent-cloud-mirror.sh ubuntu resolute
```

The switch is an operator confirmation, not automatic cloud or route detection.
The script covers Ubuntu and Debian APT repositories; pass the target distribution
and codename, for example `debian trixie`. It downloads only the GPG key and Release
metadata to temporary files, with HTTPS verification, proxies disabled and bounded
timeouts. It neither follows redirects nor silently falls back to another endpoint.
It needs `curl`, not root privileges, and makes no package or service changes.

A disabled check reports `SKIP` and exits 0. Invalid arguments or opt-in values
exit 2. After opting in, DNS/TLS/HTTP errors, timeouts and unexpected content
fail with exit 1; they are never converted to a successful skip.

`PASS (network smoke only)` means the two endpoints returned expected content
markers. It does **not** verify cryptographic signatures, architecture/channel
package availability, package downloads, installation, or Docker service startup.
For installation acceptance, use a fresh disposable Tencent Cloud VM in the same
private-network environment, review the script, and run:

```shell
sudo sh install.sh --mirror TencentCloud
sudo docker version
sudo docker info
sudo docker compose version
```

Record the OS, architecture, commit, network environment and results separately
from the offline and smoke checks. Docker Hub access is a separate service and is
not part of this package-mirror test.

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
