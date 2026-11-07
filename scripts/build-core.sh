#!/usr/bin/env bash
# Builds the Go core, the `spacevibe` helper the app spawns (SV1), for the host architecture.
#
#   scripts/build-core.sh <output-path> [version]
#
# The version is stamped into identity.Version (default "dev"). CGO is off, so the binary is static and
# carries no libc dependency; -trimpath keeps the build machine's paths out of it. Used by test.sh,
# build-app.sh, dev.sh and dev-fixture.sh so the flags live in one place.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="${1:?usage: scripts/build-core.sh <output-path> [version]}"
VERSION="${2:-dev}"
case "${OUT}" in /*) ;; *) OUT="${PWD}/${OUT}" ;; esac

mkdir -p "$(dirname "${OUT}")"
echo "==> go build ${OUT} (version ${VERSION})"
(cd core && CGO_ENABLED=0 GOARCH="$(go env GOHOSTARCH)" go build -trimpath \
  -ldflags "-X spacevibe.dev/core/internal/identity.Version=${VERSION}" \
  -o "${OUT}" ./cmd/spacevibe)
