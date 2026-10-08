#!/usr/bin/env bash
# What the package computes is compared with what the system's own tools compute, for
# inputs that no published vector covers: a digest that is right for the examples of the
# standard and wrong for other lengths would pass every other test.
#   packages/crypto/tests/against.sh <crypto-tool>
set -uo pipefail
tool=${1:?usage: against.sh <crypto-tool>}
command -v sha256sum > /dev/null || { echo "against.sh: there is no sha256sum here to compare with" >&2; exit 2; }
command -v openssl > /dev/null || { echo "against.sh: there is no openssl here to compare with" >&2; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
passed=0
failed=0

good() { passed=$((passed + 1)); }
bad() { failed=$((failed + 1)); echo "  FAIL crypto/against: $1"; }

# digest <what it is> <file>: the tool's SHA-256 of the file is sha256sum's.
digest() {
  local ours theirs
  ours=$("$tool" sha256 "$2")
  theirs=$(sha256sum "$2" | cut -d' ' -f1)
  if [ -n "$ours" ] && [ "$ours" = "$theirs" ]; then good; else bad "$1: the digest is $ours, and sha256sum says $theirs"; fi
}

# Bytes of every value, new each time: what is asked holds for any.
head -c 100000 /dev/urandom > "$work/noise"
for length in $(seq 0 130); do
  head -c "$length" "$work/noise" > "$work/piece"
  digest "$length bytes" "$work/piece"
done
head -c 1000 "$work/noise" > "$work/piece"
digest "1,000 bytes" "$work/piece"
digest "100,000 bytes" "$work/noise"
cat "$root"/packages/*/*.🍇 "$root"/packages/*/README.md "$root"/packages/*/*.🍇 | head -c 1048576 > "$work/sources"
digest "a megabyte of sources" "$work/sources"

# signed <what it is> <key file> <file>: the tool's HMAC-SHA-256 is openssl's.
signed() {
  local ours theirs
  ours=$("$tool" hmac "$2" "$3")
  theirs=$(openssl dgst -sha256 -mac HMAC -macopt "hexkey:$(od -An -tx1 -v "$2" | tr -d ' \n')" "$3" | sed 's/^.*= //')
  if [ -n "$ours" ] && [ "$ours" = "$theirs" ]; then good; else bad "$1: the signature is $ours, and openssl says $theirs"; fi
}

# Keys around the length of a block, which is where a key begins to be hashed first.
for keyLength in 1 31 32 33 63 64 65 200; do
  tail -c "$keyLength" "$work/noise" > "$work/key"
  for length in 0 1 64 1000; do
    head -c "$length" "$work/noise" > "$work/piece"
    signed "a key of $keyLength bytes, a message of $length" "$work/key" "$work/piece"
  done
done

# How long. Generous bounds: they are there to notice a hash that has become ten times
# slower, on a machine that is doing other things as well.
took() {
  local began
  began=$(date +%s%N)
  "$tool" "$@" > /dev/null
  echo $(( ($(date +%s%N) - began) / 1000000 ))
}
megabyte=$(took sha256 "$work/sources")
if [ "$megabyte" -lt 10000 ]; then good; else bad "a megabyte took $megabyte ms to hash"; fi
head -c 32 "$work/noise" > "$work/key"
head -c 200 "$work/noise" > "$work/piece"
thousand=$(took hmacs "$work/key" "$work/piece")
if [ "$thousand" -lt 10000 ]; then good; else bad "a thousand signatures of 200 bytes took $thousand ms"; fi

echo "crypto/against: $passed passed, $failed failed (a megabyte was hashed in $megabyte ms, and 200 bytes were signed a thousand times in $thousand ms)"
[ "$failed" -eq 0 ]
