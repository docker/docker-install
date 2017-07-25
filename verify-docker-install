#!/bin/bash -e
(
	echo "INFO: Executing installation script!"
	sh build/install.sh
)

# Verify that we can at least get version output
if ! docker --version; then
	echo "ERROR: Did Docker get installed?"
	exit 1
fi

# Attempt to run a container if not in a container
if [ ! -f /.dockerenv  ]; then
	if ! docker run --rm hello-world; then
		echo "ERROR: Could not get docker to run the hello world container"
		exit 2
	fi
fi

echo "INFO: Successfully verified docker installation!"
