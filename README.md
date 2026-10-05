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

For example, on a Tencent Cloud host running a supported Linux distribution,
review the script and preview the installation before running it as root:

```shell
sh install.sh --mirror TencentCloud --dry-run
sudo sh install.sh --mirror TencentCloud
```

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

To test mirror selection on a supported Linux distribution without installing
packages or contacting the mirrors:

```shell
sh scripts/test-mirrors.sh
```

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
