#!/usr/bin/env bash
# End-to-end update test through a local feed on 127.0.0.1, with no clicks. Two runs of an installed older build:
#   wrong signature -> the archive is downloaded and refused, the bundle stays at the old version
#   right signature -> the archive is downloaded, verified and installed when the app quits
# Sparkle's update window takes a click, so these test bundles (never the committed plist) turn on background install;
# the signature check is the same either way. The window and relaunch are checked by hand: see the plan, task S7.3.
#
# Runs against a temporary HOME. Needs the Developer ID identity, the key in the Keychain, and no other Reins running,
# because the app's Sparkle settings live in the shared `dev.spacevibe.reins` defaults domain; only the SU* keys this
# run sets are touched, and they are removed at the end.
set -euo pipefail

cd "$(dirname "$0")/.."

PORT="${SPACEVIBE_UPDATE_TEST_PORT:-8765}"
FEED="http://127.0.0.1:${PORT}"
DOMAIN="dev.spacevibe.reins"
TOOLS=".build/artifacts/sparkle/Sparkle/bin"

fail() { echo "FAIL: $*" >&2; exit 1; }

if pgrep -x Reins >/dev/null; then fail "quit the running Reins first"; fi

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/reins-update-test.XXXXXX")" && pwd -P)"
SERVER=""
clear_settings() {
  for key in SULastCheckTime SUHasLaunchedBefore SUUpdateGroupIdentifier SUSkippedMinorVersion; do
    defaults delete "${DOMAIN}" "${key}" 2>/dev/null || true
  done
}
cleanup() {
  pkill -f "${WORK}/.*/MacOS/Reins" 2>/dev/null || true
  if [[ -n "${SERVER}" ]]; then kill "${SERVER}" 2>/dev/null || true; wait "${SERVER}" 2>/dev/null || true; fi
  clear_settings
  rm -rf "${WORK}"
}
trap cleanup EXIT

echo "==> building (feed ${FEED}/appcast.xml)"
SPACEVIBE_BUNDLE_DIR="${WORK}/base" SPACEVIBE_UPDATE_FEED_URL="${FEED}/appcast.xml" scripts/build-app.sh >"${WORK}/build.log" 2>&1 \
  || { tail -20 "${WORK}/build.log" >&2; fail "build"; }
IDENTITY="$(codesign -dvv "${WORK}/base/Reins.app" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p')"
[[ -n "${IDENTITY}" ]] || fail "needs a Developer ID signature (see AGENTS.md B3)"

# make_bundle <dir> <build number> <version>
make_bundle() {
  mkdir -p "$1"
  ditto "${WORK}/base/Reins.app" "$1/Reins.app"
  plutil -replace CFBundleVersion -string "$2" "$1/Reins.app/Contents/Info.plist"
  plutil -replace CFBundleShortVersionString -string "$3" "$1/Reins.app/Contents/Info.plist"
  plutil -replace SUAutomaticallyUpdate -bool YES "$1/Reins.app/Contents/Info.plist"
  plutil -replace SUAllowsAutomaticUpdates -bool YES "$1/Reins.app/Contents/Info.plist"
  codesign --force --options runtime --timestamp=none --sign "${IDENTITY}" "$1/Reins.app" 2>/dev/null
}

mkdir -p "${WORK}/feed" "${WORK}/home/.claude" "${WORK}/home/.codex" "${WORK}/home/.spacevibe"
make_bundle "${WORK}/new" 2 0.2.0
ditto -c -k --keepParent "${WORK}/new/Reins.app" "${WORK}/feed/Reins-0.2.0.zip"
"${TOOLS}/generate_appcast" --account "${DOMAIN}" --download-url-prefix "${FEED}/" --maximum-deltas 0 "${WORK}/feed" >/dev/null
cp "${WORK}/feed/appcast.xml" "${WORK}/appcast-right.xml"
# A signature of the right size that the Reins key did not make.
sed -E "s|sparkle:edSignature=\"[^\"]*\"|sparkle:edSignature=\"$(openssl rand -base64 64 | tr -d '\n')\"|" \
  "${WORK}/appcast-right.xml" >"${WORK}/appcast-wrong.xml"

(cd "${WORK}" && exec python3 -I -m http.server "${PORT}" --bind 127.0.0.1 --directory "${WORK}/feed" >"${WORK}/server.log" 2>&1) &
SERVER=$!

# run <name> <feed file> <expected build number after quit>
run() {
  local name="$1" appcast="$2" expected="$3" dir="${WORK}/$1" pid="" info
  echo "==> ${name}"
  info="${dir}/Reins.app/Contents/Info.plist"
  make_bundle "${dir}" 1 0.1.0
  cp "${appcast}" "${WORK}/feed/appcast.xml"
  : >"${WORK}/server.log"
  clear_settings
  # Far enough in the past that the scheduled check runs at launch.
  defaults write "${DOMAIN}" SULastCheckTime -date '2020-01-01 00:00:00 +0000'
  open -g -n --env "HOME=${WORK}/home" --env "CLAUDE_CONFIG_DIR=${WORK}/home/.claude" --env "CODEX_HOME=${WORK}/home/.codex" \
    --env "SPACEVIBE_HOME=${WORK}/home/.spacevibe" "${dir}/Reins.app"

  for _ in $(seq 1 60); do grep -q 'GET /Reins-0.2.0.zip' "${WORK}/server.log" && break; sleep 1; done
  grep -q 'GET /Reins-0.2.0.zip' "${WORK}/server.log" || { cat "${WORK}/server.log" >&2; fail "${name}: the app never downloaded the update"; }
  echo "    downloaded after the check: $(grep -c 'GET /appcast.xml' "${WORK}/server.log") feed request(s)"
  sleep 6 # Verification and extraction run in the background and have no signal this script can read.

  pid="$(pgrep -f "${dir}/Reins.app/Contents/MacOS/Reins" || true)"
  [[ -n "${pid}" ]] || fail "${name}: the app died before quit"
  swift - "${pid}" <<'SWIFT'
import AppKit
_ = NSRunningApplication(processIdentifier: pid_t(CommandLine.arguments[1])!)?.terminate()
SWIFT
  while kill -0 "${pid}" 2>/dev/null; do sleep 1; done

  local actual=""
  for _ in $(seq 1 30); do
    actual="$(plutil -extract CFBundleVersion raw "${info}" 2>/dev/null || true)"
    [[ "${actual}" == "2" ]] && break
    sleep 1
  done
  [[ "${actual}" == "${expected}" ]] || fail "${name}: build ${actual} after quit, expected ${expected}"
  codesign --verify --deep --strict "${dir}/Reins.app" 2>/dev/null || fail "${name}: the bundle no longer verifies"
  echo "    PASS: build ${actual} after quit, signature valid"
}

run wrong-signature "${WORK}/appcast-wrong.xml" 1
run right-signature "${WORK}/appcast-right.xml" 2
echo "==> update test passed"
