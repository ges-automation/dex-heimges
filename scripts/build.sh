#!/bin/sh
set -eu

# =============================================================================
# Script:       build.sh
# Author:       Andrew J. Moore
# Date:         2026-09-18
# Revision:     r5
#
# Description:
#   Builds the custom dex-heimges container image from an exact pinned
#   upstream Dex commit.
#
#   By default, the script creates a release build suitable for publication.
#   Release builds require a clean repository whose HEAD exactly matches the
#   latest origin/main revision.
#
#   Passing --dev creates a local development image from the current working
#   tree. Development builds may contain uncommitted or untracked changes,
#   are intentionally kept outside the GHCR namespace, and are never recorded
#   as publishable images.
#
# Build modes:
#   ./scripts/build.sh
#       Release build.
#
#   ./scripts/build.sh --dev
#       Development build using the current local working tree.
#
# Release image tag format:
#   ghcr.io/ges-automation/dex-heimges:
#     YYYYMMDDHHMM-dex_<upstream-sha>-patch_<patch-commit-sha>
#
# Development image tag format:
#   dex-heimges:YYYYMMDDHHMM-dex_<upstream-sha>-dev
#
# Prerequisites:
#   - Git
#   - Docker Engine / Docker CLI
#   - One or more *.patch files in ../patches
#
# Release build requirements:
#   - Clean Git working tree
#   - Local HEAD exactly matches origin/main
#
# Upstream freshness check:
#   Both release and development builds compare the pinned Dex commit with the
#   current tip of upstream Dex master. If they differ, the script displays
#   both short and full SHAs and requires confirmation before continuing.
#
# Output:
#   Release builds create a GHCR-namespaced local image and record its exact
#   image name in .build-image for use by publish.sh.
#
#   Development builds create only a local dex-heimges:*-dev image and remove
#   any existing .build-image so a development workflow cannot leave a stale
#   image reference available for publishing.
#
# Notes:
#   Patch files are validated and applied in shell glob order, which normally
#   corresponds to lexical filename order. Prefix filenames numerically if
#   patch application order matters.
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Exact upstream Dex commit to build.
DEX_REPO="https://github.com/dexidp/dex.git"
DEX_COMMIT="7ace0e79cc6cfd2ed9373a2daa50cfb683e2e390"

RELEASE_IMAGE_REPO="ghcr.io/ges-automation/dex-heimges"
DEV_IMAGE_REPO="dex-heimges"

# -----------------------------------------------------------------------------
# Command-line arguments
# -----------------------------------------------------------------------------

BUILD_MODE="release"

case "${1:-}" in
    "")
        ;;
    --dev)
        BUILD_MODE="dev"
        ;;
    -h|--help)
        echo "Usage: $0 [--dev]"
        echo
        echo "  no option   Build a publishable release image."
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

case "$BUILD_MODE" in
    release)
        IMAGE_TAG="${BUILD_TIME}-dex_${DEX_SHORT}-patch_${REPO_SHORT}"
        IMAGE="${RELEASE_IMAGE_REPO}:${IMAGE_TAG}"
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
# Release source validation
# -----------------------------------------------------------------------------

if [ "$BUILD_MODE" = "release" ]; then
    # Ensure all source used by the build is represented by the repository SHA.
    if [ -n "$(git -C "$REPO_DIR" status --porcelain)" ]; then
        echo "Error: repository has uncommitted or untracked changes."
        echo
        git -C "$REPO_DIR" status --short
        echo
        echo "Commit or stash your changes before creating a release build."
        echo "Use ./scripts/build.sh --dev or make dev for a local development build."
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
        echo "Run 'git pull --ff-only' before creating a release build."
        echo "Use ./scripts/build.sh --dev or make dev for a local development build."
        exit 1
    fi
else
    # A development build must never leave a publishable image pointer behind.
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
echo "Build mode:       ${BUILD_MODE}"
echo "Build time UTC:   ${BUILD_TIME}"
echo "Dex commit SHA:   ${DEX_SHORT}"
echo "Patch commit SHA: ${REPO_SHORT}"
echo "Image tag:        ${IMAGE}"
echo "Patch directory:  ${PATCH_DIR}"
echo

if [ "$BUILD_MODE" = "dev" ]; then
    echo "Development build: uncommitted and untracked repository changes are allowed."
    echo "This image is local-only and cannot be published by publish.sh."
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
    --label io.ges.dex.upstream-revision="${DEX_COMMIT}" \
    --label io.ges.build-mode="${BUILD_MODE}" \
    --tag "$IMAGE" \
    .

# -----------------------------------------------------------------------------
# Record and report build output
# -----------------------------------------------------------------------------

if [ "$BUILD_MODE" = "release" ]; then
    # Record the exact image produced by this build for publish.sh.
    printf '%s\n' "$IMAGE" > "$IMAGE_FILE"
fi

echo
echo "Built image:"
docker image inspect "$IMAGE" \
    --format '{{.RepoTags}} {{.Id}}'

if [ "$BUILD_MODE" = "release" ]; then
    echo
    echo "Recorded publishable image:"
    echo "  $IMAGE_FILE"
    echo "  $IMAGE"
else
    echo
    echo "Development image only; .build-image was not created."
fi
