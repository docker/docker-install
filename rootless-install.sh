#!/bin/sh

# This script is meant for quick & easy install via:
#   $ curl -fsSL https://get.docker.com/rootless -o get-docker.sh
#   $ sh get-docker.sh
#
# NOTE: Make sure to verify the contents of the script
#       you downloaded matches the contents of install.sh
#       located at https://github.com/docker/docker-install
#       before executing.
#
# Git commit from https://github.com/docker/docker-install when
# the script was uploaded (Should only be modified by upload job):
SCRIPT_COMMIT_SHA=UNKNOWN

# This script should be run with an unprivileged user and install/setup Docker under $HOME/bin/.

set -e

init_vars() {
	BIN="$HOME/bin"
	DAEMON=dockerd
	SYSTEMD=
	if systemctl --user daemon-reload >/dev/null 2>&1; then
		SYSTEMD=1
	fi
}

checks() {
	# OS verification: Linux only, point osx/win to helpful locations
	case "$(uname)" in
	Linux)
		;;
	*)
		>&2 echo "Rootless Docker cannot be installed on $(uname)"; exit 1
		;;
	esac

	# User verification: deny running as root (unless forced?)
	if [ "$(id -u)" = "0" ] && [ -z "$FORCE_ROOTLESS_INSTALL" ]; then
		>&2 echo "Refusing to install rootless Docker as the root user"; exit 1
	fi

	# HOME verification
	if [ ! -d "$HOME" ]; then
		>&2 echo "Aborting because HOME directory $HOME does not exist"; exit 1
	fi

	if [ -d "$BIN" ]; then
		if [ ! -w "$BIN" ]; then
			>&2 echo "Aborting because $BIN is not writable"; exit 1
		fi
	else
		if [ ! -w "$HOME" ]; then
			>&2 echo "Aborting because HOME (\"$HOME\") is not writable"; exit 1
		fi
	fi

	# Existing rootful docker verification
	if [ -w /var/run/docker.sock ] && [ -z "$FORCE_ROOTLESS_INSTALL" ]; then
		>&2 echo "Aborting because rootful Docker is running and accessible. Set FORCE_ROOTLESS_INSTALL=1 to ignore."; exit 1
	fi

	# Validate XDG_RUNTIME_DIR
	if [ ! -w "$XDG_RUNTIME_DIR" ]; then
		if [ -n "$SYSTEMD" ]; then
			>&2 echo "Aborting because systemd was detected but XDG_RUNTIME_DIR (\"$XDG_RUNTIME_DIR\") does not exist or is not writable"
			>&2 echo "Hint: this could happen if you changed users with 'su' or 'sudo'. To work around this:"
			>&2 echo "- try again by first running with root privileges 'loginctl enable-linger <user>' where <user> is the unprivileged user and export XDG_RUNTIME_DIR to the value of RuntimePath as shown by 'loginctl show-user <user>'"
			>&2 echo "- or simply log back in as the desired unprivileged user (ssh works for remote machines)"
			exit 1
		fi
		export XDG_RUNTIME_DIR="/tmp/docker-$(id -u)"
		mkdir -p "$XDG_RUNTIME_DIR"
		XDG_RUNTIME_DIR_CREATED=1
	fi

	# Already installed verification (unless force?). Only having docker cli binary previously shouldn't fail the build.
	if [ -x "$BIN/$DAEMON" ]; then
		# If rootless installation is detected print out the modified PATH and DOCKER_HOST that needs to be set.
		echo "# Existing rootless Docker detected at $BIN/$DAEMON"
		print_instructions
		exit 0
	fi

	INSTRUCTIONS=

	# uidmap dependency check
	if ! which newuidmap >/dev/null 2>&1; then
		if which apt-get >/dev/null 2>&1; then
			INSTRUCTIONS="apt-get install -y uidmap"
		elif which dnf >/dev/null 2>&1; then
			INSTRUCTIONS="dnf install -y shadow-utils"
		elif which yum >/dev/null 2>&1; then
			INSTRUCTIONS="curl -o /etc/yum.repos.d/vbatts-shadow-utils-newxidmap-epel-7.repo https://copr.fedorainfracloud.org/coprs/vbatts/shadow-utils-newxidmap/repo/epel-7/vbatts-shadow-utils-newxidmap-epel-7.repo
