#!/usr/bin/env bash
# Checks how numbers are read and written against Python, whose conversions between text and
# reals are correctly rounded: 200,000 literals read and 100,000 reals written, each compared
# bit for bit. The unit tests hold a hundred or so of these; this is the long version.
#   tests/numbers.sh          the usual numbers
#   tests/numbers.sh 7        another seed, so other numbers
# Needs Python 3 on this machine and the grapevine image. ./build.sh test needs neither,
# and does not run this.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/numbers
python3 tests/numbers/gen.py "${1:-20261007}" build/numbers
docker run --rm --platform linux/amd64 -v "$PWD":/src -w /src grapevine bash -c '
  set -e
  [ -f build/packages/grapevine/libgrapevine.a ] || ./build.sh > /dev/null
  cd build
  emojicodec /src/tests/numbers/probe.🍇 -c -o obj/numbers-probe.o
  P=${EMOJICODE_PACKAGES_PATH:-/usr/local/EmojicodePackages}
  c++ obj/numbers-probe.o -Wl,--start-group packages/grapevine/libgrapevine.a -Wl,--end-group \
    "$P/s/libs.a" -lm -lpthread "$P/runtime/libruntime.a" -o bin/numbers-probe
  ./bin/numbers-probe'
