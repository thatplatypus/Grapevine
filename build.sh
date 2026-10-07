#!/usr/bin/env bash
# Builds every package and links every program into build/.
#   ./build.sh         build
#   ./build.sh test    build, then run the test suites that need no network
set -euo pipefail
cd "$(dirname "$0")"
case "${1:-}" in
  ""|test) ;;
  *) echo "usage: ./build.sh [test]" >&2; exit 2 ;;
esac
EC=${EC:-emojicodec}
# The same variable the compiler reads, so compiling and linking look in one place.
STOCK=${EMOJICODE_PACKAGES_PATH:-/usr/local/EmojicodePackages}
ROOT="$PWD"
PKG="$ROOT/build/packages"
BIN="$ROOT/build/bin"
OBJ="$ROOT/build/obj"
# Start clean, so nothing from an earlier build is linked in or reported as built.
rm -rf "$PKG" "$BIN" "$OBJ"
mkdir -p "$PKG" "$BIN" "$OBJ"

# Packages, in dependency order.
packages/grapevine/build.sh "$PKG/grapevine"

# program <name> <main file> [stock package...]
# Compiles a program to an object and links it here. The compiler's own link step puts
# packages in an order that fails when one package depends on another, so every package
# archive goes into one linker group instead. Stock packages are named per program.
# The compiler runs from build/ because ./packages under the working directory is on
# its search path: there it finds the freshly built packages, and never a stale
# interface left in a source folder by a compiler run by hand.
program() {
  local name=$1 main=$2; shift 2
  local archives=("$PKG"/*/lib*.a)
  local stock
  for stock in "$@"; do archives+=("$STOCK/$stock/lib$stock.a"); done
  ( cd "$ROOT/build" && "$EC" "$ROOT/$main" -c -o "$OBJ/$name.o" )
  c++ "$OBJ/$name.o" -Wl,--start-group "${archives[@]}" -Wl,--end-group \
    "$STOCK/s/libs.a" -lm -lpthread "$STOCK/runtime/libruntime.a" -o "$BIN/$name"
}

program shared-tests    packages/shared/tests/main.🍇
program grapevine-tests packages/grapevine/tests/unit/main.🍇
program grapevine-fuzz  packages/grapevine/tests/fuzz/main.🍇
program wire-host       packages/grapevine/tests/host/main.🍇
program todo-api        app/main.🍇
program app-tests       app/tests.🍇
echo "built: $(ls "$BIN" | tr '\n' ' ')"

if [[ "${1:-}" == "test" ]]; then
  echo; echo "── lint"; ./tests/lint-test.sh; ./tests/lint.sh
  echo; echo "── shared: unit tests"; "$BIN/shared-tests"
  echo; echo "── grapevine: unit tests"; "$BIN/grapevine-tests"
  echo; echo "── grapevine: fuzz"; "$BIN/grapevine-fuzz"; FUZZ_MODE=json "$BIN/grapevine-fuzz"
  echo; echo "── sample: in-memory tests"; "$BIN/app-tests"
  echo; echo "── sample: HTTP smoke test"; ./tests/smoke.sh
fi
