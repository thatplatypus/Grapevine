#!/usr/bin/env bash
# Builds two packages, of which the second imports the first, and then a program that imports
# the second only.
cd "$(dirname "$0")" || exit 2
for name in inner outer; do
  emojicodec packages/$name/$name.🍇 -p $name -c -o packages/$name/$name.o -i packages/$name/🏛 || exit 3
  ar rcs packages/$name/lib$name.a packages/$name/$name.o
done
echo "both packages compiled"
# The compiler ends with 0 here though its linker failed, so its status says nothing.
emojicodec main.🍇
if [[ -x main ]]; then ./main; else echo "no program was linked"; fi
