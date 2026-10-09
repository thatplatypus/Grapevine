#!/usr/bin/env bash
# Tests the check of the packages itself: a small tree that is right must pass, and each
# fault planted in a copy of it must be reported with its own words, and be all that is
# reported. Without this, a check that had stopped seeing anything would read as three
# packages in good order.
#   tests/packages-test.sh
set -uo pipefail
cd "$(dirname "$0")/.."
check="$PWD/tests/packages.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
cases=0
fail() { failures=$((failures + 1)); echo "  FAIL $1"; }

# All that the check looks at, and nothing more: a license, the byte helpers, and three
# packages that each have a manifest, an entry that includes its own copy of the helpers,
# the two copies, and a test.
right="$work/right"
mkdir -p "$right/packages/shared"
printf 'the license\n' > "$right/LICENSE"
printf '💭 the byte helpers\n' > "$right/packages/shared/bytes.🍇"
for package in crypto deflate grapevine; do
  folder="$right/packages/$package"
  mkdir -p "$folder/tests"
  cat > "$folder/packmoji.json" <<JSON
{
  "package": {
    "name": "@thatplatypus/$package",
    "version": "0.1.0",
    "kind": "library",
    "emojicode": ">=1.0.0-beta.2",
    "description": "A package of the tree that is right"
  },
  "build": {
    "entry": "$package.🍇",
    "sources": [
      "*.🍇"
    ]
  }
}
JSON
  printf '📜 🔤bytes.🍇🔤\n' > "$folder/$package.🍇"
  cp "$right/packages/shared/bytes.🍇" "$folder/bytes.🍇"
  cp "$right/LICENSE" "$folder/LICENSE"
  # A test is not released, so it may take a file from beside its package.
  printf '📜 🔤../../shared/check.🍇🔤\n' > "$folder/tests/main.🍇"
done

# plant <name>: a fresh copy of the tree that is right, for one case to spoil.
plant() { tree="$work/$1"; cp -R "$right" "$tree"; }

# change <file> <sed expression>: without sed's own way of writing a file in place, which
# is spelt differently on a Mac and on Linux.
change() { sed "$2" "$1" > "$1.changed" && mv "$1.changed" "$1"; }

# passes <case>
passes() {
  cases=$((cases + 1))
  out=$(bash "$check" "$tree" 2>&1); status=$?
  if [ "$status" -ne 0 ]; then
    fail "$1: refused with status $status: $out"
  elif ! grep -qxF "packages: each fit to be released by itself" <<< "$out"; then
    fail "$1: passed without saying so: $out"
  fi
}

# reports <case> <count, as the last line says it> <words>
reports() {
  cases=$((cases + 1))
  out=$(bash "$check" "$tree" 2>&1); status=$?
  [ "$status" -eq 1 ] || fail "$1: status $status, not 1: $out"
  grep -qF -- "$3" <<< "$out" || fail "$1: not reported with \"$3\": $out"
  grep -qxF -- "packages: $2" <<< "$out" || fail "$1: not \"packages: $2\": $out"
}

plant right-as-it-is
passes "a tree that is right, with a test that takes a file from beside its package"

plant include-in-a-comment
printf '💭 📜 🔤../x.🍇🔤\n' >> "$tree/packages/crypto/crypto.🍇"
passes "an include that is only spoken of in a comment"

# As a checkout on Windows may leave it. Packmoji reads either kind of line end.
plant windows-line-ends
cr=$(printf '\r')
change "$tree/packages/crypto/packmoji.json" "s/\$/$cr/"
passes "a manifest with the line ends of Windows"

plant no-manifest
rm "$tree/packages/crypto/packmoji.json"
reports "a package with no manifest" "1 problem" "crypto: no packmoji.json"

plant wrong-name
change "$tree/packages/deflate/packmoji.json" 's|"name": "@thatplatypus/deflate"|"name": "@thatplatypus/crypto"|'
reports "a manifest that names another package" "1 problem" "deflate: packmoji.json names @thatplatypus/crypto, and the folder is deflate"

plant no-entry
change "$tree/packages/grapevine/packmoji.json" '/"entry"/d'
reports "a manifest with no entry" "1 problem" "grapevine: packmoji.json names no entry"

plant entry-not-there
change "$tree/packages/grapevine/packmoji.json" 's|"entry": "grapevine.🍇"|"entry": "main.🍇"|'
reports "an entry that is not there" "1 problem" "grapevine: the entry main.🍇 is not there"

plant bytes-missing
rm "$tree/packages/crypto/bytes.🍇"
reports "a package without the byte helpers" "1 problem" "crypto: bytes.🍇 is missing"

plant bytes-differ
printf '💭 changed here and nowhere else\n' >> "$tree/packages/deflate/bytes.🍇"
reports "byte helpers that were changed in one package" "1 problem" "deflate: bytes.🍇 differs from packages/shared/bytes.🍇: copy that one over it"

plant license-missing
rm "$tree/packages/grapevine/LICENSE"
reports "a package without a license" "1 problem" "grapevine: LICENSE is missing"

plant license-differs
printf 'and one more condition\n' >> "$tree/packages/crypto/LICENSE"
reports "a license that was changed in one package" "1 problem" "crypto: LICENSE differs from the LICENSE at the root: copy that one over it"

plant include-from-beside
printf '📜 🔤../shared/bytes.🍇🔤\n' > "$tree/packages/deflate/deflate.🍇"
reports "an include from beside the package" "1 problem" "deflate: packages/deflate/deflate.🍇:1 includes ../shared/bytes.🍇, which is not at the top of the package's folder"

# In a file that is not the entry: every source at the top of the folder is read.
plant include-from-below
printf '💭 more\n📜 🔤parts/more.🍇🔤\n' > "$tree/packages/grapevine/extra.🍇"
reports "an include from a folder below, which a release would leave out" "1 problem" "grapevine: packages/grapevine/extra.🍇:2 includes parts/more.🍇, which is not at the top of the package's folder"

plant absolute-include
printf '📜 🔤/etc/x.🍇🔤\n' >> "$tree/packages/crypto/crypto.🍇"
reports "an include by a whole path" "1 problem" "crypto: packages/crypto/crypto.🍇:2 includes /etc/x.🍇, which is not at the top of the package's folder"

plant include-with-no-space
printf '📜🔤../x.🍇🔤\n' >> "$tree/packages/crypto/crypto.🍇"
reports "an include with nothing between its two signs" "1 problem" "crypto: packages/crypto/crypto.🍇:2 includes ../x.🍇"

plant include-after-a-tab
printf '📜\t  🔤../x.🍇🔤\n' >> "$tree/packages/crypto/crypto.🍇"
reports "an include with a tab and spaces between its two signs" "1 problem" "crypto: packages/crypto/crypto.🍇:2 includes ../x.🍇"

plant two-faults
rm "$tree/packages/crypto/packmoji.json" "$tree/packages/deflate/bytes.🍇"
reports "two faults at once" "2 problems" "deflate: bytes.🍇 is missing"

if [ "$failures" -gt 0 ]; then
  echo "packages-test: $failures failed"
  exit 1
fi
echo "packages-test: $cases cases"
