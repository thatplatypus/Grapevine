#!/usr/bin/env bash
# Tests the rehearsal of a release itself: a small repository that is right must pass, and
# each fault planted in a copy of it must be reported with its own words. Without this, a
# rehearsal that had stopped seeing anything would read as packages fit to be released.
#
# The repository is made up: two packages of a few lines, of which the one that is named
# as the real repository is needs the other. Nothing is compiled here, so their sources
# need not be Emojicode that builds.
#   tests/release-test.sh
# Needs what tests/release.sh needs: a pmj (PMJ, or on the PATH), git, perl and python3.
set -uo pipefail
pmj=${PMJ:-pmj}
case "$pmj" in
  /*) ;;
  */*) pmj="$PWD/$pmj" ;;
  *) pmj=$(command -v "$pmj" || true) ;;
esac
if [ -z "$pmj" ] || [ ! -x "$pmj" ]; then
  echo "release-test: there is no pmj to pack with. Name one with PMJ, or put one on the PATH" >&2
  exit 2
fi
export PMJ="$pmj"
cd "$(dirname "$0")/.." || exit 2
check="$PWD/tests/release.sh"

# git as it is with nobody's settings: no signing, no hooks, and an author of its own.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=release-test GIT_AUTHOR_EMAIL=release-test@example.invalid
export GIT_COMMITTER_NAME=release-test GIT_COMMITTER_EMAIL=release-test@example.invalid

# Every tree is under a folder with a space in its name, as a checkout may be.
made=$(mktemp -d) || exit 2
work="$made/a checkout"
mkdir "$work" || exit 2
trap 'rm -rf "$made"' EXIT
failures=0
cases=0
fail() { failures=$((failures + 1)); echo "  FAIL $1"; }

# manifest <folder> <name> <version> [<needed> <at>]: a manifest as Packmoji writes one.
manifest() {
  {
    cat <<JSON
{
  "package": {
    "name": "@thatplatypus/$2",
    "version": "$3",
    "kind": "library",
    "emojicode": ">=1.0.0-beta.2",
    "repository": "github.com/thatplatypus/grapevine"
  },
JSON
    if [ -n "${4:-}" ]; then
      cat <<JSON
  "dependencies": {
    "@thatplatypus/$4": "$5"
  },
JSON
    fi
    cat <<JSON
  "build": {
    "entry": "$2.🍇",
    "sources": [
      "*.🍇"
    ]
  },
  "native": {
    "sources": [
      "native/*.cpp"
    ]
  }
}
JSON
  } > "$1/packmoji.json"
}

# commit <tree> <what for>: everything in the tree, as one commit.
commit() { git -C "$1" add -A && git -C "$1" commit --quiet -m "$2"; }

# A repository that is right: a folder that is no package, a package that needs nothing,
# and the package named as the real repository is, which needs the other. Each has a file
# below the top of its folder that a release holds, as grapevine's native file is.
right="$work/right"
mkdir -p "$right/packages/shared" "$right/packages/one/tests" "$right/packages/one/native" "$right/packages/grapevine/native"
printf 'what the packages have copies of\n' > "$right/packages/shared/note.txt"
manifest "$right/packages/one" one 0.1.0
printf '💭 one\n' > "$right/packages/one/one.🍇"
printf '// one\n' > "$right/packages/one/native/net.cpp"
printf '# one\n' > "$right/packages/one/README.md"
printf '💭 a test, which no release holds\n' > "$right/packages/one/tests/main.🍇"
manifest "$right/packages/grapevine" grapevine 0.1.0 one 0.1
printf '💭 grapevine\n' > "$right/packages/grapevine/grapevine.🍇"
printf '// grapevine\n' > "$right/packages/grapevine/native/net.cpp"
printf 'build/\ntarget/\n' > "$right/.gitignore"
git -C "$right" init --quiet --initial-branch=main
commit "$right" "a repository that is right"

# plant <name>: a fresh copy of the repository that is right, for one case to spoil.
plant() { tree="$work/$1"; cp -R "$right" "$tree"; }

# change <file> <sed expression>: without sed's own way of writing a file in place, which
# is spelt differently on a Mac and on Linux.
change() { sed "$2" "$1" > "$1.changed" && mv "$1.changed" "$1"; }

