#!/bin/sh
# Offline mirror-option/dry-run regression checks, not mirror availability tests.
# TencentCloud must stay covered here even on non-Tencent CI runners: these
# assertions never contact a mirror. See test-tencent-cloud-mirror.sh for the
# separate, opt-in smoke check that requires Tencent Cloud's private network.
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

# Fail if dry-run accidentally invokes a downloader, package manager or service
# command. Preserve command-existence detection by only shadowing installed tools.
for tool in curl wget apt-get apt-cache dnf dnf5 yum yum-config-manager systemctl sudo su docker; do
	command -v "$tool" > /dev/null 2>&1 || continue
	cat > "$tmp_dir/bin/$tool" <<-'GUARD'
		#!/bin/sh
		printf '%s\n' "${0##*/}" >> "$FORBIDDEN_COMMAND_LOG"
		echo "ERROR: ${0##*/} must not execute in an offline test." >&2
		exit 99
	GUARD
	chmod +x "$tmp_dir/bin/$tool"
done
output="$tmp_dir/output"
download_url=''
network_test=''

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	cat "$output" >&2
	exit 1
}

run_script() {
	status=0
	: > "$tmp_dir/forbidden"
	# Discard inherited installer options and any network-test opt-in.
	env -i PATH="$tmp_dir/bin:$PATH" HOME="${HOME:-/tmp}" \
		DOWNLOAD_URL="$download_url" TENCENT_CLOUD_INTRANET="$network_test" \
		FORBIDDEN_COMMAND_LOG="$tmp_dir/forbidden" \
		"$test_shell" "$@" > "$output" 2>&1 || status=$?
	[ ! -s "$tmp_dir/forbidden" ] || fail 'offline test executed a forbidden command'
	return "$status"
}

run() {
	run_script ./install.sh --dry-run "$@"
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
echo 'PASS (offline): default download URL'

for mirror in Aliyun AzureChinaCloud TencentCloud; do
	case "$mirror" in
		Aliyun) url='https://mirrors.aliyun.com/docker-ce' ;;
		AzureChinaCloud) url='https://mirror.azure.cn/docker-ce' ;;
		TencentCloud) url='https://mirrors.cloud.tencent.com/docker-ce' ;;
	esac
	run --mirror "$mirror" || fail "$mirror"
	contains "$url/linux/"
	excludes 'https://download.docker.com/linux/'
	echo "PASS (offline): $mirror option selects expected URL"
done
cp "$output" "$tmp_dir/tencent-cloud"

download_url='https://mirrors.cloud.tencent.com/docker-ce'
run || fail 'DOWNLOAD_URL compatibility'
cmp -s "$output" "$tmp_dir/tencent-cloud" || fail 'mirror and DOWNLOAD_URL differ'
echo 'PASS (offline): TencentCloud matches DOWNLOAD_URL'

download_url='https://example.com/docker-ce'
run || fail 'custom DOWNLOAD_URL'
contains "$download_url/linux/"
echo 'PASS (offline): custom DOWNLOAD_URL'

run --mirror TencentCloud || fail 'mirror precedence'
contains 'https://mirrors.cloud.tencent.com/docker-ce/linux/'
excludes "$download_url"
echo 'PASS (offline): --mirror overrides DOWNLOAD_URL'
download_url=''

run --mirror TencentCloud --channel test || fail 'test channel'
contains 'https://mirrors.cloud.tencent.com/docker-ce/linux/'
grep -E ' test"|docker-ce-test' "$output" > /dev/null || fail 'test channel missing'
echo 'PASS (offline): test channel argument (not package availability)'

run --mirror TencentCloud --setup-repo || fail 'repository-only mode'
contains 'https://mirrors.cloud.tencent.com/docker-ce/linux/'
excludes ' install docker-ce'
excludes 'systemctl enable --now docker.service'
echo 'PASS (offline): repository-only mode'

run --mirror TencentCloud --no-autostart || fail 'no-autostart mode'
contains ' install docker-ce'
excludes 'systemctl enable --now docker.service'
echo 'PASS (offline): no-autostart mode'

run --mirror TencentCloud --version 27.5 || fail 'version option'
contains 'VERSION pinning is not supported in DRY_RUN'
contains 'https://mirrors.cloud.tencent.com/docker-ce/linux/'
echo 'PASS (offline): version option (not version availability)'

run --help || fail 'help output'
contains '--mirror <Aliyun|AzureChinaCloud|TencentCloud>'
echo 'PASS (offline): help lists TencentCloud'

status=0
run --mirror UnknownMirror || status=$?
[ "$status" -eq 1 ] || fail 'unknown mirror should exit with status 1'
contains "unknown mirror 'UnknownMirror'"
contains "'Aliyun', 'AzureChinaCloud', or 'TencentCloud'"
echo 'PASS (offline): unknown mirror is rejected'

# Test only the network check's entry guards here, never its live requests.
run_script ./scripts/test-tencent-cloud-mirror.sh ubuntu resolute || fail 'network check default'
contains 'SKIP:'
contains 'Tencent Cloud private network'
excludes 'PASS'
echo 'PASS (offline): network smoke check is skipped by default'

network_test=yes
status=0
run_script ./scripts/test-tencent-cloud-mirror.sh ubuntu resolute || status=$?
[ "$status" -eq 2 ] || fail 'invalid opt-in must fail before network access'
contains 'must be 0 or 1'
echo 'PASS (offline): invalid network opt-in is rejected'

network_test=1
status=0
run_script ./scripts/test-tencent-cloud-mirror.sh || status=$?
[ "$status" -eq 2 ] || fail 'missing network-check arguments must be rejected'
contains 'Usage:'
echo 'PASS (offline): missing network-check arguments are rejected'

status=0
run_script ./scripts/test-tencent-cloud-mirror.sh centos 9 || status=$?
[ "$status" -eq 2 ] || fail 'unsupported smoke-check repository must be rejected'
contains 'Ubuntu and Debian APT repositories only'
echo 'PASS (offline): unsupported smoke-check repository is rejected'

status=0
run_script ./scripts/test-tencent-cloud-mirror.sh ubuntu '../resolute' || status=$?
[ "$status" -eq 2 ] || fail 'invalid repository codename must be rejected'
contains 'lowercase letters and digits'
echo 'PASS (offline): invalid repository codename is rejected'

echo 'Offline checks complete. Tencent Cloud intranet connectivity and installation were NOT tested.'
