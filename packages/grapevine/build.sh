#!/usr/bin/env bash
# Builds the grapevine package: libgrapevine.a and its interface file 🏛.
#   packages/grapevine/build.sh [output folder] [folder of the sources]     (default for both: this folder)
# The second is for a release of the package, which holds its sources and not this script.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "${1:-$here}"
out="$(cd "${1:-$here}" && pwd)"
from="$(cd "${2:-$here}" && pwd)"
EC=${EC:-emojicodec}
INCLUDE=${EMOJICODE_INCLUDE:-/usr/local/include/emojicode}

# The package imports crypto and deflate, which have to be built first, beside this one.
# The compiler takes the first folder of a package's name that it finds, and looks under
# ./packages of the folder it runs in before anywhere it is told of, so it is run from a
# folder that has no such thing and pointed at the built packages.
packages="$(dirname "$out")"
for needed in crypto deflate; do
  if [ ! -f "$packages/$needed/🏛" ]; then
    echo "grapevine: build the $needed package first, beside this one: packages/$needed/build.sh $packages/$needed" >&2
    exit 1
  fi
done
( cd "$out" && "$EC" -S "$packages" "$from/grapevine.🍇" -p grapevine -c -o "$out/grapevine.o" -i "$out/🏛" ) 2>&1 | tee "$out/compile.log"
# The compiler checks the code it generated, says "Detected in:" when the check fails, and
# exits 0 all the same. What it built then crashes when it runs.
if grep -q "Detected in:" "$out/compile.log"; then
  echo "grapevine: the compiler generated code that its own check refuses, named above" >&2
  exit 1
fi
rm -f "$out/compile.log"
c++ -std=c++17 -O2 -Wall -Wextra -c "$from/native/net.cpp" -I "$INCLUDE" -o "$out/net.o"
# A fresh archive every time: ar would otherwise keep members that no longer exist.
rm -f "$out/libgrapevine.a"
ar rcs "$out/libgrapevine.a" "$out/grapevine.o" "$out/net.o"
rm -f "$out/grapevine.o" "$out/net.o"
