#!/bin/sh
#
# SPDX-FileCopyrightText: © 2026 GES Automation Technology, Inc.
# SPDX-FileContributor: Andrew J. Moore
# SPDX-License-Identifier: 0BSD
#
# =============================================================================
# Script:       scripts/image.sh
# Author:       Andrew J. Moore
# Revised:      2026-09-21
# Revision:     r7
# Source:       https://github.com/ges-automation/dex-heimges
#
# Purpose:
#   Builds the custom dex-heimges container image from an exact pinned
#   upstream Dex commit.
#
# Comments:
#   Versioned builds require a clean repository at origin/main, produce a
#   GHCR-namespaced image, and record it in .build-image. Development builds
#   permit working-tree changes, produce only a local *-dev image, and remove
#   any stale .build-image file. Both modes compare the pinned Dex commit with
#   upstream master and require confirmation when they differ.
#
#   Patch files are validated and applied in shell glob order, which normally
#   corresponds to lexical filename order. Prefix filenames numerically if
#   patch application order matters.
#
#   Versioned tags use:
#     ghcr.io/ges-automation/dex-heimges:
#       YYYYMMDDHHMM-dex_<upstream-sha>-patch_<patch-commit-sha>
#
#   Development tags use:
#     dex-heimges:YYYYMMDDHHMM-dex_<upstream-sha>-dev
#
# Dependencies:
#   Git - Validates repository state, fetches Dex, and applies patches.
#   Docker CLI - Builds and inspects the resulting container image.
#   POSIX utilities - Uses awk, basename, cut, date, dirname, and mktemp.
#   patches/*.patch - At least one applicable Dex patch is required.
#
# Usage:
#   sh ./scripts/image.sh [--dev]
#
# Arguments:
#   --dev     Build a local development image from the working tree.
#   -h        Show command help and exit.
#   --help    Show command help and exit.
# =============================================================================

set -eu

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Exact upstream Dex commit to build.
DEX_REPO="https://github.com/dexidp/dex.git"
DEX_COMMIT="7ace0e79cc6cfd2ed9373a2daa50cfb683e2e390"

VERSIONED_IMAGE_REPO="ghcr.io/ges-automation/dex-heimges"
DEV_IMAGE_REPO="dex-heimges"

# -----------------------------------------------------------------------------
# Command-line arguments
# -----------------------------------------------------------------------------

IMAGE_MODE="versioned"

case "${1:-}" in
    "")
        ;;
    --dev)
        IMAGE_MODE="dev"
        ;;
    -h|--help)
        echo "Usage: $0 [--dev]"
        echo
        echo "  no option   Build an official versioned image locally."
        echo "  --dev       Build a local development image from the current working tree."
        exit 0
        ;;
    *)
        echo "Error: unknown option: $1"
        echo "Usage: $0 [--dev]"
        exit 1
        ;;
esac

if [ "$#" -gt 1 ]; then
    echo "Error: too many arguments."
    echo "Usage: $0 [--dev]"
    exit 1
fi

# -----------------------------------------------------------------------------
# Paths and build metadata
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
PATCH_DIR="$REPO_DIR/patches"
IMAGE_FILE="$REPO_DIR/.build-image"

DEX_SHORT="$(printf '%s' "$DEX_COMMIT" | cut -c1-7)"
REPO_SHORT="$(git -C "$REPO_DIR" rev-parse --short=7 HEAD)"
BUILD_TIME="$(date -u +%Y%m%d%H%M)"

case "$IMAGE_MODE" in
    versioned)
        IMAGE_TAG="${BUILD_TIME}-dex_${DEX_SHORT}-patch_${REPO_SHORT}"
        IMAGE="${VERSIONED_IMAGE_REPO}:${IMAGE_TAG}"
        ;;
    dev)
        IMAGE_TAG="${BUILD_TIME}-dex_${DEX_SHORT}-dev"
        IMAGE="${DEV_IMAGE_REPO}:${IMAGE_TAG}"
        ;;
esac

BUILD_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$BUILD_DIR"
}

trap cleanup EXIT INT TERM

# -----------------------------------------------------------------------------
# Prerequisite checks
# -----------------------------------------------------------------------------

if ! command -v git >/dev/null 2>&1; then
    echo "Error: Git is not installed."
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker is not installed."
    exit 1
fi

if [ ! -d "$PATCH_DIR" ]; then
    echo "Error: patch directory does not exist:"
    echo "  $PATCH_DIR"
    exit 1
fi

# POSIX sh has no nullglob, so explicitly verify that at least one patch exists.
PATCH_FOUND=0

