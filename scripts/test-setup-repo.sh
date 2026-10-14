#!/bin/sh
# Exercise the real option parser without entering the installation code.
# In particular, a broken --setup-repo must never turn this test into an install.
set -eu

cd "$(dirname "$0")/.."
test_shell=${TEST_SHELL:-sh}
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' 0
trap 'exit 1' HUP INT TERM

# Keep the argument parser and mirror/channel validation verbatim. Stop before
# function definitions and do_install, so even a swallowed --dry-run is harmless.
# Fail closed if the boundary changes instead of executing the complete script.
awk '
	/^command_exists\(\) \{$/ { found = 1; exit }
	{ print }
	END { if (!found) exit 1 }
' install.sh > "$tmp_dir/parser.sh"
cat >> "$tmp_dir/parser.sh" <<'PROBE'
printf 'REPO_ONLY=%s\nDRY_RUN=%s\nNO_AUTOSTART=%s\nCHANNEL=%s\nVERSION=%s\nDOWNLOAD_URL=%s\n' \
	"$REPO_ONLY" "$DRY_RUN" "$NO_AUTOSTART" "$CHANNEL" "$VERSION" "$DOWNLOAD_URL"
PROBE

output="$tmp_dir/output"
dry_run=''
count=0

fail() {
	printf 'FAIL (offline): %s\n' "$1" >&2
	cat "$output" >&2
	exit 1
}

run() {
	expected_status=$1
	shift
	status=0
	env -i PATH="$PATH" HOME="${HOME:-/tmp}" DRY_RUN="$dry_run" \
		"$test_shell" "$tmp_dir/parser.sh" "$@" > "$output" 2>&1 || status=$?
	[ "$status" -eq "$expected_status" ] || fail "expected status $expected_status, got $status"
}

contains() {
	grep -F -- "$1" "$output" > /dev/null || fail "missing: $1"
}

equals() {
	grep -Fx -- "$1" "$output" > /dev/null || fail "missing exact value: $1"
}

pass() {
	count=$((count + 1))
	printf 'PASS (offline): %s\n' "$1"
}

run 0
equals 'REPO_ONLY=0'
equals 'DRY_RUN='
pass 'defaults'

run 0 --setup-repo
equals 'REPO_ONLY=1'
pass '--setup-repo as the only argument'

run 0 --setup-repo --dry-run
equals 'REPO_ONLY=1'
equals 'DRY_RUN=1'
pass '--setup-repo preserves following --dry-run'

run 0 --dry-run --setup-repo
equals 'REPO_ONLY=1'
equals 'DRY_RUN=1'
pass '--setup-repo as the last argument'

run 0 --setup-repo --mirror Aliyun
equals 'REPO_ONLY=1'
equals 'DOWNLOAD_URL=https://mirrors.aliyun.com/docker-ce'
pass '--setup-repo preserves following --mirror and value'

run 0 --mirror Aliyun --setup-repo
equals 'REPO_ONLY=1'
equals 'DOWNLOAD_URL=https://mirrors.aliyun.com/docker-ce'
pass 'mirror before --setup-repo'

run 0 --setup-repo --channel test
equals 'REPO_ONLY=1'
equals 'CHANNEL=test'
pass '--setup-repo preserves following --channel and value'

run 0 --setup-repo --version v27.5
equals 'REPO_ONLY=1'
equals 'VERSION=27.5'
pass '--setup-repo preserves following --version and value'

run 0 --setup-repo --no-autostart
equals 'REPO_ONLY=1'
equals 'NO_AUTOSTART=1'
pass '--setup-repo preserves following --no-autostart'

run 0 --setup-repo --help
contains 'USAGE:'
if grep -F 'REPO_ONLY=' "$output" > /dev/null; then
	fail '--help must exit before the parser probe'
fi
pass '--setup-repo preserves following --help'

run 1 --setup-repo --unknown-option
contains 'Illegal option --unknown-option'
pass '--setup-repo does not hide an invalid option'

run 0 --setup-repo --setup-repo --dry-run
equals 'REPO_ONLY=1'
equals 'DRY_RUN=1'
pass 'repeated --setup-repo remains idempotent'

run 0 --setup-repo --dry-run --mirror Aliyun --channel test --version v27.5 --no-autostart
equals 'REPO_ONLY=1'
equals 'DRY_RUN=1'
equals 'DOWNLOAD_URL=https://mirrors.aliyun.com/docker-ce'
equals 'CHANNEL=test'
equals 'VERSION=27.5'
equals 'NO_AUTOSTART=1'
pass 'all options after --setup-repo'

run 0 --dry-run --mirror Aliyun --channel test --version v27.5 --no-autostart --setup-repo
equals 'REPO_ONLY=1'
equals 'DRY_RUN=1'
equals 'DOWNLOAD_URL=https://mirrors.aliyun.com/docker-ce'
equals 'CHANNEL=test'
equals 'VERSION=27.5'
equals 'NO_AUTOSTART=1'
pass 'all options before --setup-repo'

dry_run=1
run 0 --setup-repo
equals 'REPO_ONLY=1'
equals 'DRY_RUN=1'
pass 'DRY_RUN environment variable remains supported'
dry_run=''

run 1 --setup-repo --mirror UnknownMirror
contains "unknown mirror 'UnknownMirror'"
pass '--setup-repo does not hide mirror validation'

run 1 --setup-repo --channel invalid
contains "unknown CHANNEL 'invalid'"
pass '--setup-repo does not hide channel validation'

printf '%s offline parser scenarios passed; no network or installation was attempted.\n' "$count"
