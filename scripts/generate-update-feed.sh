#!/usr/bin/env bash
# Writes a signed appcast.xml next to notarized DMGs. Publishes nothing.
#
#   scripts/generate-update-feed.sh <directory with DMGs> <https download prefix ending in />
#
# Refuses an archive that is not stapled, a Keychain key that differs from Resources/Info.plist, and any entry without an
# Ed25519 signature or HTTPS URL. Upload the DMG before replacing the public appcast.xml.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -ne 2 ]]; then
  echo "usage: scripts/generate-update-feed.sh <directory with DMGs> <https download prefix ending in />" >&2
  exit 2
fi
ARCHIVES_DIR="$(cd "$1" && pwd)"
DOWNLOAD_PREFIX="$2"
TOOLS_DIR="${REPO_ROOT}/.build/artifacts/sparkle/Sparkle/bin"
SIGNING_ACCOUNT="dev.spacevibe.reins"

fail() { echo "$*" >&2; exit 1; }

[[ -x "${TOOLS_DIR}/generate_appcast" ]] || fail "Sparkle tools are missing. Run swift package resolve first."
[[ "${DOWNLOAD_PREFIX}" =~ ^https://[^/@#?]+/([^@#?]*/)?$ ]] \
  || fail "The download prefix must be an HTTPS URL ending in / without credentials, query or fragment."

shopt -s nullglob
DMGS=("${ARCHIVES_DIR}"/*.dmg)
[[ ${#DMGS[@]} -gt 0 ]] || fail "No DMG in ${ARCHIVES_DIR}."
for dmg in "${DMGS[@]}"; do
  xcrun stapler validate "${dmg}" >/dev/null 2>&1 || fail "Not notarized and stapled: ${dmg}"
done

EXPECTED_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${REPO_ROOT}/Resources/Info.plist")"
ACTUAL_KEY="$("${TOOLS_DIR}/generate_keys" --account "${SIGNING_ACCOUNT}" -p)"
[[ "${ACTUAL_KEY}" == "${EXPECTED_KEY}" ]] || fail "The Keychain key does not match Resources/Info.plist. No appcast was written."

"${TOOLS_DIR}/generate_appcast" --account "${SIGNING_ACCOUNT}" --download-url-prefix "${DOWNLOAD_PREFIX}" \
  --maximum-deltas 0 -o "${ARCHIVES_DIR}/appcast.xml" "${ARCHIVES_DIR}"

# generate_appcast can warn and still succeed without a signature; refuse that output.
swift - "${ARCHIVES_DIR}/appcast.xml" <<'SWIFT'
import Foundation
do {
    let document = try XMLDocument(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let enclosures = try document.nodes(forXPath: "/rss/channel/item/enclosure")
    guard !enclosures.isEmpty else { throw NSError(domain: "UpdateFeed", code: 1) }
    for case let enclosure as XMLElement in enclosures {
        guard let signature = enclosure.attribute(forName: "sparkle:edSignature")?.stringValue,
              Data(base64Encoded: signature)?.count == 64,
              let url = enclosure.attribute(forName: "url")?.stringValue, url.hasPrefix("https://") else {
            throw NSError(domain: "UpdateFeed", code: 2)
        }
    }
} catch {
    fputs("Update feed validation failed: \(error.localizedDescription). Do not publish this appcast.\n", stderr)
    exit(1)
}
SWIFT
echo "Signed update feed: ${ARCHIVES_DIR}/appcast.xml"
