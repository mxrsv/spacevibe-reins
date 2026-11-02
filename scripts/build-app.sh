#!/usr/bin/env bash
# Builds, assembles and signs `Reins.app` into build/.
#
# Signing: the Developer ID identity is used when it is in the keychain (override the name with
# REINS_SIGNING_IDENTITY). It is never required: without it the bundle is ad-hoc signed, which
# runs fine but makes macOS ask again for folder access (Documents, Desktop) after each rebuild.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Reins"
EXECUTABLE_NAME="Reins"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
SIGNING_IDENTITY="${REINS_SIGNING_IDENTITY:-Developer ID Application: VAN BINH TRAN (DJDD3T8LH7)}"

echo "==> swift build -c release"
swift build -c release
BINARY_DIR="$(swift build -c release --show-bin-path)"
BINARY="${BINARY_DIR}/${EXECUTABLE_NAME}"

echo "==> assembling ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp "${BINARY}" "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"
cp Resources/Info.plist "${APP_BUNDLE}/Contents/Info.plist"
printf 'APPL????' > "${APP_BUNDLE}/Contents/PkgInfo"
# Resources and frameworks are copied here, before codesign: anything added to a signed bundle
# invalidates the signature.

echo "==> deployment target"
# Guards the -10825 failure: a binary built for a newer macOS than the host will not launch.
vtool -show-build-version "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}" | sed -n '2,6p'

echo "==> codesign"
if security find-identity -v -p codesigning | grep -qF "\"${SIGNING_IDENTITY}\""; then
  echo "    identity: ${SIGNING_IDENTITY}"
  codesign --force --options runtime --timestamp=none --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
else
  echo "    identity not found in the keychain: ad-hoc signature (folder consent will not survive a rebuild)"
  codesign --force --sign - "${APP_BUNDLE}"
fi
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

echo "==> designated requirement"
codesign -d -r- "${APP_BUNDLE}" 2>&1 | sed -n '/designated/,$p'

echo "==> built ${APP_BUNDLE}"
