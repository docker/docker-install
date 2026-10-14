#!/bin/sh
# Offline APT selection regression checks. Execute the installer's real install
# flow against package-list fixtures, recording its installation command. Platform
# detection is fixed to Ubuntu noble; every privileged command is intercepted.
# This is neither dry-run output nor a live package installation test.
set -eu

cd "$(dirname "$0")/.."
install_script=${INSTALL_SCRIPT:-./install.sh}
test_shell=$(command -v "${TEST_SHELL:-sh}")
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' 0
trap 'exit 1' HUP INT TERM
mkdir "$tmp_dir/bin"
output="$tmp_dir/output"
test_channel=stable

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	cat "$output" >&2
	[ ! -f "$tmp_dir/install-command" ] || cat "$tmp_dir/install-command" >&2
	exit 1
}

# Load the entire installer, replacing only its final invocation with fixed
# platform detection. None of the version lookup or package-list code is copied.
[ "$(tail -n 1 "$install_script")" = 'do_install' ] || fail 'unexpected installer entry point'
sed '$d' "$install_script" > "$tmp_dir/install.sh"
cat >> "$tmp_dir/install.sh" <<'PLATFORM'
get_distribution() { echo ubuntu; }
check_forked() { :; }
is_wsl() { return 1; }
command_exists() { [ "$1" = lsb_release ]; }
do_install
PLATFORM

cat > "$tmp_dir/bin/id" <<'MOCK'
#!/bin/sh
[ "$*" = '-un' ] || exit 99
echo root
MOCK
cat > "$tmp_dir/bin/lsb_release" <<'MOCK'
#!/bin/sh
[ "$*" = '--codename' ] || exit 99
printf 'Codename:\tnoble\n'
MOCK
cat > "$tmp_dir/bin/dpkg" <<'MOCK'
#!/bin/sh
[ "$*" = '--print-architecture' ] || exit 99
echo amd64
MOCK
cat > "$tmp_dir/bin/apt-cache" <<'MOCK'
#!/bin/sh
case "$*" in
	'madison docker-ce') cat "$TEST_FIXTURES/engine" ;;
	'madison docker-ce-cli') cat "$TEST_FIXTURES/cli" ;;
	*) echo "unexpected apt-cache arguments: $*" >> "$FORBIDDEN_COMMAND_LOG"; exit 99 ;;
esac
MOCK
# Intercept sh -c before commands or redirects can change the host. Only package
# lookups run through a real shell, with apt-cache replaced by the fixture reader.
cat > "$tmp_dir/bin/sh" <<'MOCK'
#!/bin/sh
if [ "$#" = 2 ] && [ "$1" = '-c' ]; then
	case "$2" in
		'apt-cache madison docker-ce'|'apt-cache madison docker-ce | '*|\
		'apt-cache madison docker-ce-cli'|'apt-cache madison docker-ce-cli | '*)
			exec /bin/sh "$@"
			;;
		'DEBIAN_FRONTEND=noninteractive apt-get -y -qq --allow-downgrades install docker-ce='*|\
		'DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=60 -y -qq --allow-downgrades install docker-ce='*)
			printf '%s\n' "$2" >> "$INSTALL_COMMAND_LOG"
			exit 0
			;;
		'apt-get -qq update >/dev/null'|\
		'DEBIAN_FRONTEND=noninteractive apt-get -y -qq install ca-certificates curl >/dev/null'|\
		'DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=60 -y -qq install ca-certificates curl >/dev/null'|\
		'install -m 0755 -d /etc/apt/keyrings'|\
		'curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" -o /etc/apt/keyrings/docker.asc'|\
		'chmod a+r /etc/apt/keyrings/docker.asc'|\
		'echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list'|\
		'echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble test" > /etc/apt/sources.list.d/docker.list')
			exit 0
			;;
	esac
