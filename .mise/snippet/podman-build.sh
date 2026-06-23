#!/usr/bin/env sh
# shellcheck shell=dash

set +u
if [ "$FORGEJO_ACTIONS" = "true" ]; then
	X_PODMAN_MANIFEST_REGISTRY="docker.io"
fi
set -u

X_PODMAN_MANIFEST="$X_PODMAN_MANIFEST_REGISTRY/searxng/base:$X_PODMAN_MANIFEST_TAG"

if podman manifest exists "$X_PODMAN_MANIFEST"; then
	podman manifest rm "$X_PODMAN_MANIFEST"
fi

# shellcheck disable=SC2086
podman build $X_PODMAN_COMMON \
	--platform="$X_PODMAN_TARGET" \
	--target="$X_PODMAN_MANIFEST_TAG" \
	--manifest="$X_PODMAN_MANIFEST" \
	.

export X_PODMAN_MANIFEST
