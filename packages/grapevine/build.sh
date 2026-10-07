#!/usr/bin/env bash
# Builds the grapevine package: libgrapevine.a and its interface file 🏛.
#   packages/grapevine/build.sh [output folder]     (default: this folder)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "${1:-$here}"
out="$(cd "${1:-$here}" && pwd)"
EC=${EC:-emojicodec}

"$EC" "$here/grapevine.🍇" -p grapevine -c -o "$out/grapevine.o" -i "$out/🏛"
ar rcs "$out/libgrapevine.a" "$out/grapevine.o"
rm -f "$out/grapevine.o"
