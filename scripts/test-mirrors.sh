#!/bin/sh
# Exercise mirror selection without installing packages or accessing mirrors.
# Run on a supported Linux distribution with sh scripts/test-mirrors.sh.
set -eu

cd "$(dirname "$0")/.."
test_shell=${TEST_SHELL:-sh}
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' 0
trap 'exit 1' HUP INT TERM

# Avoid the existing-installation warning delay on CI hosts with Docker installed.
mkdir "$tmp_dir/bin"
printf '#!/bin/sh\nexit 0\n' > "$tmp_dir/bin/sleep"
chmod +x "$tmp_dir/bin/sleep"
output="$tmp_dir/output"
download_url=''

run() {
	env -i PATH="$tmp_dir/bin:$PATH" HOME="${HOME:-/tmp}" \
		DOWNLOAD_URL="$download_url" \
		"$test_shell" ./install.sh --dry-run "$@" > "$output" 2>&1
}

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	cat "$output" >&2
	exit 1
}

contains() {
	grep -F -- "$1" "$output" > /dev/null || fail "missing: $1"
}

excludes() {
	if grep -F -- "$1" "$output" > /dev/null; then
		fail "unexpected: $1"
	fi
}

run || fail 'default download URL'
contains 'https://download.docker.com/linux/'
echo 'PASS: default download URL'

for mirror in Aliyun AzureChinaCloud TencentCloud; do
	case "$mirror" in
		Aliyun) url='https://mirrors.aliyun.com/docker-ce' ;;
		AzureChinaCloud) url='https://mirror.azure.cn/docker-ce' ;;
		TencentCloud) url='https://mirrors.cloud.tencent.com/docker-ce' ;;
	esac
	run --mirror "$mirror" || fail "$mirror"
	contains "$url/linux/"
	excludes 'https://download.docker.com/linux/'
	echo "PASS: $mirror"
done
cp "$output" "$tmp_dir/tencent-cloud"

download_url='https://mirrors.cloud.tencent.com/docker-ce'
run || fail 'DOWNLOAD_URL compatibility'
cmp -s "$output" "$tmp_dir/tencent-cloud" || fail 'mirror and DOWNLOAD_URL differ'
echo 'PASS: TencentCloud matches DOWNLOAD_URL'

download_url='https://example.com/docker-ce'
run || fail 'custom DOWNLOAD_URL'
contains "$download_url/linux/"
echo 'PASS: custom DOWNLOAD_URL'

run --mirror TencentCloud || fail 'mirror precedence'
contains 'https://mirrors.cloud.tencent.com/docker-ce/linux/'
excludes "$download_url"
echo 'PASS: --mirror overrides DOWNLOAD_URL'
download_url=''

run --mirror TencentCloud --channel test || fail 'test channel'
contains 'https://mirrors.cloud.tencent.com/docker-ce/linux/'
grep -E ' test"|docker-ce-test' "$output" > /dev/null || fail 'test channel missing'
echo 'PASS: test channel'

run --mirror TencentCloud --setup-repo || fail 'repository-only mode'
contains 'https://mirrors.cloud.tencent.com/docker-ce/linux/'
excludes ' install docker-ce'
excludes 'systemctl enable --now docker.service'
echo 'PASS: repository-only mode'

run --mirror TencentCloud --no-autostart || fail 'no-autostart mode'
contains ' install docker-ce'
excludes 'systemctl enable --now docker.service'
echo 'PASS: no-autostart mode'

run --mirror TencentCloud --version 27.5 || fail 'version option'
contains 'VERSION pinning is not supported in DRY_RUN'
contains 'https://mirrors.cloud.tencent.com/docker-ce/linux/'
echo 'PASS: version option'

run --help || fail 'help output'
contains '--mirror <Aliyun|AzureChinaCloud|TencentCloud>'
echo 'PASS: help lists TencentCloud'

status=0
run --mirror UnknownMirror || status=$?
[ "$status" -eq 1 ] || fail 'unknown mirror should exit with status 1'
contains "unknown mirror 'UnknownMirror'"
contains "'Aliyun', 'AzureChinaCloud', or 'TencentCloud'"
echo 'PASS: unknown mirror is rejected'