yum install -y shadow-utils46-newxidmap"
		else
			echo "newuidmap binary not found. Please install with a package manager."
			exit 1
		fi
	fi

	# iptables dependency check
	if [ -z "$SKIP_IPTABLES" ] && ! which iptables >/dev/null 2>&1 && [ ! -f /sbin/iptables ] && [ ! -f /usr/sbin/iptables ]; then
		if which apt-get >/dev/null 2>&1; then
			INSTRUCTIONS="${INSTRUCTIONS}
apt-get install -y iptables"
		elif which dnf >/dev/null 2>&1; then
			INSTRUCTIONS="${INSTRUCTIONS}
dnf install -y iptables"
		else
			echo "iptables binary not found. Please install with a package manager."
			exit 1
		fi
	fi

	# ip_tables module dependency check
	if [ -z "$SKIP_IPTABLES" ] && ! lsmod | grep ip_tables >/dev/null 2>&1 && ! cat /lib/modules/$(uname -r)/modules.builtin | grep ip_tables >/dev/null 2>&1; then
			INSTRUCTIONS="${INSTRUCTIONS}
modprobe ip_tables"
	fi

	# debian requires setting unprivileged_userns_clone
	if [ -f /proc/sys/kernel/unprivileged_userns_clone ]; then
		if [ "1" != "$(cat /proc/sys/kernel/unprivileged_userns_clone)" ]; then
			INSTRUCTIONS="${INSTRUCTIONS}
cat <<EOT > /etc/sysctl.d/50-rootless.conf
kernel.unprivileged_userns_clone = 1
EOT
sysctl --system"
		fi
	fi

	# centos requires setting max_user_namespaces
	if [ -f /proc/sys/user/max_user_namespaces ]; then
		if [ "0" = "$(cat /proc/sys/user/max_user_namespaces)" ]; then
			INSTRUCTIONS="${INSTRUCTIONS}
cat <<EOT > /etc/sysctl.d/51-rootless.conf
user.max_user_namespaces = 28633
EOT
sysctl --system"
		fi
	fi

	if [ -n "$INSTRUCTIONS" ]; then
		echo "# Missing system requirements. Please run following commands to
# install the requirements and run this installer again.
# Alternatively iptables checks can be disabled with SKIP_IPTABLES=1"

		echo
		echo "cat <<EOF | sudo sh -x"
		echo "$INSTRUCTIONS"
		echo "EOF"
		echo
		exit 1
	fi

	# validate subuid/subgid files for current user
	if ! grep "^$(id -un):\|^$(id -u):" /etc/subuid >/dev/null 2>&1; then
		>&2 echo "Could not find records for the current user $(id -un) from /etc/subuid . Please make sure valid subuid range is set there.
For example:
echo \"$(id -un):100000:65536\" >> /etc/subuid"
		exit 1
	fi
	if ! grep "^$(id -un):\|^$(id -u):" /etc/subgid >/dev/null 2>&1; then
		>&2 echo "Could not find records for the current user $(id -un) from /etc/subgid . Please make sure valid subuid range is set there.
For example:
echo \"$(id -un):100000:65536\" >> /etc/subgid"
		exit 1
	fi
}