for PATCH_FILE in "$PATCH_DIR"/*.patch; do
    if [ -f "$PATCH_FILE" ]; then
        PATCH_FOUND=1
        break
    fi
done

if [ "$PATCH_FOUND" -eq 0 ]; then
    echo "Error: no .patch files found in:"
    echo "  $PATCH_DIR"
    exit 1
fi

# -----------------------------------------------------------------------------
# Versioned image source validation
# -----------------------------------------------------------------------------

if [ "$IMAGE_MODE" = "versioned" ]; then
    # Ensure all source used by the build is represented by the repository SHA.
    if [ -n "$(git -C "$REPO_DIR" status --porcelain)" ]; then
        echo "Error: repository has uncommitted or untracked changes."
        echo
        git -C "$REPO_DIR" status --short
        echo
        echo "Commit or stash your changes before creating a versioned image."
        echo "Use 'sh ./scripts/image.sh --dev' or 'make image-dev' for a local development image."
        exit 1
    fi

    echo "Checking origin/main..."
    git -C "$REPO_DIR" fetch --quiet origin main

    LOCAL_HEAD="$(git -C "$REPO_DIR" rev-parse HEAD)"
    REMOTE_HEAD="$(git -C "$REPO_DIR" rev-parse origin/main)"

    if [ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]; then
        echo "Error: local repository does not match origin/main."
        echo
        echo "Local HEAD:  $(git -C "$REPO_DIR" rev-parse --short=7 HEAD)"
        echo "origin/main: $(git -C "$REPO_DIR" rev-parse --short=7 origin/main)"
        echo
        echo "Run 'git pull --ff-only' before creating a versioned image."
        echo "Use 'sh ./scripts/image.sh --dev' or 'make image-dev' for a local development image."
        exit 1
    fi
else
    # A development build must never leave a pushable image pointer behind.
    rm -f "$IMAGE_FILE"
fi

# -----------------------------------------------------------------------------
# Upstream Dex freshness check
# -----------------------------------------------------------------------------

echo "Checking upstream Dex master..."

DEX_MASTER_COMMIT="$(
    git ls-remote "$DEX_REPO" refs/heads/master | awk '{print $1}'
)"

if [ -z "$DEX_MASTER_COMMIT" ]; then
    echo "Error: unable to determine the current upstream Dex master commit."
    exit 1
fi

if [ "$DEX_MASTER_COMMIT" != "$DEX_COMMIT" ]; then
    DEX_MASTER_SHORT="$(printf '%s' "$DEX_MASTER_COMMIT" | cut -c1-7)"

    echo
    echo "NOTICE: upstream Dex master differs from the pinned commit."
    echo
    echo "Pinned commit:"
    echo "  short: ${DEX_SHORT}"
    echo "  full:  ${DEX_COMMIT}"
    echo
    echo "Current master:"
    echo "  short: ${DEX_MASTER_SHORT}"
    echo "  full:  ${DEX_MASTER_COMMIT}"
    echo
    printf "Continue building the pinned commit? [y/N] "

    CONTINUE_BUILD=""
    if ! IFS= read -r CONTINUE_BUILD; then
        CONTINUE_BUILD=""
    fi

    case "$CONTINUE_BUILD" in
        y|Y)
            ;;
        *)
            echo "Build cancelled."
            exit 0
            ;;
    esac
fi

# -----------------------------------------------------------------------------
# Build summary
# -----------------------------------------------------------------------------

echo
echo "Image mode:       ${IMAGE_MODE}"
echo "Build time UTC:   ${BUILD_TIME}"
echo "Dex commit SHA:   ${DEX_SHORT}"
echo "Patch commit SHA: ${REPO_SHORT}"
echo "Image tag:        ${IMAGE}"
echo "Patch directory:  ${PATCH_DIR}"
echo

if [ "$IMAGE_MODE" = "dev" ]; then
    echo "Development build: uncommitted and untracked repository changes are allowed."
    echo "This image is local-only and cannot be pushed by image-push.sh."
    echo
fi

# -----------------------------------------------------------------------------
# Fetch upstream Dex source
# -----------------------------------------------------------------------------

echo "Fetching Dex commit ${DEX_SHORT}..."

git init "$BUILD_DIR/dex" >/dev/null 2>&1
cd "$BUILD_DIR/dex"

git remote add origin "$DEX_REPO"
git fetch --depth 1 origin "$DEX_COMMIT"
git checkout FETCH_HEAD

# -----------------------------------------------------------------------------
# Validate all patches before modifying the source tree
# -----------------------------------------------------------------------------

echo
echo "Checking patches..."

for PATCH_FILE in "$PATCH_DIR"/*.patch; do
    PATCH_NAME="$(basename "$PATCH_FILE")"

    echo "  Checking ${PATCH_NAME}..."
    git apply --check "$PATCH_FILE"
done

# -----------------------------------------------------------------------------
# Apply patches
# -----------------------------------------------------------------------------

echo
echo "Applying patches..."

for PATCH_FILE in "$PATCH_DIR"/*.patch; do
    PATCH_NAME="$(basename "$PATCH_FILE")"

    echo "  Applying ${PATCH_NAME}..."
    git apply "$PATCH_FILE"
done

# -----------------------------------------------------------------------------
# Build container image
# -----------------------------------------------------------------------------

echo
echo "Building ${IMAGE}..."

docker build \
    --build-arg VERSION="${IMAGE_TAG}" \
    --label org.opencontainers.image.title="dex-heimges" \
    --label org.opencontainers.image.description="Custom Dex build with HEIMGES patches" \
    --label org.opencontainers.image.source="https://github.com/ges-automation/dex-heimges" \
    --label org.opencontainers.image.created="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --label org.opencontainers.image.version="${IMAGE_TAG}" \
    --label org.opencontainers.image.revision="${REPO_SHORT}" \
    --label com.gestech.dex.upstream-revision="${DEX_COMMIT}" \
    --label com.gestech.dex.image-mode="${IMAGE_MODE}" \
    --tag "$IMAGE" \
    .

# -----------------------------------------------------------------------------
# Record and report build output
# -----------------------------------------------------------------------------

if [ "$IMAGE_MODE" = "versioned" ]; then
    # Record the exact image produced by this build for image-push.sh.
    printf '%s\n' "$IMAGE" > "$IMAGE_FILE"
fi

echo
echo "Built image:"
docker image inspect "$IMAGE" \
    --format '{{.RepoTags}} {{.Id}}'

if [ "$IMAGE_MODE" = "versioned" ]; then
    echo
    echo "Recorded pushable image:"
    echo "  $IMAGE_FILE"
    echo "  $IMAGE"
else
    echo
    echo "Development image only; .build-image was not created."
fi
