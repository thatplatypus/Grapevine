#!/usr/bin/env bash
# Builds the grapevine package: libgrapevine.a and its interface file 🏛.
#   packages/grapevine/build.sh [output folder]     (default: this folder)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "${1:-$here}"
out="$(cd "${1:-$here}" && pwd)"
EC=${EC:-emojicodec}
INCLUDE=${EMOJICODE_INCLUDE:-/usr/local/include/emojicode}

"$EC" "$here/grapevine.🍇" -p grapevine -c -o "$out/grapevine.o" -i "$out/🏛"
c++ -std=c++17 -O2 -Wall -Wextra -c "$here/native/net.cpp" -I "$INCLUDE" -o "$out/net.o"
# A fresh archive every time: ar would otherwise keep members that no longer exist.
rm -f "$out/libgrapevine.a"
ar rcs "$out/libgrapevine.a" "$out/grapevine.o" "$out/net.o"
rm -f "$out/grapevine.o" "$out/net.o"
