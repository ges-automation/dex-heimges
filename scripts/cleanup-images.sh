#!/bin/sh
set -eu

# =============================================================================
# Script:       cleanup-images.sh
# Author:       Andrew J. Moore
# Date:         2026-09-18
# Revision:     r1
#
# Description:
#   Removes all local dex-heimges container images produced by release and
#   development builds. This does not remove containers, volumes, networks,
#   or Docker/BuildKit build cache.
#
# Image repositories removed:
#   - ghcr.io/gesandrewmoore/dex-heimges
#   - dex-heimges
#
# Prerequisites:
#   - Docker Engine / Docker CLI
# =============================================================================

RELEASE_IMAGE_REPO="ghcr.io/gesandrewmoore/dex-heimges"
DEV_IMAGE_REPO="dex-heimges"

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker is not installed."
    exit 1
fi

remove_repository_images() {
    REPOSITORY="$1"
    IMAGE_IDS="$(docker image ls -q "$REPOSITORY" | sort -u)"

    if [ -z "$IMAGE_IDS" ]; then
        echo "No local images found for: $REPOSITORY"
        return
    fi

    echo "Removing local images for: $REPOSITORY"
    printf '%s\n' "$IMAGE_IDS" | xargs docker image rm
}

remove_repository_images "$DEV_IMAGE_REPO"
remove_repository_images "$RELEASE_IMAGE_REPO"

echo
echo "dex-heimges image cleanup complete."
