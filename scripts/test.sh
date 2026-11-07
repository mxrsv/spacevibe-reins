#!/usr/bin/env bash
# Runs the unit tests.
#
# Plain `swift test` builds but runs nothing on a machine with only the Command Line Tools
# installed: swift-testing ships in `Library/Developer/Frameworks` there rather than inside
# the toolchain, and SwiftPM only discovers it when the framework search path is on the
# command line. Passing `-Xswiftc -F` is what flips discovery on; the two `-rpath` entries are
# what let the built test bundle find `Testing.framework` and `lib_TestingInterop.dylib` at
# run time. With a full Xcode installed none of this applies and the flags are skipped.
#
# The Go core is vetted, tested and built first; SPACEVIBE_CORE_BINARY points Swift tests at the build.
# Tests build their own temporary HOME. SPACEVIBE_TEST=1 turns on the real-home guard in `Roots`.
set -euo pipefail

cd "$(dirname "$0")/.."

DEVELOPER_DIR_PATH="${DEVELOPER_DIR:-$(xcode-select -p)}"
TESTING_FRAMEWORKS="${DEVELOPER_DIR_PATH}/Library/Developer/Frameworks"
TESTING_INTEROP="${DEVELOPER_DIR_PATH}/Library/Developer/usr/lib"

FLAGS=()
if [[ -d "${TESTING_FRAMEWORKS}/Testing.framework" ]]; then
  FLAGS=(
    -Xswiftc -F -Xswiftc "${TESTING_FRAMEWORKS}"
    -Xlinker -F -Xlinker "${TESTING_FRAMEWORKS}"
    -Xlinker -rpath -Xlinker "${TESTING_FRAMEWORKS}"
    -Xlinker -rpath -Xlinker "${TESTING_INTEROP}"
  )
else
  echo "note: no Command Line Tools swift-testing found; running swift test unmodified." >&2
fi

export SPACEVIBE_TEST=1
# Go first: vet and test the core, then build the binary Swift tests spawn.
(cd core && go vet ./... && go test -count=1 ./...)
export SPACEVIBE_CORE_BINARY="${PWD}/.build/spacevibe-core/spacevibe"
scripts/build-core.sh "${SPACEVIBE_CORE_BINARY}"
# The frozen goldens (SV5) must be byte-identical to the committed hashes.
(cd core/testdata/fixtures && shasum -a 256 -c --quiet SHA256SUMS)
# The `+` form: bash 3.2 with `set -u` treats an empty array as unbound, which is the Xcode case above.
exec swift test ${FLAGS[@]+"${FLAGS[@]}"} "$@"
