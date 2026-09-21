#!/bin/sh
#
# SPDX-FileCopyrightText: © 2026 GES Automation Technology, Inc.
# SPDX-FileContributor: Andrew J. Moore
# SPDX-License-Identifier: 0BSD
#
# =============================================================================
# Script:       scripts/image-push.sh
# Author:       Andrew J. Moore
# Revised:      2026-09-21
# Revision:     r6
# Source:       https://github.com/ges-automation/dex-heimges
#
# Purpose:
#   Pushes the most recently built dex-heimges container image to the
#   GitHub Container Registry (GHCR), then tags and pushes the same image as
#   latest. The image is read from the .build-image file produced by a
#   successful versioned build.
#
# Comments:
#   Rejects images outside the expected dex-heimges GHCR namespace. Retrieves
#   credentials from 1Password and uses a temporary Docker configuration so
#   they are not persisted in ~/.docker/config.json. Reuses an active
#   1Password CLI session or starts an interactive sign-in when needed.
#
# Dependencies:
#   Docker CLI - Authenticates, inspects, tags, and pushes container images.
#   1Password CLI (op) - Reads the GHCR username and personal access token.
#   POSIX utilities - Uses cat, dirname, mktemp, rm, and sed.
#   .build-image - Must identify an existing successful versioned build.
#
# Environment:
#   GHCR_PAT_OP_REF - 1Password item reference containing username and
#                     credential fields. When unset, the script prompts for it
#                     and can save it to ~/.profile.
#
# Usage:
#   sh ./scripts/image-push.sh
#
# Arguments:
#   None.
# =============================================================================

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
IMAGE_FILE="$REPO_DIR/.build-image"
PROFILE_FILE="$HOME/.profile"
EXPECTED_IMAGE_PREFIX="ghcr.io/ges-automation/dex-heimges:"
LATEST_IMAGE="ghcr.io/ges-automation/dex-heimges:latest"

# -----------------------------------------------------------------------------
# Prerequisite checks
# -----------------------------------------------------------------------------

if ! command -v op >/dev/null 2>&1; then
    echo "Error: 1Password CLI (op) is not installed."
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker is not installed."
    exit 1
fi

# -----------------------------------------------------------------------------
# Bootstrap GHCR_PAT_OP_REF if it is not already configured
# -----------------------------------------------------------------------------

if [ -z "${GHCR_PAT_OP_REF:-}" ]; then
    echo "GHCR_PAT_OP_REF is not configured."
    echo
    printf "Enter the 1Password item reference for the GHCR credential\n"
    printf "(example: op://<vault-id>/<item-id>): "
    read GHCR_PAT_OP_REF

    if [ -z "$GHCR_PAT_OP_REF" ]; then
        echo "Error: no 1Password reference supplied."
        exit 1
    fi

    echo
    printf "Save GHCR_PAT_OP_REF to %s? [Y/n] " "$PROFILE_FILE"
    read SAVE_REF

    case "${SAVE_REF:-Y}" in
        Y|y|"")
            # Remove any previous definition before adding the new one.
            if [ -f "$PROFILE_FILE" ]; then
                sed -i '/^[[:space:]]*export GHCR_PAT_OP_REF=/d' "$PROFILE_FILE"
            fi

            printf "\nexport GHCR_PAT_OP_REF='%s'\n" "$GHCR_PAT_OP_REF" >> "$PROFILE_FILE"

            echo "Saved GHCR_PAT_OP_REF to $PROFILE_FILE"
            ;;
        *)
            echo "GHCR_PAT_OP_REF will be used for this run only."
            ;;
    esac

    export GHCR_PAT_OP_REF
fi

# -----------------------------------------------------------------------------
# Ensure an active 1Password CLI session exists
# -----------------------------------------------------------------------------

ensure_op_session() {
    if ! op whoami >/dev/null 2>&1; then
        echo
        echo "1Password authentication required."
        eval "$(op signin)"
    fi
}

ensure_op_session

# -----------------------------------------------------------------------------
# Determine image to push
# -----------------------------------------------------------------------------

if [ ! -f "$IMAGE_FILE" ]; then
    echo "Error: no built image is recorded in:"
    echo "  $IMAGE_FILE"
    echo
    echo "Run 'make image' or 'sh ./scripts/image.sh' first."
    exit 1
fi

IMAGE="$(cat "$IMAGE_FILE")"

if [ -z "$IMAGE" ]; then
    echo "Error: $IMAGE_FILE is empty."
    exit 1
fi

# Refuse to push anything outside the expected versioned image namespace.
case "$IMAGE" in
    "$EXPECTED_IMAGE_PREFIX"*)
        ;;
    *)
        echo "Error: refusing to push image outside the expected GHCR repository:"
        echo "  $IMAGE"
        echo
        echo "Expected prefix:"
        echo "  $EXPECTED_IMAGE_PREFIX"
        exit 1
        ;;
esac

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Error: recorded image does not exist locally:"
    echo "  $IMAGE"
    echo
    echo "Run 'make image' or 'sh ./scripts/image.sh' first."
    exit 1
fi

# -----------------------------------------------------------------------------
# Read GHCR credentials from 1Password
# -----------------------------------------------------------------------------

echo
echo "Reading GHCR credentials from 1Password..."

GHCR_USERNAME="$(op read "${GHCR_PAT_OP_REF}/username")"
GHCR_PAT="$(op read "${GHCR_PAT_OP_REF}/credential")"

if [ -z "$GHCR_USERNAME" ]; then
    echo "Error: username could not be read from 1Password."
    exit 1
fi

if [ -z "$GHCR_PAT" ]; then
    echo "Error: credential could not be read from 1Password."
    exit 1
fi

# -----------------------------------------------------------------------------
# Use a temporary Docker configuration so GHCR credentials are not persisted
# -----------------------------------------------------------------------------

DOCKER_CONFIG="$(mktemp -d)"

cleanup() {
    unset GHCR_PAT
    rm -rf "$DOCKER_CONFIG"
}

trap cleanup EXIT INT TERM
export DOCKER_CONFIG

# -----------------------------------------------------------------------------
# Authenticate and push
# -----------------------------------------------------------------------------

echo
echo "Authenticating to ghcr.io as ${GHCR_USERNAME}..."

printf '%s' "$GHCR_PAT" |
    docker login ghcr.io \
        --username "$GHCR_USERNAME" \
        --password-stdin

unset GHCR_PAT

echo
echo "Pushing:"
echo "  $IMAGE"
echo

docker push "$IMAGE"

echo
echo "Tagging latest:"
echo "  $LATEST_IMAGE"

echo
docker tag "$IMAGE" "$LATEST_IMAGE"
docker push "$LATEST_IMAGE"

echo
echo "Pushed successfully:"
echo "  $IMAGE"
echo "  $LATEST_IMAGE"
