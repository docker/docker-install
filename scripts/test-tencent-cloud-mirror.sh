#!/bin/sh
# Opt-in network smoke check. Run only from a Tencent Cloud VM using its VPC
# private-network route. This is not a package installation or signature test.
set -eu

usage() {
	echo "Usage: TENCENT_CLOUD_INTRANET=1 sh $0 <ubuntu|debian> <codename>"
	echo "Run only inside Tencent Cloud's private network, with the default VPC DNS."
	echo "The environment variable is an operator confirmation, not cloud detection."
}

if [ "${1:-}" = "--help" ]; then
	usage
	exit 0
fi

# Check the opt-in before looking up DNS, invoking curl, or creating files.
case "${TENCENT_CLOUD_INTRANET:-0}" in
	0|"")
		echo 'SKIP: Tencent Cloud network smoke check is disabled; no network requests made.'
		echo 'Run in the Tencent Cloud private network and set TENCENT_CLOUD_INTRANET=1.'
		exit 0
		;;
	1) ;;
	*)
		>&2 echo 'ERROR: TENCENT_CLOUD_INTRANET must be 0 or 1.'
		exit 2
		;;
esac

if [ "$#" -ne 2 ]; then
	usage >&2
	exit 2
fi

distro=$1
codename=$2
case "$distro" in
	ubuntu|debian) ;;
	*)
		>&2 echo 'ERROR: this smoke check covers Ubuntu and Debian APT repositories only.'
		exit 2
		;;
esac
case "$codename" in
	""|*[!a-z0-9]*)
		>&2 echo 'ERROR: use a distribution codename containing only lowercase letters and digits.'
		exit 2
		;;
esac

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	echo 'Check the Tencent Cloud VPC DNS/private-network route and repository availability.' >&2
	exit 1
}

command -v curl > /dev/null 2>&1 || fail 'curl is required'
echo 'NOTICE: run only inside the Tencent Cloud private network; no cloud or route detection is performed.'
echo 'NOTICE: proxies are bypassed; ensure the default Tencent Cloud VPC DNS is in use.'
umask 077
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' 0
trap 'exit 1' HUP INT TERM
base_url="https://mirrors.cloud.tencent.com/docker-ce/linux/$distro"

fetch() {
	# Ignore .curlrc and proxies; retain TLS verification. Do not follow redirects
	# or silently fall back to a public endpoint. Bound each request's duration.
	if ! http_code=$(curl -q --fail --silent --show-error --proto '=https' \
		--noproxy '*' --connect-timeout 5 --max-time 30 \
		--output "$tmp_dir/$2" --write-out '%{http_code}' "$base_url/$1"); then
		fail "cannot download $base_url/$1"
	fi
	[ "$http_code" = '200' ] || fail "unexpected HTTP $http_code from $base_url/$1"
	[ -s "$tmp_dir/$2" ] || fail "empty response from $base_url/$1"
}

fetch gpg gpg
grep -Fqx -- '-----BEGIN PGP PUBLIC KEY BLOCK-----' "$tmp_dir/gpg" || fail 'unexpected GPG key response'
grep -Fqx -- '-----END PGP PUBLIC KEY BLOCK-----' "$tmp_dir/gpg" || fail 'incomplete GPG key response'
fetch "dists/$codename/Release" Release
grep -Fqx -- 'Origin: Docker' "$tmp_dir/Release" || fail 'unexpected repository metadata'
grep -Fqx -- "Codename: $codename" "$tmp_dir/Release" || fail 'repository codename mismatch'

echo "PASS (network smoke only): $distro/$codename key and Release endpoints returned expected content markers."
echo 'NOT TESTED: cryptographic signatures, package downloads, installation, or Docker service startup.'
