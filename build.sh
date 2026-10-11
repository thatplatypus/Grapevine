#!/usr/bin/env bash
# Builds every package and links every program into build/.
#   ./build.sh                    build
#   ./build.sh test               build, then run the test suites that need no network
#   ./build.sh released <folder>  build the packages from releases of them, and try those out
#
# A release of a package is its own folder and nothing above it. <folder> holds one for
# each package as pmj unpacked it: <folder>/crypto, <folder>/deflate and <folder>/grapevine.
# The packages are then built from those files and from nothing else of theirs, and what is
# built on them is the programs that import a package, as whoever uses one does.
# ./test-release.sh runs this.
set -euo pipefail
cd "$(dirname "$0")"
usage() { echo "usage: ./build.sh [test | released <folder>]" >&2; exit 2; }
case "${1:-}" in
  ""|test) [ $# -le 1 ] || usage ;;
  released) [ $# -eq 2 ] || usage ;;
  *) usage ;;
esac
mode=${1:-build}
EC=${EC:-emojicodec}
# The same variable the compiler reads, so compiling and linking look in one place.
STOCK=${EMOJICODE_PACKAGES_PATH:-/usr/local/EmojicodePackages}
ROOT="$PWD"
# Where each package's sources are: its own folder here, or a release of it.
FROM="$ROOT/packages"
if [ "$mode" = released ]; then
  FROM="$(cd "$2" 2> /dev/null && pwd)" || { echo "build.sh: $2 is not a folder" >&2; exit 2; }
  for needed in crypto deflate grapevine; do
    [ -f "$FROM/$needed/packmoji.json" ] \
      || { echo "build.sh: $FROM/$needed is not a release of $needed: it has no packmoji.json" >&2; exit 2; }
  done
fi
PKG="$ROOT/build/packages"
BIN="$ROOT/build/bin"
OBJ="$ROOT/build/obj"
# Start clean, so nothing from an earlier build is linked in or reported as built.
rm -rf "$PKG" "$BIN" "$OBJ"
mkdir -p "$PKG" "$BIN" "$OBJ"

# Packages, in dependency order.
packages/crypto/build.sh "$PKG/crypto" "$FROM/crypto"
packages/deflate/build.sh "$PKG/deflate" "$FROM/deflate"
packages/grapevine/build.sh "$PKG/grapevine" "$FROM/grapevine"

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
  ( cd "$ROOT/build" && "$EC" "$ROOT/$main" -c -o "$OBJ/$name.o" ) 2>&1 | tee "$OBJ/$name.log"
  # The compiler checks the code it generated, says "Detected in:" when the check fails,
  # and exits 0 all the same. What it built then crashes when it runs.
  if grep -q "Detected in:" "$OBJ/$name.log"; then
    echo "$main: the compiler generated code that its own check refuses, named above" >&2
    exit 1
  fi
  c++ "$OBJ/$name.o" -Wl,--start-group "${archives[@]}" -Wl,--end-group \
    "$STOCK/s/libs.a" -lm -lpthread "$STOCK/runtime/libruntime.a" -o "$BIN/$name"
}

# The programs that include a package's sources, to test what no importer can reach. They
# are built from the sources here whatever the packages were built from, so they say
# nothing of a release.
if [[ "$mode" != released ]]; then
  program shared-tests    packages/shared/tests/main.🍇
  program crypto-tests    packages/crypto/tests/main.🍇
  program deflate-tests   packages/deflate/tests/main.🍇
  program grapevine-tests packages/grapevine/tests/unit/main.🍇
  program grapevine-fuzz  packages/grapevine/tests/fuzz/main.🍇
fi
# The programs that import a package, as whoever uses one does. A release is tried by these.
program crypto-tool    packages/crypto/tests/tool.🍇 files
program deflate-tool    packages/deflate/tests/tool.🍇 files
program wire-host       packages/grapevine/tests/host/main.🍇
program todo-api        samples/todo/main.🍇
program app-tests       samples/todo/tests.🍇
echo "built: $(ls "$BIN" | tr '\n' ' ')"

