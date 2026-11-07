#!/usr/bin/env bash
# Writes the Rules screen screenshots (dark and light, 1440x900) into <dir>: the full set on the default synthetic home,
# then the Codex "unrestricted" and "both models" variants. Each run builds nothing new after the first and uses its own
# synthetic home (see scripts/dev-fixture.sh); nothing real is read.
#
#   scripts/rules-shots.sh <dir>                       the old Rules screen
#   SPACEVIBE_UI_V5=1 scripts/rules-shots.sh <dir>     the v5 Rules tab (RulesTabShots): rules-*, rules-unrestricted-*, rules-both-*
set -euo pipefail

cd "$(dirname "$0")/.."
DIR="${1:?usage: scripts/rules-shots.sh <dir>}"
mkdir -p "${DIR}"

export SPACEVIBE_SHOT_SCREEN=rules
scripts/dev-fixture.sh --shots "${DIR}"
SPACEVIBE_FIXTURE_CODEX=unrestricted scripts/dev-fixture.sh --shots "${DIR}"
SPACEVIBE_FIXTURE_CODEX=both scripts/dev-fixture.sh --shots "${DIR}"
