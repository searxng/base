#!/usr/bin/env sh
# shellcheck shell=dash

# shellcheck disable=SC2154
if [ "$usage_push" != "true" ]; then
	exit 0
fi

set +u
if [ "$FORGEJO_ACTIONS" != "true" ]; then
	echo >&2 "This task is intended to be run in CI/CD"
	exit 1
fi
set -u

podman manifest push --all "$X_PODMAN_MANIFEST"
