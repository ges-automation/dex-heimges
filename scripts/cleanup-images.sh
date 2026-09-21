#!/bin/sh
#
# SPDX-FileCopyrightText: © 2026 GES Automation Technology, Inc.
# SPDX-FileContributor: Andrew J. Moore
# SPDX-License-Identifier: 0BSD
#
# =============================================================================
# Script:       scripts/cleanup-images.sh
# Author:       Andrew J. Moore
# Revised:      2026-09-21
# Revision:     r3
# Source:       https://github.com/ges-automation/dex-heimges
#
# Purpose:
#   Removes all local dex-heimges container images produced by versioned and
#   development builds. It does not remove containers, volumes, networks, or
#   Docker/BuildKit build cache.
#
# Comments:
#   Removes images from ghcr.io/ges-automation/dex-heimges and dex-heimges.
#
# Dependencies:
#   Docker CLI - Lists and removes the repository's local container images.
#   POSIX utilities - Uses sort and xargs to normalize and remove image IDs.
#
# Usage:
#   sh ./scripts/cleanup-images.sh
#
# Arguments:
#   None.
# =============================================================================

set -eu

VERSIONED_IMAGE_REPO="ghcr.io/ges-automation/dex-heimges"
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
remove_repository_images "$VERSIONED_IMAGE_REPO"

echo
echo "dex-heimges image cleanup complete."