# rehearse: runs the rehearsal on the tree, and keeps what it said and how it ended.
rehearse() { out=$(bash "$check" "$tree" 2>&1); status=$?; }

# passes <case> <how many it says were packed> [words that it has to say]...
passes() {
  cases=$((cases + 1))
  local name=$1 count=$2 words
  shift 2
  rehearse
  if [ "$status" -ne 0 ]; then
    fail "$name: refused with status $status: $out"
    return
  fi
  grep -qxF "release: $count packed and installed, no problem found" <<< "$out" \
    || fail "$name: passed without saying \"$count packed and installed\": $out"
  for words in "$@"; do
    grep -qF -- "$words" <<< "$out" || fail "$name: did not say \"$words\": $out"
  done
}

# reports <case> <count, as the last line says it> <words>...
reports() {
  cases=$((cases + 1))
  local name=$1 count=$2 words
  shift 2
  rehearse
  [ "$status" -eq 1 ] || fail "$name: status $status, not 1: $out"
  grep -qxF -- "release: $count" <<< "$out" || fail "$name: not \"release: $count\": $out"
  for words in "$@"; do
    grep -qF -- "$words" <<< "$out" || fail "$name: not reported with \"$words\": $out"
  done
}

# stops <case> <words>: the rehearsal could not be made at all.
stops() {
  cases=$((cases + 1))
  [ "$status" -eq 2 ] || fail "$1: status $status, not 2: $out"
  grep -qF -- "$2" <<< "$out" || fail "$1: did not say \"$2\": $out"
}

# ── What is right

plant right-as-it-is
passes "a repository that is right" 2 \
  "@thatplatypus/one 0.1.0: not released yet" "@thatplatypus/grapevine 0.1.0: not released yet"
[ -f "$tree/build/release/files/one-0.1.0.pmj.tar.gz" ] && [ -f "$tree/build/release/files/grapevine-0.1.0.pmj.tar.gz" ] \
  || fail "a repository that is right: the two files are not in build/release/files"
[ "$(grep -c '' "$tree/build/release/summary.txt" 2> /dev/null)" = 2 ] \
  || fail "a repository that is right: build/release/summary.txt does not have a line for each package"
grep -qF '"@thatplatypus/one@0.1.0"' "$tree/build/release/locks/grapevine.lock" 2> /dev/null \
  || fail "a repository that is right: the application that added grapevine did not lock the package it needs"
# The digest that is said is the digest of the file, by the system's own tool.
if command -v sha256sum > /dev/null 2>&1; then
  digest=$(sha256sum "$tree/build/release/files/one-0.1.0.pmj.tar.gz" | cut -d' ' -f1)
else
  digest=$(shasum -a 256 "$tree/build/release/files/one-0.1.0.pmj.tar.gz" | cut -d' ' -f1)
fi
grep -qxF "@thatplatypus/one 0.1.0 $digest one-0.1.0.pmj.tar.gz" "$tree/build/release/summary.txt" 2> /dev/null \
  || fail "a repository that is right: the summary does not give one's file with its own digest"

# What an earlier rehearsal left is no part of the next one.
passes "a second rehearsal in the same checkout" 2

plant pmj-named-from-where-it-is-run
mkdir "$work/bin" && ln -s "$pmj" "$work/bin/pmj"
cases=$((cases + 1))
out=$(cd "$work/bin" && PMJ=./pmj bash "$check" "$tree" 2>&1); status=$?
[ "$status" -eq 0 ] || fail "a pmj named by a path from where the rehearsal is run: status $status: $out"

plant a-pre-release
manifest "$tree/packages/one" one 0.2.0-rc.1
manifest "$tree/packages/grapevine" grapevine 0.2.0-rc.1 one 0.2.0-rc.1
commit "$tree" "versions that are pre-releases"
passes "versions that are pre-releases" 2 "@thatplatypus/one 0.2.0-rc.1: not released yet"

plant a-name-with-a-space
printf '💭 more\n' > "$tree/packages/one/a b.🍇"
commit "$tree" "a source with a space in its name"
passes "a source with a space in its name" 2

plant released
git -C "$tree" tag one-v0.1.0
passes "a version that is tagged, and whose folder is as the tag has it" 2 \
  "@thatplatypus/one 0.1.0: released, and unchanged since" "@thatplatypus/grapevine 0.1.0: not released yet"

