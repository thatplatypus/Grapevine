#!/usr/bin/env bash
# What the package computes is compared with what the system's own tools compute, for
# inputs that no published vector covers: a digest that is right for the examples of the
# standard and wrong for other lengths would pass every other test.
#   packages/crypto/tests/against.sh <crypto-tool>
set -uo pipefail
tool=${1:?usage: against.sh <crypto-tool>}
command -v sha256sum > /dev/null || { echo "against.sh: there is no sha256sum here to compare with" >&2; exit 2; }
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

echo "crypto/against: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
