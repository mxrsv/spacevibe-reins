#!/usr/bin/env bash
# Refuses an Info.plist whose Sparkle public key must not ship: the key of the deprecated account dev.spacevibe.reins
# (AGENTS.md B8), a missing key or an empty one. Reads the plist only; touches no Keychain.
#
#   scripts/check-update-key.sh <Info.plist>    exit 0 when the key may ship, 1 with one sentence on stderr otherwise
set -euo pipefail

# Deleted, with the check against it, once the owner's new key (account dev.spacevibe.app) is in Info.plist (B8).
DEPRECATED_UPDATE_KEY='hm8HrxfmddgAerzdQuttPxx7gexaV3oBycH9YIG1tSY='

if [[ $# -ne 1 ]]; then echo "Usage: scripts/check-update-key.sh <Info.plist>" >&2; exit 2; fi
PLIST="$1"
[[ -f "${PLIST}" ]] || { echo "${PLIST} does not exist." >&2; exit 2; }

KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${PLIST}" 2>/dev/null || true)"
if [[ -z "${KEY}" ]]; then
  echo "SUPublicEDKey is missing or empty in ${PLIST}: set the public key printed by generate_keys --account dev.spacevibe.app (AGENTS.md B8)." >&2
  exit 1
fi
if [[ "${KEY}" == "${DEPRECATED_UPDATE_KEY}" ]]; then
  echo "SUPublicEDKey in ${PLIST} is still the deprecated key of the account dev.spacevibe.reins: replace it with the new account's public key before any release (AGENTS.md B8)." >&2
  exit 1
fi
