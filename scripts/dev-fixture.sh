#!/usr/bin/env bash
# Runs Reins against a SYNTHETIC home, never the real ~/.claude and ~/.codex.
#
#   scripts/dev-fixture.sh                    build, then open the app window on a fresh synthetic home
#   scripts/dev-fixture.sh --shots <dir>      build, then write headless screenshots (no window) into <dir>
#   scripts/dev-fixture.sh --prepare          build and print the environment, do not start the app
#
# Environment: REINS_FIXTURE_ACTIVITY=empty (no live session) or =loading (the first process question waits 20 s, so the
# screen sits on "Reading logs...") is passed to scripts/fixture-home.mjs. REINS_BUILD_PATH overrides the scratch path.
# REINS_SHOT_SCREEN=shell|loadout|rules|activity picks the --shots run (default shell: the demo shell states and the
# gallery); the other three read this synthetic home and assert their writes, Undo included. Nothing else selects a screen.
#
# What the fake process list says (written by fixture-home.mjs to <home>/.reins/activity-proc.json, used because
# REINS_TEST=1 and REINS_PROC_FIXTURE name it; the pids are made up and only the fake answers for them):
#   alive 41001, 41002, 41003   the three Claude Code status files (running, waiting for you, idle)
#   codex threads 52001, 52002  two Codex rollouts (a silent tool call = not measurable, a running turn)
#   codex thread 52003          a Codex process with no rollout yet (not measurable)
# Nothing real is started or signalled; Stop in this mode only edits the in-memory list.
#
# Refuses to run when the folder it made is under the real home. The app itself refuses a root under the real home when
# REINS_TEST=1 (Roots.resolve).
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="run"
SHOT_DIR=""
case "${1:-}" in
  --shots) MODE="shots"; SHOT_DIR="${2:?usage: scripts/dev-fixture.sh --shots <dir>}" ;;
  --prepare) MODE="prepare" ;;
  "") ;;
  *) echo "usage: scripts/dev-fixture.sh [--shots <dir> | --prepare]" >&2; exit 2 ;;
esac

SCRATCH="${REINS_BUILD_PATH:-/tmp/reins-build-dev-fixture}"
echo "==> swift build (scratch ${SCRATCH})"
swift build --scratch-path "${SCRATCH}"
BIN="$(swift build --scratch-path "${SCRATCH}" --show-bin-path)/Reins"

# Build first, then write the fixture: its ages are relative to the moment it is written.
REAL_HOME="$(node -e 'process.stdout.write(require("os").userInfo().homedir)')"
FIX="$(mktemp -d "${TMPDIR:-/tmp}/reins-fixture.XXXXXX")"
FIX="$(cd "${FIX}" && pwd -P)"
case "${FIX}/" in
  "${REAL_HOME}/"*) echo "refusing: ${FIX} is under the real home ${REAL_HOME}" >&2; rmdir "${FIX}"; exit 1 ;;
esac
[ "${FIX}" != "${REAL_HOME}" ] || { echo "refusing: fixture dir is the real home" >&2; exit 1; }
[ "${MODE}" = "prepare" ] || trap 'rm -rf "${FIX}"' EXIT

echo "==> synthetic home ${FIX}"
node scripts/fixture-home.mjs "${FIX}" >/dev/null

export HOME="${FIX}"
export CLAUDE_CONFIG_DIR="${FIX}/.claude"
export CODEX_HOME="${FIX}/.codex"
export REINS_HOME="${FIX}/.reins"
export REINS_TEST=1
export REINS_PROC_FIXTURE="${FIX}/.reins/activity-proc.json"
[ -f "${REINS_PROC_FIXTURE}" ] || { echo "missing ${REINS_PROC_FIXTURE}" >&2; exit 1; }

case "${MODE}" in
  prepare)
    for v in HOME CLAUDE_CONFIG_DIR CODEX_HOME REINS_HOME REINS_TEST REINS_PROC_FIXTURE; do printf "export %s='%s'\n" "$v" "${!v}"; done
    echo "# binary: ${BIN}" ;;
  shots)
    REINS_SHOT_DIR="${SHOT_DIR}" "${BIN}" ;;
  run)
    echo "==> starting Reins (the home is deleted when it quits)"
    "${BIN}" ;;
esac