# A build from releases has not built the programs that include a package's sources, so
# their suites, and the two checks of the sources themselves, are for ./build.sh test alone.
if [[ "$mode" == test ]]; then
  echo; echo "── lint"; ./tests/lint-test.sh; ./tests/lint.sh
  # A release of a package is its own folder and nothing above it, so each has to hold all
  # that it is built from. The first of the two tests the check, the second runs it.
  echo; echo "── packages"; ./tests/packages-test.sh; ./tests/packages.sh
  echo; echo "── shared: unit tests"; "$BIN/shared-tests"
  echo; echo "── crypto: unit tests"; "$BIN/crypto-tests"
  echo; echo "── deflate: unit tests"; "$BIN/deflate-tests"
  # One fixture has to have been changed at a known time, and neither git nor a copy keeps times.
  touch -d @784111777 packages/grapevine/tests/unit/files/served/a.txt
  # A file with a backslash in its name, which a repository that may be checked out on
  # Windows cannot hold. The tests need one to show that such a name is refused and not
  # merely absent.
  mkdir -p build/fixtures && printf 'backslash' > 'build/fixtures/back\slash.txt'
  # And a file that nobody may read. Outside the tree: where the tree is a folder shared
  # from a Mac, as it is under Docker there, a file in it can be read whatever its mode says.
  rm -rf /tmp/grapevine-fixtures && mkdir -m 755 /tmp/grapevine-fixtures \
    && printf 'locked' > /tmp/grapevine-fixtures/locked.txt && chmod 000 /tmp/grapevine-fixtures/locked.txt
  # Without the allocator's cache of freed blocks for each thread. A block that sits in it
  # is counted as in use, so the leak suite, which goes by that count, would see a few
  # kilobytes come and go that nobody holds.
  UNIT=(env GLIBC_TUNABLES=glibc.malloc.tcache_count=0 "$BIN/grapevine-tests")
  # Root may read a file whatever its permissions say, so only someone else can see what
  # the server does with a file that is there and may not be read. As root, which is who
  # the build is in its container, the suites that serve files are run once more as
  # another user. Anyone else is that other user already, and the suites are told so.
  if [[ "$(id -u)" == 0 ]]; then
    echo; echo "── grapevine: unit tests"; "${UNIT[@]}"
    echo; echo "── grapevine: file suites, as a user who is not root"
    setpriv --reuid=65534 --regid=65534 --clear-groups env UNPRIVILEGED=1 SUITES=files,statics "${UNIT[@]}"
  else
    echo; echo "── grapevine: unit tests"; UNPRIVILEGED=1 "${UNIT[@]}"
  fi
  # A misspelt suite name must not look like a run in which nothing failed.
  if SUITES=no-such-suite "$BIN/grapevine-tests" > /dev/null 2>&1; then
    echo "error: SUITES=no-such-suite ran nothing and passed" >&2; exit 1
  fi
  echo; echo "── grapevine: fuzz"; "$BIN/grapevine-fuzz"; FUZZ_MODE=json "$BIN/grapevine-fuzz"
fi

# The suites of the programs that import a package: what the packages do for whoever uses
# them, whether they were built from the sources here or from a release.
if [[ "$mode" != build ]]; then
  # The system's own tools, and not our own code, say whether a digest is right.
  echo; echo "── crypto: against the system's tools"; packages/crypto/tests/against.sh "$BIN/crypto-tool"
  # The system's gzip, and not our own code, says whether a stream can be read.
  echo; echo "── deflate: round trip through gzip"; packages/deflate/tests/roundtrip.sh "$BIN/deflate-tool"
  # Without the allocator's cache here too: the sample measures its own handlers for leaks.
  echo; echo "── sample: in-memory tests"; GLIBC_TUNABLES=glibc.malloc.tcache_count=0 "$BIN/app-tests"
  echo; echo "── sample: HTTP smoke test"; ./tests/smoke.sh
  echo; echo "── log lines under load"; ./tests/lines.sh
fi
