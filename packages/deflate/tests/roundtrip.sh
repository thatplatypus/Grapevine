#!/usr/bin/env bash
# What the compressor writes is given to the system's gzip, which is not ours, and what
# comes back is compared with what went in. A stream that only our own code could read
# would pass every other test there is.
#   packages/deflate/tests/roundtrip.sh <deflate-tool>
set -uo pipefail
tool=${1:?usage: roundtrip.sh <deflate-tool>}
command -v gzip > /dev/null || { echo "roundtrip.sh: there is no gzip here to read the streams" >&2; exit 2; }
command -v perl > /dev/null || { echo "roundtrip.sh: there is no perl here to turn the tool's digits into bytes" >&2; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
passed=0
failed=0

good() { passed=$((passed + 1)); }
bad() { failed=$((failed + 1)); echo "  FAIL deflate/roundtrip: $1"; }

# stream <file> <where to>: the file's stream, as the bytes the tool's digits stand for.
stream() { "$tool" hex "$1" | perl -ne 'chomp; print pack("H*", $_)' > "$2"; }

# trip <what it is> <file>: gzip accepts the file's stream, and reads the file back out of it.
trip() {
  if ! stream "$2" "$work/out.gz"; then bad "$1: the tool failed"; return; fi
  if ! gzip -t "$work/out.gz" 2>/dev/null; then bad "$1: gzip does not accept the stream"; return; fi
  if gzip -dc "$work/out.gz" 2>/dev/null | cmp -s - "$2"; then good; else bad "$1: gzip reads back something else"; fi
}

# Fixtures. The random ones are new each time: what is asked of them holds for any.
: > "$work/nothing"
printf 'a' > "$work/one"
for value in $(seq 0 255); do printf "\\$(printf '%03o' "$value")"; done > "$work/every"
cp "$here/../README.md" "$work/prose"
head -c 100000 /dev/zero | tr '\0' 'a' > "$work/letter"
head -c 300000 /dev/urandom > "$work/noise"
cat "$root"/packages/*/*.🍇 "$root"/packages/*/README.md "$root"/packages/*/*.🍇 | head -c 1048576 > "$work/sources"

trip "nothing" "$work/nothing"
trip "one byte" "$work/one"
trip "every value a byte can have" "$work/every"
trip "prose" "$work/prose"
trip "a hundred thousand of one letter" "$work/letter"
trip "bytes without pattern" "$work/noise"
trip "a megabyte of sources" "$work/sources"

echo "deflate/roundtrip: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
