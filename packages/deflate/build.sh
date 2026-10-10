#!/usr/bin/env bash
# Builds the deflate package: libdeflate.a and its interface file 🏛.
#   packages/deflate/build.sh [output folder] [folder of the sources]     (default for both: this folder)
# The second is for a release of the package, which holds its sources and not this script.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "${1:-$here}"
out="$(cd "${1:-$here}" && pwd)"
from="$(cd "${2:-$here}" && pwd)"
EC=${EC:-emojicodec}

"$EC" "$from/deflate.🍇" -p deflate -c -o "$out/deflate.o" -i "$out/🏛" 2>&1 | tee "$out/compile.log"
# The compiler checks the code it generated, says "Detected in:" when the check fails, and
# exits 0 all the same. What it built then crashes when it runs.
if grep -q "Detected in:" "$out/compile.log"; then
  echo "deflate: the compiler generated code that its own check refuses, named above" >&2
  exit 1
fi
rm -f "$out/compile.log"
# A fresh archive every time: ar would otherwise keep members that no longer exist.
rm -f "$out/libdeflate.a"
ar rcs "$out/libdeflate.a" "$out/deflate.o"
rm -f "$out/deflate.o"
