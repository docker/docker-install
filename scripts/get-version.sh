#!/bin/bash
set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <stable|test>" >&2
    exit 1
fi

channel="$1"

last_release_tag() {
    local field="$1"
    gh -R moby/moby release list -O desc --json tagName,isLatest,isPrerelease \
        -q ".[] | select(.${field}) | \
            .tagName | \
            sub(\"^docker-\"; \"\") | \
            select(startswith(\"v\") == true) | \
            sub(\"^v\"; \"\")" |
        head -n1
}

case "$channel" in
    stable) last_release_tag 'isLatest' ;;
    test) last_release_tag 'isPrerelease' ;;
    *)
        echo "Error: Invalid channel '$channel'. Use 'stable' or 'test'." >&2
        exit 1
        ;;
esac
