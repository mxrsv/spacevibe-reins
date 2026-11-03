#!/usr/bin/env bash
# Packages one committed revision as a signed DMG, and with --notarize as the notarized, stapled release artifact plus
# the signed appcast. Publishes nothing: the tag, the push and the GitHub release are printed at the end for the owner.
#
#   scripts/release.sh --prepare    local candidate: Developer ID signature with a timestamp, not notarized, no appcast
#   scripts/release.sh --notarize   release artifact: notarized and stapled app and DMG, appcast.xml, SHA256SUMS
#
# Environment:
#   REINS_NOTARY_PROFILE    notarytool Keychain profile (`xcrun notarytool store-credentials`); --notarize only
#   REINS_UPDATE_FEED_URL   appcast URL baked into the app as SUFeedURL; default: the latest GitHub release's appcast.xml
#   REINS_DOWNLOAD_PREFIX   where the DMG will be downloadable, ending in /; default: this version's GitHub release
#   REINS_SIGNING_IDENTITY  as in scripts/build-app.sh
#
# Builds from `git archive HEAD` in a temporary folder, so the artifact is exactly the committed revision even when the
# checkout has other sessions' edits; a dirty tree is still refused so nothing is forgotten. Output goes to
# build/distribution/v<version>-<sha7>/ (gitignored).
set -euo pipefail

cd "$(dirname "$0")/.."

usage() { echo "Usage: scripts/release.sh --prepare | --notarize"; }
MODE="${1:-}"
case "${MODE}" in
  --help) usage; exit 0 ;;
  --prepare|--notarize) ;;
  *) usage >&2; exit 2 ;;
esac
if [[ $# -ne 1 ]]; then usage >&2; exit 2; fi

GITHUB_REPO="mxrsv/spacevibe-reins"
APP_NAME="Reins"
SIGNING_IDENTITY="${REINS_SIGNING_IDENTITY:-Developer ID Application: VAN BINH TRAN (DJDD3T8LH7)}"
NOTARY_PROFILE="${REINS_NOTARY_PROFILE:-}"

fail() { echo "$*" >&2; exit 1; }

if [[ "${MODE}" == --notarize ]]; then
  [[ -n "${NOTARY_PROFILE}" ]] || fail "Set REINS_NOTARY_PROFILE to a notarytool Keychain profile name (AGENTS.md B9)."
  xcrun --find notarytool >/dev/null || fail "notarytool is missing from the Command Line Tools."
  xcrun --find stapler >/dev/null || fail "stapler is missing from the Command Line Tools."
fi
security find-identity -v -p codesigning | grep -qF "\"${SIGNING_IDENTITY}\"" \
  || fail "The Developer ID identity is not in the keychain: ${SIGNING_IDENTITY}"
if [[ -n "$(git status --porcelain=v1)" ]]; then
  git status --short >&2
  fail "Commit or stash the changes above before packaging a release: the artifact must match one revision."
fi

REVISION="$(git rev-parse HEAD)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/reins-release.XXXXXX")"
trap 'rm -rf "${WORK_DIR}"' EXIT
SOURCE_DIR="${WORK_DIR}/source"
STAGING_DIR="${WORK_DIR}/image"
mkdir -p "${SOURCE_DIR}" "${STAGING_DIR}"
git archive "${REVISION}" | tar -x -C "${SOURCE_DIR}"

PLIST="${SOURCE_DIR}/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST}")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${PLIST}")"
TAG="v${VERSION}"
[[ "${BUILD_NUMBER}" =~ ^[0-9]+$ ]] || fail "CFBundleVersion must be a whole number; Sparkle compares it. Found: ${BUILD_NUMBER}"
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  fail "Tag ${TAG} already exists. Raise CFBundleShortVersionString and CFBundleVersion in Resources/Info.plist first."
fi
PREVIOUS_TAG="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
if [[ -n "${PREVIOUS_TAG}" ]]; then
  git show "${PREVIOUS_TAG}:Resources/Info.plist" >"${WORK_DIR}/previous.plist"
  PREVIOUS_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${WORK_DIR}/previous.plist")"
  (( BUILD_NUMBER > PREVIOUS_BUILD )) \
    || fail "CFBundleVersion ${BUILD_NUMBER} is not above ${PREVIOUS_BUILD} (${PREVIOUS_TAG}); installed copies would never see this release."
