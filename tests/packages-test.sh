#!/usr/bin/env bash
# Tests the check of the packages itself: a small tree that is right must pass, and each
# fault planted in a copy of it must be reported with its own words, and be all that is
# reported. Without this, a check that had stopped seeing anything would read as three
# packages in good order.
#   tests/packages-test.sh
set -uo pipefail
cd "$(dirname "$0")/.."
check="$PWD/tests/packages.sh"
# Without a folder of its own this would build its trees wherever it happens to be.
work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT
failures=0
cases=0
fail() { failures=$((failures + 1)); echo "  FAIL $1"; }

# manifest <folder> <package> [native]: a manifest as Packmoji writes one.
manifest() {
  {
    cat <<JSON
{
  "package": {
    "name": "@thatplatypus/$2",
    "version": "0.1.0",
    "kind": "library",
    "emojicode": ">=1.0.0-beta.2",
    "description": "A package of the tree that is right"
  },
  "build": {
    "entry": "$2.🍇",
    "sources": [
      "*.🍇"
    ]
JSON
    if [ "${3:-}" = native ]; then
      cat <<JSON
  },
  "native": {
    "sources": [
      "native/*.cpp"
    ],
    "link": [
      "pthread"
    ]
  }
}
JSON
    else
      printf '  }\n}\n'
    fi
  } > "$1/packmoji.json"
}

# package <tree> <name> [native]: a package that is right.
package() {
  local folder="$1/packages/$2"
  mkdir -p "$folder/tests"
  manifest "$folder" "$2" "${3:-}"
  printf '📜 🔤bytes.🍇🔤\n' > "$folder/$2.🍇"
  cp "$1/packages/shared/bytes.🍇" "$folder/bytes.🍇"
  cp "$1/LICENSE" "$folder/LICENSE"
  # A test is not released, so it may take a file from beside its package.
  printf '📜 🔤../../shared/check.🍇🔤\n' > "$folder/tests/main.🍇"
  if [ "${3:-}" = native ]; then
    mkdir -p "$folder/native"
    printf '#include "runtime/Runtime.h"\n#include <atomic>\n' > "$folder/native/net.cpp"
  fi
}

# All that the check looks at, and nothing more: a license, the byte helpers, and three
# packages, one of them with native code as grapevine has.
right="$work/right"
mkdir -p "$right/packages/shared"
printf 'the license\n' > "$right/LICENSE"
printf '💭 the byte helpers\n' > "$right/packages/shared/bytes.🍇"
package "$right" crypto
package "$right" deflate
package "$right" grapevine native

# plant <name>: a fresh copy of the tree that is right, for one case to spoil.
plant() { tree="$work/$1"; cp -R "$right" "$tree"; }

# change <file> <sed expression>: without sed's own way of writing a file in place, which
# is spelt differently on a Mac and on Linux.
change() { sed "$2" "$1" > "$1.changed" && mv "$1.changed" "$1"; }

