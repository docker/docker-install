#!/bin/bash

if [ -z "$1" ]; then
    echo "usage: $0 <stable|test>" >&2
    exit 2
fi

CHANNEL="$1"

# Determine subdomain based on channel
case "$CHANNEL" in
    test)
        SUBDOMAIN="test"
        ;;
    stable)
        SUBDOMAIN="get"
        ;;
    *)
        echo "Error: Invalid CHANNEL: $CHANNEL" >&2
        exit 1
        ;;
esac

set -euo pipefail

DIFF_FOUND=0

if [[ ! -f "build/$CHANNEL/install.sh" ]]; then
    echo "Error: build/$CHANNEL/install.sh not found" >&2
    exit 1
fi

if [[ "$CHANNEL" == "stable" ]] && [[ ! -f "build/$CHANNEL/rootless-install.sh" ]]; then
    echo "Error: build/$CHANNEL/rootless-install.sh not found" >&2
    exit 1
fi

TMP_DIR=$(mktemp -d)

# Download and compare install.sh
curl -sfSL "https://$SUBDOMAIN.docker.com" -o "$TMP_DIR/install.sh"

echo "# Diff $CHANNEL install.sh"
if ! diff --color=always -u "$TMP_DIR/install.sh" "build/$CHANNEL/install.sh"; then
    DIFF_FOUND=1
fi

# For stable channel, also compare rootless-install.sh
if [[ "$CHANNEL" == "stable" ]]; then
    curl -sfSL "https://$SUBDOMAIN.docker.com/rootless" -o "$TMP_DIR/rootless-install.sh"
    echo "# Diff $CHANNEL rootless-install.sh"
    if ! diff --color=always -u "$TMP_DIR/rootless-install.sh" "build/$CHANNEL/rootless-install.sh"; then
        DIFF_FOUND=1
    fi
fi

exit $DIFF_FOUND
