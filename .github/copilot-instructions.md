# Copilot Instructions for docker-install

## Project Overview
This repository provides the canonical shell scripts for installing Docker Engine on Linux systems. The scripts are served via `get.docker.com` (stable) and `test.docker.com` (test channel) and handle OS detection, package management configuration, and daemon setup across multiple Linux distributions.

## Architecture & Key Patterns

### Multi-Channel Distribution Model
- **Channels**: `stable` (production) and `test` (pre-releases/alpha/beta)
- Scripts exist in source form (`install.sh`, `rootless-install.sh`) and are **built into channel-specific variants** in `build/` directory
- Build process uses `sed` + `envsubst` to inject channel defaults and git metadata
- Mirror support (Aliyun, AzureChinaCloud) is hardcoded in scripts for regional availability

### Linux Distribution Detection
- Primary: Read `/etc/os-release` and parse `ID` field
- Fallback: Parse `/etc/lsb-release` or `/etc/debian_version` (for Debian-like distros)
- Supports: Ubuntu, Debian, Raspbian, CentOS, Fedora, RHEL, SLES, Kylin, Alma, Rocky, etc.
- Handles forked distributions via `check_forked()` - examines `lsb_release` output
- Maps Debian version numbers (13→trixie, 12→bookworm, 11→bullseye, etc.)

### Two Installation Modes
1. **Rootful** (`install.sh`): Package-based installation via distro repos (apt/yum/zypper), requires root/sudo
2. **Rootless** (`rootless-install.sh`): Static binary installation to `$HOME/bin`, runs as unprivileged user

### Version Management
- `scripts/get-version.sh`: Queries `moby/moby` GitHub releases via `gh` CLI
  - `stable`: Uses `isLatest=true` filter
  - `test`: Uses `isPrerelease=true` filter
- Version strings: CalVer (YY.MM) or SemVer formats
- Custom `version_compare()` and `version_gte()` functions handle both formats without comparing patch/pre-release suffixes

### Dynamic Service Management
- Detects systemd availability (`systemctl` command) for daemon startup
- Enables and starts `docker.service` in systemd environments
- Gracefully degrades in container environments (no service management available)
- Prompts users about rootless mode setup only for v20.10+

## Developer Workflows

### Build Process
```bash
make build              # Generate channel-specific scripts in build/{test,stable}/
make shellcheck         # Lint all shell scripts with koalaman/shellcheck container
make test               # Run on test image (default: ubuntu:22.04)
make diff stable        # Compare built script with live get.docker.com
make deploy             # Upload to S3 (requires S3_BUCKET, CF_DISTRIBUTION_ID, CHANNEL env vars)
make clean              # Remove build/ directory
```

### Script Testing
- `verify-docker-install`: Runs built script, confirms docker CLI works, tests hello-world container (skipped if already in container)
- Custom `sh_c` command wrapper handles privilege escalation (sudo/su) or dry-run mode

### Dry-Run Mode
- Set `DRY_RUN=1` to preview commands without execution
- Useful for validating behavior before production deployment

## Critical Implementation Details

### Shell Conventions
- Strict mode: `set -e` (exit on error), plus explicit error handling
- Favor POSIX sh over bash (scripts must run in minimal containers)
- Use `command_exists()` utility function to check for tool availability
- Wrap privileged commands in `$sh_c` for sudo/su abstraction

### Distro-Specific Package Management
- **Debian/Ubuntu**: apt repo setup with GPG key verification
- **CentOS/RHEL/Fedora**: yum/dnf repo setup with signed packages
- **openSUSE/SLES**: zypper repo management
- REPO_FILE variable switches between `docker-ce.repo` (production) and `docker-ce-staging.repo` (staging URLs)

### Special Cases
- **WSL (Windows Subsystem for Linux)**: Detected via uname kernel string (`*microsoft*`), warns user to use Docker Desktop
- **Darwin/macOS**: Not supported by install script, redirects to Docker Desktop
- **Container environment**: Detected via `/.dockerenv` presence, skips daemon startup

## When Modifying Scripts

### Avoid These Pitfalls
- Don't assume bash-isms; test in POSIX sh (`dash`)
- Don't hardcode distro detection logic—use `get_distribution()` and `check_forked()`
- Changes to source scripts (`install.sh`, `rootless-install.sh`) require rebuild via `make build`
- Version function edge cases: handle both `23.0` and `23.0.0` formats

### Always Update Templates
- Edit **source** scripts (`install.sh`, `rootless-install.sh`), not built versions
- Template variables (`$LOAD_SCRIPT_*`) are injected at build time—never hardcode values
- Add new variables to `ENVSUBST_VARS` in Makefile and initialize in both source scripts

### Testing Strategy
- Run `make shellcheck` before committing (catches syntax errors)
- Test on target distros via `make test` with `TEST_IMAGE=debian:bookworm`, `fedora:latest`, etc.
- Manual smoke test: `sh install.sh --dry-run` then `sh install.sh --version 24.0`

## Integration Points
- **Upstream**: Monitors `moby/moby` releases via GitHub API (requires `gh` CLI installed)
- **Distribution**: Hosted on CDN (CloudFront) fronting S3 bucket
- **Package sources**: Official Docker repos at `download.docker.com` (or mirrors for regional deployments)