fi
printf 'unexpected sh command: %s\n' "$*" >> "$FORBIDDEN_COMMAND_LOG"
exit 99
MOCK
cat > "$tmp_dir/bin/guard" <<'MOCK'
#!/bin/sh
printf 'unexpected command: %s %s\n' "${0##*/}" "$*" >> "$FORBIDDEN_COMMAND_LOG"
exit 99
MOCK
chmod +x "$tmp_dir/bin/"*
for tool in curl wget apt-get dnf dnf5 yum yum-config-manager systemctl sudo su docker install chmod; do
	ln -s guard "$tmp_dir/bin/$tool"
done

fixture() {
	: > "$tmp_dir/engine"
	for version in "$@"; do
		# Include both normal spaces and tabs around fields, as madison can use
		# either; distro metadata contains the known false-positive version.
		printf ' docker-ce\t|  %s \t| https://download.docker.com/linux/ubuntu noble/stable amd64 Packages\n' "$version" >> "$tmp_dir/engine"
	done
	cp "$tmp_dir/engine" "$tmp_dir/cli"
}

run() {
	status=0
	: > "$tmp_dir/forbidden"
	: > "$tmp_dir/install-command"
	env -i PATH="$tmp_dir/bin:$PATH" HOME="${HOME:-/tmp}" \
		TEST_FIXTURES="$tmp_dir" FORBIDDEN_COMMAND_LOG="$tmp_dir/forbidden" \
		INSTALL_COMMAND_LOG="$tmp_dir/install-command" \
		"$test_shell" "$tmp_dir/install.sh" --version "$1" --channel "$test_channel" --no-autostart > "$output" 2>&1 || status=$?
	[ ! -s "$tmp_dir/forbidden" ] || fail 'installer executed an unexpected command'
}

expect_version() {
	requested=$1
	expected=$2
	expected_cli=${3:-$expected}
	run "$requested"
	[ "$status" -eq 0 ] || fail "version $requested exited with $status"
	[ "$(wc -l < "$tmp_dir/install-command" | tr -d ' ')" -eq 1 ] || fail 'expected one package installation command'
	grep -F -- " install docker-ce=$expected " "$tmp_dir/install-command" > /dev/null || fail "version $requested selected the wrong Engine package"
	# Legacy releases did not provide a separate CLI package.
	case "$requested" in
		17.*)
			if grep -F -- 'docker-ce-cli' "$tmp_dir/install-command" > /dev/null; then
				fail 'legacy version unexpectedly installs a separate CLI package'
			fi
			;;
		*)
			grep -F -- " docker-ce-cli=$expected_cli " "$tmp_dir/install-command" > /dev/null || fail "version $requested selected the wrong CLI package"
			;;
	esac
	printf 'PASS (offline): %s selects %s\n' "$requested" "$expected"
}

expect_missing() {
	run "$1"
	[ "$status" -eq 1 ] || fail "unavailable version $1 should exit with status 1"
	grep -F -- "ERROR: '$1' not found amongst apt-cache madison results" "$output" > /dev/null || fail "missing error for version $1"
	[ ! -s "$tmp_dir/install-command" ] || fail 'unavailable version must not install packages'
	printf 'PASS (offline): unavailable %s fails before installation\n' "$1"
}

fixture '5:28.4.0-1~ubuntu.24.04~noble' '5:24.0.9-1~ubuntu.24.04~noble'
expect_version 24.0 '5:24.0.9-1~ubuntu.24.04~noble'

fixture '5:24.0.10-1~ubuntu.24.04~noble' '5:24.0.1-1~ubuntu.24.04~noble'
expect_version 24.0.1 '5:24.0.1-1~ubuntu.24.04~noble'

fixture '5:22.02.1-1~ubuntu.24.04~noble' '5:22.0.1-1~ubuntu.24.04~noble'
expect_version 22.0 '5:22.0.1-1~ubuntu.24.04~noble'

