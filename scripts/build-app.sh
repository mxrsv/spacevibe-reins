#!/usr/bin/env bash
# Builds, assembles and signs `Reins.app` into build/.
#
#   scripts/build-app.sh                 development build: Developer ID when present, else ad-hoc; no timestamp
#   scripts/build-app.sh --distribution  release candidate: Developer ID required, secure timestamp (notarization
#                                        rejects a signature without one), REINS_UPDATE_FEED_URL required
#
# Signing: the Developer ID identity is used when it is in the keychain (override the name with
# REINS_SIGNING_IDENTITY). In a development build it is never required: without it the bundle is ad-hoc signed,
# which runs fine but makes macOS ask again for folder access (Documents, Desktop) after each rebuild.
#
# Updates: REINS_UPDATE_FEED_URL is written to the bundle as SUFeedURL. Without it the app has no update source and makes
# no request. HTTPS only; plain http is accepted for 127.0.0.1, which is what scripts/test-update.sh serves.
# REINS_BUNDLE_DIR puts the bundle somewhere other than build/.
set -euo pipefail

cd "$(dirname "$0")/.."

DISTRIBUTION=0
TIMESTAMP_OPTION="--timestamp=none"
case "${1:-}" in
  "") ;;
  --distribution) DISTRIBUTION=1; TIMESTAMP_OPTION="--timestamp" ;;
  --help) echo "Usage: scripts/build-app.sh [--distribution]"; exit 0 ;;
  *) echo "Unknown build option: $1" >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then echo "Too many build arguments" >&2; exit 2; fi

APP_NAME="Reins"
EXECUTABLE_NAME="Reins"
BUILD_DIR="${REINS_BUNDLE_DIR:-build}"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
SIGNING_IDENTITY="${REINS_SIGNING_IDENTITY:-Developer ID Application: VAN BINH TRAN (DJDD3T8LH7)}"
UPDATE_FEED_URL="${REINS_UPDATE_FEED_URL:-}"

case "${UPDATE_FEED_URL}" in
  ""|https://*|http://127.0.0.1:*) ;;
  *) echo "REINS_UPDATE_FEED_URL must be HTTPS (or http://127.0.0.1:<port> for a local test)." >&2; exit 2 ;;
esac
if [[ "${DISTRIBUTION}" == 1 ]]; then
  case "${UPDATE_FEED_URL}" in
    https://*) ;;
    *) echo "A distribution build needs REINS_UPDATE_FEED_URL set to the public HTTPS appcast URL." >&2; exit 2 ;;
  esac
fi

echo "==> swift build -c release"
swift build -c release
BINARY_DIR="$(swift build -c release --show-bin-path)"
BINARY="${BINARY_DIR}/${EXECUTABLE_NAME}"

echo "==> assembling ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources" "${APP_BUNDLE}/Contents/Frameworks"
cp "${BINARY}" "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"
cp Resources/Info.plist "${APP_BUNDLE}/Contents/Info.plist"
if [[ -n "${UPDATE_FEED_URL}" ]]; then
  plutil -insert SUFeedURL -string "${UPDATE_FEED_URL}" "${APP_BUNDLE}/Contents/Info.plist"
  echo "    update feed: ${UPDATE_FEED_URL}"
else
  echo "    updates off: REINS_UPDATE_FEED_URL is not set"
fi
ditto "${BINARY_DIR}/Sparkle.framework" "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
# Inter, the only typeface (OFL); InterFont registers it from here at launch.
mkdir -p "${APP_BUNDLE}/Contents/Resources/Fonts"
cp Resources/Fonts/InterVariable.woff2 Resources/Fonts/OFL.txt "${APP_BUNDLE}/Contents/Resources/Fonts/"
# The CLI brand marks Limits draws (CLIMark reads them from here).
mkdir -p "${APP_BUNDLE}/Contents/Resources/Brand"
cp Resources/Brand/*.svg "${APP_BUNDLE}/Contents/Resources/Brand/"
printf 'APPL????' > "${APP_BUNDLE}/Contents/PkgInfo"
# The app icon, rendered from the mark on every build so the artwork has one source. Resources and frameworks are
# copied here, before codesign: anything added to a signed bundle invalidates the signature.
ICON_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/reins-icon.XXXXXX")"
trap 'rm -rf "${ICON_WORK_DIR}"' EXIT
swift scripts/build-icon.swift Resources/AppIcon.svg "${ICON_WORK_DIR}/AppIcon.iconset"
iconutil -c icns "${ICON_WORK_DIR}/AppIcon.iconset" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

echo "==> deployment target"
# Guards the -10825 failure: a binary built for a newer macOS than the host will not launch.
vtool -show-build-version "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}" | sed -n '2,6p'

echo "==> codesign"
if security find-identity -v -p codesigning | grep -qF "\"${SIGNING_IDENTITY}\""; then
  echo "    identity: ${SIGNING_IDENTITY} (${TIMESTAMP_OPTION})"
  SIGN_ARGS=(--options runtime "${TIMESTAMP_OPTION}" --sign "${SIGNING_IDENTITY}")
elif [[ "${DISTRIBUTION}" == 1 ]]; then
  echo "A distribution build needs the Developer ID identity in the keychain: ${SIGNING_IDENTITY}" >&2
  exit 1
else
  echo "    identity not found in the keychain: ad-hoc signature (folder consent will not survive a rebuild)"
  SIGN_ARGS=(--sign -)
fi
# Inside out: Sparkle launches these helpers to install and relaunch an update.
SPARKLE_FRAMEWORK="${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
for component in \
  "${SPARKLE_FRAMEWORK}/Versions/B/Autoupdate" \
  "${SPARKLE_FRAMEWORK}/Versions/B/Updater.app" \
  "${SPARKLE_FRAMEWORK}/Versions/B/XPCServices/Downloader.xpc" \
  "${SPARKLE_FRAMEWORK}/Versions/B/XPCServices/Installer.xpc" \
  "${SPARKLE_FRAMEWORK}"; do
  codesign --force --preserve-metadata=identifier,entitlements "${SIGN_ARGS[@]}" "${component}"
done
codesign --force "${SIGN_ARGS[@]}" "${APP_BUNDLE}"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

echo "==> font"
ls "${APP_BUNDLE}/Contents/Resources/Fonts"

echo "==> designated requirement"
codesign -d -r- "${APP_BUNDLE}" 2>&1 | sed -n '/designated/,$p'

echo "==> built ${APP_BUNDLE}"