start_docker() {
	# detect if overlay is supported (ubuntu)
	tmpdir=$(mktemp -d)
	mkdir -p $tmpdir/lower $tmpdir/upper $tmpdir/work $tmpdir/merged
	if "$BIN"/rootlesskit mount -t overlay overlay -olowerdir=$tmpdir/lower,upperdir=$tmpdir/upper,workdir=$tmpdir/work $tmpdir/merged >/dev/null 2>&1; then
		USE_OVERLAY=1
	fi
	rm -rf "$tmpdir"

	if [ -z "$SYSTEMD" ]; then
		start_docker_nonsystemd
		return
	fi

	mkdir -p $HOME/.config/systemd/user
	
	DOCKERD_FLAGS="--experimental"
	
	if [ -n "$SKIP_IPTABLES" ]; then
		DOCKERD_FLAGS="$DOCKERD_FLAGS --iptables=false"
	fi

	if [ "$USE_OVERLAY" = "1" ]; then
		DOCKERD_FLAGS="$DOCKERD_FLAGS --storage-driver=overlay2"
	else
		DOCKERD_FLAGS="$DOCKERD_FLAGS --storage-driver=vfs"
	fi

	CFG_DIR="$HOME/.config"
	if [ -n "$XDG_CONFIG_HOME" ]; then
		CFG_DIR="$XDG_CONFIG_HOME"
	fi


	if [ ! -f $CFG_DIR/systemd/user/docker.service ]; then
		cat <<EOT > $CFG_DIR/systemd/user/docker.service
[Unit]
Description=Docker Application Container Engine (Rootless)
Documentation=https://docs.docker.com

[Service]
Environment=PATH=$HOME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=$HOME/bin/dockerd-rootless.sh $DOCKERD_FLAGS
ExecReload=/bin/kill -s HUP \$MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
Type=simple

[Install]
WantedBy=multi-user.target
EOT
	systemctl --user daemon-reload
	fi
	if ! systemctl --user status docker >/dev/null 2>&1; then
		echo "# starting systemd service"
		systemctl --user start docker
	fi
	systemctl --user status docker | cat

	sleep 1
	PATH="$BIN:$PATH" DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock" docker version
}

service_instructions() {
	if [ -z "$SYSTEMD" ]; then
		return
	fi
	cat <<EOT
#
# To control docker service run:
# systemctl --user (start|stop|restart) docker
#
EOT
}


start_docker_nonsystemd() {
	iptablesflag=
	if [ -n "$SKIP_IPTABLES" ]; then
		iptablesflag="--iptables=false "
	fi
	cat <<EOT
# systemd not detected, dockerd daemon needs to be started manually

$BIN/dockerd-rootless.sh --experimental $iptablesflag--storage-driver vfs

EOT
}

print_instructions() {
	start_docker
	echo "# Docker binaries are installed in $BIN"
	if [ "$(which $DAEMON)" != "$BIN/$DAEMON" ]; then
		echo "# WARN: dockerd is not in your current PATH or pointing to $BIN/$DAEMON"
	fi
	echo "# Make sure the following environment variables are set (or add them to ~/.bashrc):\n"

	if [ -n "$XDG_RUNTIME_DIR_CREATED" ]; then
		echo "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
	fi

	case :$PATH: in
	*:$BIN:*) ;;
	*) echo "export PATH=$BIN:\$PATH" ;;
	esac

	# iptables is required but /sbin might not be in PATH
	if [ -z "$SKIP_IPTABLES" ] && ! which iptables >/dev/null 2>&1; then
		if [ -f /sbin/iptables ]; then
			echo "export PATH=\$PATH:/sbin"
		elif [ -f /usr/sbin/iptables ]; then
			echo "export PATH=\$PATH:/usr/sbin"
		fi
	fi

	echo "export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock"
	echo
	service_instructions
}

do_install() {
	init_vars
	checks

	tmp=$(mktemp -d)
	trap "rm -rf $tmp" EXIT INT TERM
	# Alternatively could find latest nightly release from https://download.docker.com/linux/static/nightly/ .
	# Later we can provide different channels.
	STATIC_RELEASE_URL="https://master.dockerproject.org/linux/x86_64/docker.tgz"
	STATIC_RELEASE_ROOTLESS_URL="https://master.dockerproject.org/linux/x86_64/docker-rootless-extras.tgz"

	# Download tarballs docker-* and docker-rootless-extras=*
	(
		cd "$tmp"
		curl -L -o docker.tgz "$STATIC_RELEASE_URL"
		curl -L -o rootless.tgz "$STATIC_RELEASE_ROOTLESS_URL"
	)
	# Extract under $HOME/bin/
	(
		mkdir -p "$BIN"
		cd "$BIN"
		tar zxf "$tmp/docker.tgz" --strip-components=1
		tar zxf "$tmp/rootless.tgz" --strip-components=1
	)

	print_instructions

}

do_install
