#!/bin/sh
set -eu

# Exact Dex commit to build.
DEX_COMMIT="7ace0e79cc6cfd2ed9373a2daa50cfb683e2e390"
DEX_SHORT="$(printf '%s' "$DEX_COMMIT" | cut -c1-7)"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PATCH_SHORT="$(git -C "$SCRIPT_DIR" rev-parse --short=7 HEAD)"
BUILD_TIME="$(date -u +%Y%m%d%H%M)"

IMAGE_REPO="ghcr.io/gesandrewmoore/dex-heimges"
IMAGE_TAG="${BUILD_TIME}-dex_${DEX_SHORT}-patch_${PATCH_SHORT}"
IMAGE="${IMAGE_REPO}:${IMAGE_TAG}"

BUILD_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$BUILD_DIR"
}

trap cleanup EXIT INT TERM

# Optional safety check: ensure repo is clean so patch SHA fully describes source.
if ! git -C "$SCRIPT_DIR" diff --quiet || ! git -C "$SCRIPT_DIR" diff --cached --quiet; then
    echo "Error: repository has uncommitted changes."
    echo "Commit or stash your changes before building."
    exit 1
fi

echo "Build repo SHA: ${PATCH_SHORT}"
echo "Dex commit SHA:  ${DEX_SHORT}"
echo "Build time UTC:  ${BUILD_TIME}"
echo "Image tag:       ${IMAGE}"
echo

echo "Fetching Dex commit ${DEX_SHORT}..."

git init "$BUILD_DIR/dex" >/dev/null 2>&1
cd "$BUILD_DIR/dex"

git remote add origin https://github.com/dexidp/dex.git
git fetch --depth 1 origin "$DEX_COMMIT"
git checkout FETCH_HEAD

echo "Checking HEIMGES claims patch..."
git apply --check "$SCRIPT_DIR/ges-claims.go.patch"
echo "Applying HEIMGES claims patch..."
git apply "$SCRIPT_DIR/ges-claims.go.patch"

echo "Checking HEIMGES LDAP patch..."
git apply --check "$SCRIPT_DIR/ges-ldap.go.patch"
echo "Applying HEIMGES LDAP patch..."
git apply "$SCRIPT_DIR/ges-ldap.go.patch"

echo "Building ${IMAGE}..."

docker build \
    --build-arg VERSION="${IMAGE_TAG}" \
    --label org.opencontainers.image.title="dex-heimges" \
    --label org.opencontainers.image.description="Custom Dex build with HEIMGES patches" \
    --label org.opencontainers.image.source="https://github.com/gesandrewmoore/dex-heimges" \
    --label org.opencontainers.image.created="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --label org.opencontainers.image.version="${IMAGE_TAG}" \
    --label org.opencontainers.image.revision="${PATCH_SHORT}" \
    --label io.ges.dex.upstream-revision="${DEX_COMMIT}" \
    --tag "$IMAGE" \
    .

echo
echo "Built image:"
docker image inspect "$IMAGE" \
    --format '{{.RepoTags}} {{.Id}}'

if [ "${PUSH:-0}" = "1" ]; then
    echo
    echo "Pushing ${IMAGE}..."
    docker push "$IMAGE"
fi
