#!/usr/bin/env bash
# What the compressor writes is given to the system's gzip, which is not ours, and what
# comes back is compared with what went in. A stream that only our own code could read
# would pass every other test there is.
#   packages/deflate/tests/roundtrip.sh <deflate-tool>
set -uo pipefail
tool=${1:?usage: roundtrip.sh <deflate-tool>}
command -v gzip > /dev/null || { echo "roundtrip.sh: there is no gzip here to read the streams" >&2; exit 2; }
command -v perl > /dev/null || { echo "roundtrip.sh: there is no perl here to turn the tool's digits into bytes" >&2; exit 2; }
command -v shuf > /dev/null || { echo "roundtrip.sh: there is no shuf here to make a fixture with" >&2; exit 2; }
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

# packed <file>: how many bytes the file's stream has.
packed() { stream "$1" "$work/sized.gz" && stat -c %s "$work/sized.gz"; }

# below <what it is> <number> <bound>
below() { if [ "$2" -lt "$3" ]; then good; else bad "$1: $2 is not below $3"; fi; }

# took <file>: the milliseconds the tool takes to compress the file, and write nothing.
took() {
  local began
  began=$(date +%s%N)
  "$tool" quiet "$1"
  echo $(( ($(date +%s%N) - began) / 1000000 ))
}

# Fixtures. The random ones are new each time: what is asked of them holds for any.
: > "$work/nothing"
printf 'a' > "$work/one"
for value in $(seq 0 255); do printf "\\$(printf '%03o' "$value")"; done > "$work/every"
cp "$root/README.md" "$work/prose"
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

# What repeats can get wrong: the longest repeat there is and one more, a repeat as far
# back as one may reach and one byte further, a repeat that reaches into itself, input
# too short to hold a repeat, and input that ends just after one.
for run in 258 259 260 516; do
  head -c "$run" /dev/zero | tr '\0' 'x' > "$work/run"
  trip "a run of $run" "$work/run"
  { printf 'q'; cat "$work/run"; printf 'q'; } > "$work/framed"
  trip "a run of $run between two other bytes" "$work/framed"
done
head -c 1000 /dev/urandom > "$work/block"
cat "$work/block" "$work/block" > "$work/twice"
trip "a block and then the same block" "$work/twice"
head -c 31768 /dev/urandom > "$work/filler"
cat "$work/block" "$work/filler" "$work/block" > "$work/reach"
{ cat "$work/block" "$work/filler"; printf 'z'; cat "$work/block"; } > "$work/past"
trip "a block again 32768 bytes on" "$work/reach"
trip "a block again 32769 bytes on" "$work/past"
yes abc | tr -d '\n' | head -c 15000 > "$work/overlap"
trip "three letters over and over" "$work/overlap"
for length in $(seq 0 20); do
  head -c "$length" "$work/prose" > "$work/short"
  trip "the first $length bytes of prose" "$work/short"
done
printf 'abcdefghabcdefghx' > "$work/after1"
printf 'abcdefghabcdefghxy' > "$work/after2"
trip "input that ends one byte after a repeat" "$work/after1"
trip "input that ends two bytes after a repeat" "$work/after2"

# How much smaller.
# A text that does not change, and the size its stream had when this was written. A
# larger one means that the search finds fewer repeats than it did, or shorter ones.
trip "the fixed prose" "$here/prose.txt"
below "the fixed prose, against one byte more than its stream has had" "$(packed "$here/prose.txt")" 1321
below "a hundred thousand of one letter" "$(packed "$work/letter")" 700
below "prose, five times its stream against three times itself" "$(( $(packed "$work/prose") * 5 ))" "$(( $(stat -c %s "$work/prose") * 3 ))"
below "bytes without pattern, against themselves and an eighth" "$(packed "$work/noise")" "$(( 300000 + 300000 / 8 ))"
below "a block and then the same block, against the block twice" "$(packed "$work/twice")" 1300
# A copy as far back as a repeat may reach is found. One byte further it is not, and the
# stream holds the block twice.
below "a block again 32768 bytes on, against one that is out of reach" "$(( $(packed "$work/reach") + 900 ))" "$(packed "$work/past")"

# How long. A search looks at a bounded number of places, so input made to keep it busy
# costs no more than text does: a megabyte of one byte, and a megabyte of triples that
# all get one number in the table of places (see the package's 🔭).
head -c 1048576 /dev/zero | tr '\0' 'a' > "$work/same"
for low in 0 1 2 3 4 5 6 7; do for high in 0 32 64 96 128 160 192 224; do for next in 0 1 2 3 4 5 6 7; do
  printf '\\%03o\\%03o\\%03o\n' $((low + high)) $(((low << 5) + next)) $((next << 5))
done; done; done > "$work/triples"
printf "$(shuf -r -n 349526 "$work/triples" | tr -d '\n')" | head -c 1048576 > "$work/alike"
trip "a megabyte of one byte" "$work/same"
trip "a megabyte of triples with one number" "$work/alike"
text=$(took "$work/sources")
below "a megabyte of text, in milliseconds" "$text" 10000
below "a megabyte of one byte, in milliseconds, against twice the text's" "$(took "$work/same")" "$((text * 2 + 200))"
below "a megabyte of triples with one number, in milliseconds, against twice the text's" "$(took "$work/alike")" "$((text * 2 + 200))"

echo "deflate/roundtrip: $passed passed, $failed failed (a megabyte of text took $text ms)"
[ "$failed" -eq 0 ]
