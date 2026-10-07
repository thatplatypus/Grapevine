#!/usr/bin/env bash
# Builds every package and links every program into build/.
#   ./build.sh         build
#   ./build.sh test    build, then run the test suites that need no network
set -euo pipefail
cd "$(dirname "$0")"
EC=${EC:-emojicodec}
STOCK=${EMOJICODE_PACKAGES:-/usr/local/EmojicodePackages}
ROOT="$PWD"
PKG="$ROOT/build/packages"
BIN="$ROOT/build/bin"
OBJ="$ROOT/build/obj"
mkdir -p "$PKG" "$BIN" "$OBJ"

# Packages, in dependency order.
packages/grapevine/build.sh "$PKG/grapevine"

# program <name> <main file> [stock package...]
# Compiles a program to an object and links it here. The compiler's own link step puts
# packages in an order that fails when one package depends on another, so every package
# archive goes into one linker group instead. Stock packages are named per program.
# The compiler runs from build/ because it searches ./packages first: there it finds
# the freshly built packages and never a stale interface left in a source folder.
program() {
  local name=$1 main=$2; shift 2
  local archives=("$PKG"/*/lib*.a)
  local stock
  for stock in "$@"; do archives+=("$STOCK/$stock/lib$stock.a"); done
  ( cd "$ROOT/build" && "$EC" "$ROOT/$main" -c -o "$OBJ/$name.o" )
  c++ "$OBJ/$name.o" -Wl,--start-group "${archives[@]}" -Wl,--end-group \
    "$STOCK/s/libs.a" -lm -lpthread "$STOCK/runtime/libruntime.a" -o "$BIN/$name"
}

program todo-api  app/main.🍇  sockets json
program app-tests app/tests.🍇 sockets json
echo "built: $(ls "$BIN" | tr '\n' ' ')"

if [[ "${1:-}" == "test" ]]; then
  echo; echo "── sample: in-memory tests"; "$BIN/app-tests"
  echo; echo "── sample: HTTP smoke test"; ./tests/smoke.sh
fi
