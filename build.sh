#!/bin/sh
set -eu

# Exact Dex commit to build.
DEX_COMMIT="7ace0e79cc6cfd2ed9373a2daa50cfb683e2e390"
DEX_SHORT="$(printf '%s' "$DEX_COMMIT" | cut -c1-7)"

IMAGE="dexidp/dex:master-${DEX_SHORT}-ges"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BUILD_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$BUILD_DIR"
}

trap cleanup EXIT INT TERM

echo "Fetching Dex commit ${DEX_SHORT}..."

git init "$BUILD_DIR/dex"
cd "$BUILD_DIR/dex"

git remote add origin https://github.com/dexidp/dex.git
git fetch --depth 1 origin "$DEX_COMMIT"
git checkout FETCH_HEAD


echo "Checking GES claims patch..."
git apply --check "$SCRIPT_DIR/ges-claims.go.patch"
echo "Applying GES claims patch..."
git apply "$SCRIPT_DIR/ges-claims.go.patch"

echo "Checking GES LDAP patch..."
git apply --check "$SCRIPT_DIR/ges-ldap.go.patch"
echo "Applying GES LDAP patch..."
git apply "$SCRIPT_DIR/ges-ldap.go.patch"


echo "Building ${IMAGE}..."

docker build \
    --build-arg VERSION="master-${DEX_SHORT}-ges" \
    --tag "$IMAGE" \
    .

echo
echo "Built image:"
docker image inspect "$IMAGE" \
    --format '{{.RepoTags}} {{.Id}}'