fi

UPDATE_FEED_URL="${REINS_UPDATE_FEED_URL:-https://github.com/${GITHUB_REPO}/releases/latest/download/appcast.xml}"
DOWNLOAD_PREFIX="${REINS_DOWNLOAD_PREFIX:-https://github.com/${GITHUB_REPO}/releases/download/${TAG}/}"
OUTPUT_DIR="build/distribution/${TAG}-${REVISION:0:7}"
[[ ! -e "${OUTPUT_DIR}" ]] || fail "${OUTPUT_DIR} exists. Remove it to package this revision again."
mkdir -p "${OUTPUT_DIR}"

echo "==> ${APP_NAME} ${VERSION} (build ${BUILD_NUMBER}) from ${REVISION:0:7}, ${MODE#--}"
REINS_UPDATE_FEED_URL="${UPDATE_FEED_URL}" REINS_SIGNING_IDENTITY="${SIGNING_IDENTITY}" \
  "${SOURCE_DIR}/scripts/build-app.sh" --distribution
APP_BUNDLE="${SOURCE_DIR}/build/${APP_NAME}.app"
printf '%s\n' "${REVISION}" >"${OUTPUT_DIR}/revision.txt"

# notarize <archive> <report>: submits and waits; anything but Accepted stops the release.
notarize() {
  xcrun notarytool submit "$1" --keychain-profile "${NOTARY_PROFILE}" --wait --timeout 15m --output-format json >"$2"
  [[ "$(plutil -extract status raw -o - "$2")" == Accepted ]] \
    || fail "Notarization was not accepted; see $2 and \`xcrun notarytool log <id> --keychain-profile ${NOTARY_PROFILE}\`."
}

if [[ "${MODE}" == --notarize ]]; then
  echo "==> notarizing the app"
  ditto -c -k --keepParent "${APP_BUNDLE}" "${WORK_DIR}/app.zip"
  notarize "${WORK_DIR}/app.zip" "${OUTPUT_DIR}/app-notarization.json"
  xcrun stapler staple "${APP_BUNDLE}"
  xcrun stapler validate "${APP_BUNDLE}"
  spctl --assess --type execute --verbose=2 "${APP_BUNDLE}"
fi

echo "==> disk image"
ditto "${APP_BUNDLE}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"
DMG="${OUTPUT_DIR}/${APP_NAME}-${VERSION}.dmg"
hdiutil create -quiet -volname "${APP_NAME}" -srcfolder "${STAGING_DIR}" -format UDZO "${DMG}"
codesign --timestamp --sign "${SIGNING_IDENTITY}" "${DMG}"
codesign --verify --strict --verbose=2 "${DMG}"

if [[ "${MODE}" == --notarize ]]; then
  echo "==> notarizing the disk image"
  notarize "${DMG}" "${OUTPUT_DIR}/dmg-notarization.json"
  xcrun stapler staple "${DMG}"
  xcrun stapler validate "${DMG}"
  spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG}"
  echo "==> update feed"
  "${SOURCE_DIR}/scripts/generate-update-feed.sh" "${OUTPUT_DIR}" "${DOWNLOAD_PREFIX}"
  printf '%s\n' "Notarized and stapled. Not published." >"${OUTPUT_DIR}/status.txt"
else
  printf '%s\n' "NOT NOTARIZED: local candidate only, do not publish this download." >"${OUTPUT_DIR}/status.txt"
fi

(cd "${OUTPUT_DIR}" && shasum -a 256 ./*.dmg >SHA256SUMS)
cat "${OUTPUT_DIR}/status.txt"
cat "${OUTPUT_DIR}/SHA256SUMS"
echo "==> artifacts in ${OUTPUT_DIR}"
if [[ "${MODE}" == --notarize ]]; then
  cat <<STEPS

Publish, in this order (each step is outward-facing; do not script it away):
  1. git tag ${TAG} ${REVISION:0:7} && git push origin main ${TAG}
  2. gh release create ${TAG} "${DMG}" "${OUTPUT_DIR}/appcast.xml" --title "${APP_NAME} ${VERSION}" --notes-file <notes.md>
     The asset must keep the name appcast.xml: installed copies read ${UPDATE_FEED_URL}
  3. Download the DMG from the release page on another Mac, open it and launch Reins once before announcing.
STEPS
fi