fixture '5:24x0x1-1~ubuntu.24.04~noble' '5:24.0.1-1~ubuntu.24.04~noble'
expect_version 24.0.1 '5:24.0.1-1~ubuntu.24.04~noble'

# Check CLI independently: an Engine-only fix must still fail this fixture.
fixture '5:24.0.1-1~ubuntu.24.04~noble'
printf '%s\n' 'docker-ce-cli | 5:28.4.0-1~ubuntu.24.04~noble | noble/stable' > "$tmp_dir/cli"
cat "$tmp_dir/engine" >> "$tmp_dir/cli"
expect_version 24.0.1 '5:24.0.1-1~ubuntu.24.04~noble'

fixture '5:24.0.1-1~ubuntu.24.04~noble'
printf '%s\n' 'docker-ce-cli | 5:24.0.10-1~ubuntu.24.04~noble | noble/stable' > "$tmp_dir/cli"
cat "$tmp_dir/engine" >> "$tmp_dir/cli"
expect_version 24.0.1 '5:24.0.1-1~ubuntu.24.04~noble'

fixture '24.0.1-1~ubuntu.24.04~noble'
expect_version 24.0.1 '24.0.1-1~ubuntu.24.04~noble'
fixture '2:24.0.1-1~ubuntu.24.04~noble'
expect_version 24.0.1 '2:24.0.1-1~ubuntu.24.04~noble'
fixture '5:24.1.7-1~ubuntu.24.04~noble' '5:24.0.9-1~ubuntu.24.04~noble'
expect_version 24 '5:24.1.7-1~ubuntu.24.04~noble'
fixture '5:24.0.9-1~ubuntu.24.04~noble' '5:24.0.1-1~ubuntu.24.04~noble'
expect_version 24.0 '5:24.0.9-1~ubuntu.24.04~noble'
expect_version v24.0.1 '5:24.0.1-1~ubuntu.24.04~noble'

fixture '17.03.2~ce-0~ubuntu-xenial'
expect_version 17.03 '17.03.2~ce-0~ubuntu-xenial'
expect_version 17.03.2-ce '17.03.2~ce-0~ubuntu-xenial'
test_channel='test'
fixture '17.12.0~ce~rc10-0~ubuntu' '17.12.0~ce~rc1-0~ubuntu'
expect_version 17.12.0-ce-rc1 '17.12.0~ce~rc1-0~ubuntu'

fixture '5:29.0.0~rc.10-1~ubuntu.24.04~noble' '5:29.0.0~rc.1-1~ubuntu.24.04~noble'
expect_version 29.0.0-rc.1 '5:29.0.0~rc.1-1~ubuntu.24.04~noble'
expect_version 29.0.0~rc.1 '5:29.0.0~rc.1-1~ubuntu.24.04~noble'
fixture '5:29.0.0~alpha.1-1~ubuntu.24.04~noble'
expect_version 29.0.0-alpha.1 '5:29.0.0~alpha.1-1~ubuntu.24.04~noble'

test_channel=stable
fixture '5:28.4.0-1~ubuntu.24.04~noble'
expect_missing 24.0
fixture '5:24.0.10-1~ubuntu.24.04~noble'
expect_missing 24.0.1
fixture '5:22.02.1-1~ubuntu.24.04~noble'
expect_missing 22.0
test_channel='test'
fixture '5:29.0.0~rc.10-1~ubuntu.24.04~noble'
expect_missing 29.0.0-rc.1
test_channel=stable
fixture '5:24.01-1~ubuntu.24.04~noble'
expect_missing '24.0[1]'
# VERSION is never interpolated into the privileged shell command.
expect_missing "24.0'; echo unexpected; #"

# grep treats embedded newlines as separate expressions. A later fragment must
# not match distribution metadata and broaden the requested version.
fixture '5:29.4.0-1~ubuntu.24.04~noble'
expect_missing 'bogus
24'

echo 'Offline APT selection checks complete. Repository availability and real installation were NOT tested.'
