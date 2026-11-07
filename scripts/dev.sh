#!/usr/bin/env bash
# The inner loop: build, sign, relaunch. Opens a window; it reads the real ~/.claude and ~/.codex
# unless HOME, CLAUDE_CONFIG_DIR, CODEX_HOME and SPACEVIBE_HOME point at a synthetic folder first.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Reins"
APP_BUNDLE="build/${APP_NAME}.app"
EXECUTABLE_NAME="Reins"

scripts/build-app.sh

echo "==> relaunching"
pkill -x "${EXECUTABLE_NAME}" 2>/dev/null || true
while pgrep -x "${EXECUTABLE_NAME}" >/dev/null 2>&1; do sleep 0.1; done
# LaunchServices can still be holding the just-killed process (error -600, procNotFound); one
# retry after a beat clears it. -10825 is a different failure: the deployment target regressed.
# `open` does not pass this shell's environment on; forward the v5 switch (LaunchMode.uiV5SwitchName) when it is set.
OPEN_ARGS=()
if [[ -n "${SPACEVIBE_UI_V5:-}" ]]; then OPEN_ARGS=(--env "SPACEVIBE_UI_V5=${SPACEVIBE_UI_V5}"); fi
for attempt in 1 2 3; do
  open "${APP_BUNDLE}" ${OPEN_ARGS[@]+"${OPEN_ARGS[@]}"} 2>/dev/null && sleep 1
  if pgrep -x "${EXECUTABLE_NAME}" >/dev/null 2>&1; then
    echo "==> running as pid $(pgrep -x "${EXECUTABLE_NAME}") (attempt ${attempt})"
    exit 0
  fi
  sleep 1
done

echo "==> the app is not running after 3 attempts; check Console for dev.spacevibe.app" >&2
exit 1