# A test is no part of a release, so one that changes after a release changes nothing of it.
plant released-then-a-test
git -C "$tree" tag one-v0.1.0
printf '💭 another test\n' > "$tree/packages/one/tests/more.🍇"
commit "$tree" "a test more"
passes "a version that is tagged, and a test that was added since" 2 \
  "@thatplatypus/one 0.1.0: released, and unchanged since"

plant released-then-a-new-version
git -C "$tree" tag one-v0.1.0
printf '💭 one, and more\n' > "$tree/packages/one/one.🍇"
manifest "$tree/packages/one" one 0.1.1
manifest "$tree/packages/grapevine" grapevine 0.1.1 one 0.1.1
commit "$tree" "a change, and the versions it asks for"
passes "a version that is tagged, changed and given a new version" 2 \
  "@thatplatypus/one 0.1.1: not released yet"

# ── What a release may not hold

plant a-file-git-does-not-track
printf '💭 tried out, and never added\n' > "$tree/packages/one/stray.🍇"
reports "a source that git does not track" "1 problem" \
  "one: its release would hold stray.🍇, which git does not track in packages/one"

plant a-file-below-the-top-that-git-does-not-track
printf '// tried out, and never added\n' > "$tree/packages/one/native/stray.cpp"
reports "a native file that git does not track" "1 problem" \
  "one: its release would hold native/stray.cpp, which git does not track in packages/one"

# ── What pmj has to take

plant a-neighbour-at-another-version
manifest "$tree/packages/one" one 0.1.1
commit "$tree" "one moves on, and grapevine does not follow"
reports "a neighbour asked for at a version it does not have here" "1 problem" \
  "grapevine: pmj did not add it to an application:" "package.not-found"

plant another-repository
change "$tree/packages/one/packmoji.json" 's|github.com/thatplatypus/grapevine|github.com/thatplatypus/other|'
commit "$tree" "one says it lives somewhere else"
reports "a manifest that names another repository" "2 problems" \
  "one: pmj did not add it to an application:" "grapevine: pmj did not add it to an application:" "release.invalid"

plant pack-refuses
rm "$tree/packages/one/one.🍇"
commit "$tree" "one loses its entry"
reports "a package that pmj will not pack" "1 problem" "one: pmj pack refused it:" "entry.not-found"

# ── What is not taken on pmj's word

# pretender <name> <lines of sh>: a pmj that does what the real one does, and then something
# of its own. \$real is the real one, and \$1 the command it was given.
pretender() {
  mkdir -p "$work/bin"
  { printf '#!/bin/sh\nreal="%s"\n' "$pmj"; printf '%s\n' "$2"; } > "$work/bin/$1"
  chmod +x "$work/bin/$1"
}

# What is there from an earlier run may not stand for what this run packed.
plant packed-in-name-only
pretender says-it-packed 'if [ "$1" = pack ]; then exit 0; fi
exec "$real" "$@"'
mkdir -p "$tree/packages/one/target" && printf 'from an earlier run\n' > "$tree/packages/one/target/one-0.1.0.pmj.tar.gz"
cases=$((cases + 1))
out=$(PMJ="$work/bin/says-it-packed" bash "$check" "$tree" 2>&1); status=$?
[ "$status" -eq 1 ] || fail "a pmj that says it packed and wrote nothing: status $status, not 1: $out"
grep -qF "one: pmj pack did not write target/one-0.1.0.pmj.tar.gz" <<< "$out" \
  || fail "a pmj that says it packed and wrote nothing: not reported for one: $out"
grep -qxF "release: 2 problems" <<< "$out" || fail "a pmj that says it packed and wrote nothing: not \"release: 2 problems\": $out"

plant locked-as-something-else
pretender locks-something-else '"$real" "$@" || exit $?
if [ "$1" = add ]; then
  sed "s/\"sha256\": \"[0-9a-f]\{8\}/\"sha256\": \"00000000/" packmoji.lock > packmoji.lock.changed && mv packmoji.lock.changed packmoji.lock
