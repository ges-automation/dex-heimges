#!/bin/sh
set -eu

# =============================================================================
# Script:       build.sh
# Author:       Andrew J. Moore
# Date:         2026-09-18
# Revision:     r1
#
# Description:
#   Builds the custom dex-heimges container image from an exact pinned
#   upstream Dex commit.
#
#   The script:
#     - Requires a clean dex-heimges Git working tree.
#     - Determines the current dex-heimges repository commit.
#     - Fetches the configured upstream Dex commit.
#     - Validates and applies all *.patch files in the patches directory.
#     - Builds the resulting Docker image.
#     - Adds OCI metadata describing the build source.
#     - Records the exact locally-built image name in .build-image for use
#       by publish.sh.
#
# Image tag format:
#   YYYYMMDDHHMM-dex_<upstream-sha>-patch_<repository-sha>
#
# Prerequisites:
#   - Git
#   - Docker Engine / Docker CLI
#   - A clean checkout of this repository
#   - One or more *.patch files in ./patches
#
# Output:
#   Local Docker image:
#     ghcr.io/gesandrewmoore/dex-heimges:<generated-tag>
#
#   Image reference file:
#     .build-image
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
DEX_COMMIT="7ace0e79cc6cfd2ed9373a2daa50cfb683e2e390"

IMAGE_REPO="ghcr.io/gesandrewmoore/dex-heimges"

# -----------------------------------------------------------------------------
# Paths and build metadata
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PATCH_DIR="$SCRIPT_DIR/patches"
IMAGE_FILE="$SCRIPT_DIR/.build-image"

DEX_SHORT="$(printf '%s' "$DEX_COMMIT" | cut -c1-7)"
REPO_SHORT="$(git -C "$SCRIPT_DIR" rev-parse --short=7 HEAD)"
BUILD_TIME="$(date -u +%Y%m%d%H%M)"

IMAGE_TAG="${BUILD_TIME}-dex_${DEX_SHORT}-patch_${REPO_SHORT}"
IMAGE="${IMAGE_REPO}:${IMAGE_TAG}"

BUILD_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$BUILD_DIR"
}

trap cleanup EXIT INT TERM

# -----------------------------------------------------------------------------
# Prerequisite and source checks
# -----------------------------------------------------------------------------

if ! command -v git >/dev/null 2>&1; then
    echo "Error: Git is not installed."
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker is not installed."
    exit 1
fi

# Ensure all source used by the build is represented by the repository SHA.
if [ -n "$(git -C "$SCRIPT_DIR" status --porcelain)" ]; then
    echo "Error: repository has uncommitted or untracked changes."
    echo
    git -C "$SCRIPT_DIR" status --short
    echo
    echo "Commit or stash your changes before building."
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
# Build summary
# -----------------------------------------------------------------------------

echo "Build repo SHA: ${REPO_SHORT}"
echo "Dex commit SHA:  ${DEX_SHORT}"
echo "Build time UTC:  ${BUILD_TIME}"
echo "Image tag:       ${IMAGE}"
echo "Patch directory: ${PATCH_DIR}"
echo

# -----------------------------------------------------------------------------
# Fetch upstream Dex source
# -----------------------------------------------------------------------------

echo "Fetching Dex commit ${DEX_SHORT}..."

git init "$BUILD_DIR/dex" >/dev/null 2>&1
cd "$BUILD_DIR/dex"

git remote add origin https://github.com/dexidp/dex.git
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
    --label org.opencontainers.image.source="https://github.com/gesandrewmoore/dex-heimges" \
    --label org.opencontainers.image.created="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --label org.opencontainers.image.version="${IMAGE_TAG}" \
    --label org.opencontainers.image.revision="${REPO_SHORT}" \
    --label io.ges.dex.upstream-revision="${DEX_COMMIT}" \
    --tag "$IMAGE" \
    .

# -----------------------------------------------------------------------------
# Record and report build output
# -----------------------------------------------------------------------------

# Record the exact image produced by this build for publish.sh.
printf '%s\n' "$IMAGE" > "$IMAGE_FILE"

echo
echo "Built image:"
docker image inspect "$IMAGE" \
    --format '{{.RepoTags}} {{.Id}}'

echo
echo "Recorded image:"
echo "  $IMAGE_FILE"
echo "  $IMAGE"
