#!/bin/sh
set -eu

# =============================================================================
# Script:       publish.sh
# Author:       Andrew J. Moore
# Date:         2026-09-18
# Revision:     r4
#
# Description:
#   Publishes the most recently built dex-heimges container image to the
#   GitHub Container Registry (GHCR).
#
#   The image to publish is read from .build-image, which is generated only
#   by a successful release build. Images outside the expected dex-heimges
#   GHCR namespace are explicitly rejected.
#
#   After the versioned image is pushed successfully, the same image is also
#   tagged and pushed as :latest so deployments can track the current release.
#
#   GHCR credentials are retrieved from 1Password using the 1Password CLI.
#   Docker authentication is performed using a temporary DOCKER_CONFIG
#   directory so GHCR credentials are not persisted in ~/.docker/config.json.
#
# Prerequisites:
#   - Docker CLI installed
#   - 1Password CLI (op) installed
#   - Access to the referenced 1Password item
#   - A successful release build that created .build-image
#
# Environment:
#   GHCR_PAT_OP_REF
#       1Password item reference containing:
#         username    - GitHub username
#         credential  - GitHub PAT with GHCR write access
#
#       Example:
#         op://<vault-id>/<item-id>
#
#   If GHCR_PAT_OP_REF is not set, this script prompts for it and optionally
#   stores it in ~/.profile for future runs.
#
# Authentication:
#   If an active 1Password CLI session already exists, it is reused.
#   Otherwise, this script performs an interactive `op signin` for the
#   duration of this script only.
# =============================================================================

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
# Determine image to publish
# -----------------------------------------------------------------------------

if [ ! -f "$IMAGE_FILE" ]; then
    echo "Error: no built image is recorded in:"
    echo "  $IMAGE_FILE"
    echo
    echo "Run 'make' or ./scripts/build.sh first."
    exit 1
fi

IMAGE="$(cat "$IMAGE_FILE")"

if [ -z "$IMAGE" ]; then
    echo "Error: $IMAGE_FILE is empty."
    exit 1
fi

# Refuse to publish anything outside the expected release image namespace.
case "$IMAGE" in
    "$EXPECTED_IMAGE_PREFIX"*)
        ;;
    *)
        echo "Error: refusing to publish image outside the expected GHCR repository:"
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
    echo "Run 'make' or ./scripts/build.sh first."
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
# Authenticate and publish
# -----------------------------------------------------------------------------

echo
echo "Authenticating to ghcr.io as ${GHCR_USERNAME}..."

printf '%s' "$GHCR_PAT" |
    docker login ghcr.io \
        --username "$GHCR_USERNAME" \
        --password-stdin

unset GHCR_PAT

echo
echo "Publishing:"
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
echo "Published successfully:"
echo "  $IMAGE"
echo "  $LATEST_IMAGE"