fi'
cases=$((cases + 1))
out=$(PMJ="$work/bin/locks-something-else" bash "$check" "$tree" 2>&1); status=$?
[ "$status" -eq 1 ] || fail "a lockfile that holds other bytes than were packed: status $status, not 1: $out"
grep -qF "one: the application that added it locked @thatplatypus/one 0.1.0 with sha256 00000000" <<< "$out" \
  || fail "a lockfile that holds other bytes than were packed: not reported for one: $out"

plant unpacked-somewhere-else
pretender keeps-no-cache '"$real" "$@" || exit $?
if [ "$1" = add ]; then rm -rf "$PACKMOJI_HOME/cache"; fi'
cases=$((cases + 1))
out=$(PMJ="$work/bin/keeps-no-cache" bash "$check" "$tree" 2>&1); status=$?
[ "$status" -eq 1 ] || fail "a pmj whose cache is not where it is looked for: status $status, not 1: $out"
grep -qF "one: pmj added it, and its files are not in pmj's cache at" <<< "$out" \
  || fail "a pmj whose cache is not where it is looked for: not reported for one: $out"

# Each package is added as whoever uses it will add it: the one that is named as the
# repository is with nothing said of where it lives, and any other as its README says.
plant added-as-a-person-would
pretender says-what-it-was-asked 'echo "$*" >> "$ASKED"
exec "$real" "$@"'
cases=$((cases + 1))
out=$(ASKED="$work/asked" PMJ="$work/bin/says-what-it-was-asked" bash "$check" "$tree" 2>&1); status=$?
[ "$status" -eq 0 ] || fail "how each package is added: status $status: $out"
grep -qxF "add @thatplatypus/grapevine@0.1.0" "$work/asked" 2> /dev/null \
  || fail "how each package is added: grapevine was not added by its name and version alone: $(cat "$work/asked" 2>&1)"
grep -qxF "add @thatplatypus/one@0.1.0 --repository github.com/thatplatypus/grapevine" "$work/asked" 2> /dev/null \
  || fail "how each package is added: one was not added with the repository it shares: $(cat "$work/asked" 2>&1)"

# ── A published version never changes

plant released-then-changed
git -C "$tree" tag one-v0.1.0
printf '💭 one, and more\n' > "$tree/packages/one/one.🍇"
reports "a version that is tagged, and whose folder has changed" "1 problem" \
  "one: 0.1.0 is released (the tag one-v0.1.0), and what would be packed now is not what the tag packs" \
  "give the package a new version in packages/one/packmoji.json"

plant a-tag-on-the-wrong-commit
git -C "$tree" tag one-v0.1.1
manifest "$tree/packages/one" one 0.1.1
manifest "$tree/packages/grapevine" grapevine 0.1.0 one 0.1.1
commit "$tree" "the version the tag names, a commit too late"
reports "a tag on a commit whose manifest names another version" "1 problem" \
  "one: the tag one-v0.1.1 is there, and packages/one as that tag has it does not pack to one-0.1.1.pmj.tar.gz"

# ── A manifest that cannot be gone by

plant no-manifest
rm "$tree/packages/one/packmoji.json"
reports "a package with no manifest" "1 problem" "one: no packmoji.json"

plant not-json
printf '{ "package": {\n' > "$tree/packages/one/packmoji.json"
reports "a manifest that is not JSON" "1 problem" "one: packmoji.json cannot be read: it is not a JSON object"

plant another-scope
change "$tree/packages/one/packmoji.json" 's|@thatplatypus/one|@someoneelse/one|'
reports "a manifest under another scope" "1 problem" "one: packmoji.json names @someoneelse/one"

plant no-packages
rm -rf "$tree/packages/one" "$tree/packages/grapevine"
reports "a repository with no package" "1 problem" "no package under packages/"

# ── What keeps the rehearsal from being made

plant no-pmj-there
out=$(PMJ="$work/no-such-pmj" bash "$check" "$tree" 2>&1); status=$?
stops "a pmj that is not there" "is not a program that can be run"

plant no-pmj-at-all
out=$(env -u PMJ PATH=/usr/bin:/bin bash "$check" "$tree" 2>&1); status=$?
stops "no pmj named, and none on the PATH" "there is no pmj to pack with"

plant not-a-checkout
rm -rf "$tree/.git"
rehearse
stops "a folder that is not a checkout" "is not a checkout"

if [ "$failures" -gt 0 ]; then
  echo "release-test: $failures failed"
  exit 1
fi
echo "release-test: $cases cases"
