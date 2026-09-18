#!/bin/sh
set -eu

# =============================================================================
# Script:       build-dev.sh
# Author:       Andrew J. Moore
# Date:         2026-09-18
# Revision:     r2
#
# Description:
#   Convenience wrapper for creating a local development build of dex-heimges.
#   Invokes build.sh with --dev so uncommitted/untracked patch development can
#   be built and tested without producing a publishable GHCR image reference.
#
# Prerequisites:
#   - Same prerequisites as build.sh
# =============================================================================

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

exec "$SCRIPT_DIR/build.sh" --dev