# passes <case> [how many packages the last line says were checked]
passes() {
  cases=$((cases + 1))
  out=$(bash "$check" "$tree" 2>&1); status=$?
  if [ "$status" -ne 0 ]; then
    fail "$1: refused with status $status: $out"
  elif ! grep -qxF "packages: ${2:-3} checked, no problem found" <<< "$out"; then
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

# ── What is right

plant right-as-it-is
passes "a tree that is right, with a test that takes a file from beside its package"

plant a-fourth-package
package "$tree" jwt
passes "a fourth package that is right" 4

plant include-in-a-comment
printf '💭 📜 🔤../x.🍇🔤\n' >> "$tree/packages/crypto/crypto.🍇"
passes "an include that is only spoken of in a comment"

plant text-in-a-comment-after-an-include
printf '📜 🔤bytes.🍇🔤 💭 see 🔤docs/notes🔤\n' >> "$tree/packages/crypto/crypto.🍇"
passes "an include of its own file, with a text in the comment after it"

# As a checkout on Windows may leave it. Packmoji reads either kind of line end.
plant windows-line-ends
cr=$(printf '\r')
change "$tree/packages/crypto/packmoji.json" "s/\$/$cr/"
passes "a manifest with the line ends of Windows"

# Packmoji leaves a byte order mark out of account too.
plant byte-order-mark
{ printf '\357\273\277'; cat "$tree/packages/crypto/packmoji.json"; } > "$tree/packages/crypto/packmoji.json.changed"
mv "$tree/packages/crypto/packmoji.json.changed" "$tree/packages/crypto/packmoji.json"
passes "a manifest that begins with a byte order mark"

# A manifest is JSON however it is laid out, and is read as that.
plant manifest-on-one-line
printf '{"build":{"sources":["*.🍇"],"entry":"deflate.🍇"},"package":{"version":"0.1.0","name":"@thatplatypus/deflate"}}\n' > "$tree/packages/deflate/packmoji.json"
passes "a manifest on one line, with its keys in another order"

# ── The manifest

plant no-manifest
rm "$tree/packages/crypto/packmoji.json"
reports "a package with no manifest" "1 problem" "crypto: no packmoji.json"

plant not-json
printf '{ "package": {\n' > "$tree/packages/crypto/packmoji.json"
reports "a manifest that is not JSON" "1 problem" "crypto: packmoji.json cannot be read: it is not a JSON object"

plant wrong-name
change "$tree/packages/deflate/packmoji.json" 's|"name": "@thatplatypus/deflate"|"name": "@thatplatypus/crypto"|'
reports "a manifest that names another package" "1 problem" "deflate: packmoji.json names @thatplatypus/crypto, and this folder's package is @thatplatypus/deflate"

plant another-scope
change "$tree/packages/crypto/packmoji.json" 's|"name": "@thatplatypus/crypto"|"name": "@someoneelse/crypto"|'
reports "a manifest under another scope" "1 problem" "crypto: packmoji.json names @someoneelse/crypto, and this folder's package is @thatplatypus/crypto"

plant no-name
change "$tree/packages/crypto/packmoji.json" '/"name"/d'
reports "a manifest with no name" "1 problem" "crypto: packmoji.json names nothing, and this folder's package is @thatplatypus/crypto"

plant no-entry
change "$tree/packages/grapevine/packmoji.json" '/"entry"/d'
reports "a manifest with no entry" "1 problem" "grapevine: packmoji.json names no entry"

plant entry-not-there
change "$tree/packages/grapevine/packmoji.json" 's|"entry": "grapevine.🍇"|"entry": "main.🍇"|'
reports "an entry that is not there" "1 problem" "grapevine: the entry main.🍇 is not there"

# The file is there, and a release would not hold it.
plant entry-below-the-top
change "$tree/packages/grapevine/packmoji.json" 's|"entry": "grapevine.🍇"|"entry": "tests/main.🍇"|'
reports "an entry that is not at the top of the folder" "1 problem" "grapevine: the entry tests/main.🍇 is not at the top of the package's folder"

plant other-sources
change "$tree/packages/deflate/packmoji.json" 's|"\*\.🍇"|"src/**/*.🍇"|'
reports "sources that are looked for somewhere else" "1 problem" "deflate: packmoji.json gives src/**/*.🍇 as its sources, and this check goes by *.🍇"

# Packmoji then looks under src/, where this package has nothing.
plant no-sources
printf '{"package":{"name":"@thatplatypus/deflate"},"build":{"entry":"deflate.🍇"}}\n' > "$tree/packages/deflate/packmoji.json"
reports "a manifest that gives no sources" "1 problem" "deflate: packmoji.json gives no sources, and this check goes by *.🍇"

plant two-sources
printf '{"package":{"name":"@thatplatypus/deflate"},"build":{"entry":"deflate.🍇","sources":["*.🍇","more/*.🍇"]}}\n' > "$tree/packages/deflate/packmoji.json"
reports "sources in two places" "1 problem" "deflate: packmoji.json gives *.🍇, more/*.🍇 as its sources, and this check goes by *.🍇"

# ── The copies

plant bytes-missing
rm "$tree/packages/crypto/bytes.🍇"
reports "a package without the byte helpers" "1 problem" "crypto: bytes.🍇 is missing"

plant bytes-differ
printf '💭 changed here and nowhere else\n' >> "$tree/packages/deflate/bytes.🍇"
reports "byte helpers that were changed in one package" "1 problem" "deflate: bytes.🍇 differs from packages/shared/bytes.🍇: edit that one, then copy it over this"

# What a tidy person does with three copies. A release would then hold a link.
plant bytes-linked
rm "$tree/packages/crypto/bytes.🍇"
ln -s ../shared/bytes.🍇 "$tree/packages/crypto/bytes.🍇"
reports "byte helpers that are a link to the shared ones" "1 problem" "crypto: bytes.🍇 is a link, and a release has to hold the file itself"

plant license-missing
rm "$tree/packages/grapevine/LICENSE"
reports "a package without a license" "1 problem" "grapevine: LICENSE is missing"

plant license-differs
printf 'and one more condition\n' >> "$tree/packages/crypto/LICENSE"
reports "a license that was changed in one package" "1 problem" "crypto: LICENSE differs from the LICENSE at the root: edit that one, then copy it over this"

plant license-linked
rm "$tree/packages/deflate/LICENSE"
ln -s ../../LICENSE "$tree/packages/deflate/LICENSE"
reports "a license that is a link to the one at the root" "1 problem" "deflate: LICENSE is a link, and a release has to hold the file itself"

# Said once, and not as three copies that differ from nothing.
plant shared-bytes-gone
rm "$tree/packages/shared/bytes.🍇"
reports "the shared byte helpers themselves gone" "1 problem" "packages/shared/bytes.🍇 is missing, which every package has a copy of"

plant root-license-gone
rm "$tree/LICENSE"
reports "the license at the root gone" "1 problem" "the LICENSE at the root is missing, which every package has a copy of"

# ── What a source includes

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

plant include-of-another-kind
printf '📜 🔤helper.emojic🔤\n' >> "$tree/packages/crypto/crypto.🍇"
reports "an include of a file that the sources do not take" "1 problem" "crypto: packages/crypto/crypto.🍇:2 includes helper.emojic, which *.🍇 does not take"

# A filter that dropped every line with a comment on it would let this through.
plant include-before-a-comment
printf '📜 🔤../shared/x.🍇🔤 💭 for now\n' >> "$tree/packages/crypto/crypto.🍇"
reports "an include with a comment after it" "1 problem" "crypto: packages/crypto/crypto.🍇:2 includes ../shared/x.🍇, which"

plant two-includes-on-a-line
printf '📜 🔤bytes.🍇🔤 📜 🔤../x.🍇🔤\n' >> "$tree/packages/crypto/crypto.🍇"
reports "a second include on one line" "1 problem" "crypto: packages/crypto/crypto.🍇:2 includes ../x.🍇, which"

# The compiler takes all of these between the two signs.
plant include-with-no-space
printf '📜🔤../x.🍇🔤\n' >> "$tree/packages/crypto/crypto.🍇"
reports "an include with nothing between its two signs" "1 problem" "crypto: packages/crypto/crypto.🍇:2 includes ../x.🍇, which"

plant include-after-a-tab
printf '📜\t  🔤../x.🍇🔤\n' >> "$tree/packages/crypto/crypto.🍇"
reports "an include with a tab and spaces between its two signs" "1 problem" "crypto: packages/crypto/crypto.🍇:2 includes ../x.🍇, which"

plant include-after-a-no-break-space
printf '📜\302\240🔤../x.🍇🔤\n' >> "$tree/packages/crypto/crypto.🍇"
reports "an include with a no-break space between its two signs" "1 problem" "crypto: packages/crypto/crypto.🍇:2 includes ../x.🍇, which"

plant include-after-a-variation-selector
printf '📜\357\270\217 🔤../x.🍇🔤\n' >> "$tree/packages/crypto/crypto.🍇"
reports "an include whose sign is followed by a variation selector" "1 problem" "crypto: packages/crypto/crypto.🍇:2 includes ../x.🍇, which"

# ── Native code

plant native-with-no-section
mkdir "$tree/packages/crypto/native"
printf '#include <atomic>\n' > "$tree/packages/crypto/native/fast.cpp"
reports "a native folder that the manifest says nothing of" "1 problem" "crypto: has a native folder, and packmoji.json has no native section"

plant section-with-no-native
rm -r "$tree/packages/grapevine/native"
reports "a native section with no folder" "1 problem" "grapevine: packmoji.json has a native section, and there is no native folder"

plant other-native-sources
change "$tree/packages/grapevine/packmoji.json" 's|"native/\*\.cpp"|"native/**/*.cpp"|'
reports "native sources that are looked for somewhere else" "1 problem" "grapevine: packmoji.json gives native/**/*.cpp as its native sources, and this check goes by native/*.cpp"

# A section that names no file of its own.
plant no-native-sources
printf '{"package":{"name":"@thatplatypus/grapevine"},"build":{"entry":"grapevine.🍇","sources":["*.🍇"]},"native":{"link":["pthread"]}}\n' > "$tree/packages/grapevine/packmoji.json"
reports "a native section that gives no sources" "1 problem" "grapevine: packmoji.json gives no native sources, and this check goes by native/*.cpp"

plant header-in-native
printf '#include "shim.h"\n' >> "$tree/packages/grapevine/native/net.cpp"
printf '// a header\n' > "$tree/packages/grapevine/native/shim.h"
reports "a header beside the native file" "1 problem" "grapevine: native/shim.h is not taken by native/*.cpp, so a release would leave it out"

plant native-below-the-top
mkdir "$tree/packages/grapevine/native/more"
printf '#include <atomic>\n' > "$tree/packages/grapevine/native/more/second.cpp"
reports "a native file in a folder below" "1 problem" "grapevine: native/more/second.cpp is not taken by native/*.cpp, so a release would leave it out"

plant native-include-from-outside
printf '#include <atomic>\n  #  include "../../shared/other.h"\n' > "$tree/packages/grapevine/native/net.cpp"
reports "a native include that leaves the native folder" "1 problem" "grapevine: packages/grapevine/native/net.cpp:2 includes ../../shared/other.h, which is outside the package's native folder"

# ── Which folders are packages

# The lint lets any folder under packages/ keep unsafe code in a bytes.🍇. This holds each
# of those to the shared one, and to everything else that is asked of a package.
plant a-folder-of-byte-helpers
mkdir "$tree/packages/jwt"
printf '💭 byte helpers of its own\n' > "$tree/packages/jwt/bytes.🍇"
reports "a fourth folder, with nothing but byte helpers of its own" "3 problems" "jwt: bytes.🍇 differs from packages/shared/bytes.🍇"

plant no-package
rm -r "$tree/packages/crypto" "$tree/packages/deflate" "$tree/packages/grapevine"
reports "no package at all" "1 problem" "no package under packages/"

plant two-faults
rm "$tree/packages/crypto/packmoji.json" "$tree/packages/deflate/bytes.🍇"
reports "two faults at once" "2 problems" "deflate: bytes.🍇 is missing"

cases=$((cases + 1))
out=$(bash "$check" "$work/no-such-tree" 2>&1); status=$?
[ "$status" -eq 2 ] || fail "a root that is not there: status $status, not 2: $out"

if [ "$failures" -gt 0 ]; then
  echo "packages-test: $failures failed"
  exit 1
fi
echo "packages-test: $cases cases"
