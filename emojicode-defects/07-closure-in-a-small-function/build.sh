#!/usr/bin/env bash
# Builds the package, which compiles, and then the program that imports it, which does not.
cd "$(dirname "$0")" || exit 2
emojicodec packages/tally/tally.🍇 -p tally -c -o packages/tally/tally.o -i packages/tally/🏛 || exit 3
ar rcs packages/tally/libtally.a packages/tally/tally.o
echo "the package compiled"
emojicodec main.🍇
