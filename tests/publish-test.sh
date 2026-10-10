#!/usr/bin/env bash
# Tests the step that makes a release. That step is written in .github/workflows/release.yml
# and nowhere else, so that nothing at a desk can make a release by being run. This takes it
# out of the workflow as it stands and runs it against a made-up repository, with what a
# rehearsal keeps beside it and a stand-in for gh that makes nothing: it keeps which tags
# have a release, and what it was asked to create.
#
# A release never changes once it is published, so each thing the step refuses is planted
# here and has to be refused with its own words.
#   tests/publish-test.sh
# Needs git, perl and tar.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
workflow="$PWD/.github/workflows/release.yml"

# git as it is with nobody's settings: no signing, no hooks, and an author of its own.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=publish-test GIT_AUTHOR_EMAIL=publish-test@example.invalid
export GIT_COMMITTER_NAME=publish-test GIT_COMMITTER_EMAIL=publish-test@example.invalid

work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT
failures=0
cases=0
fail() { failures=$((failures + 1)); echo "  FAIL $1"; }

# The step's own lines: what follows "run: |" under the step of that name, less its indent.
perl -e '
  my ($found, $indent) = (0, undef);
  while (<>) {
    if (!$found) { $found = 1 if /^\s*- name: Release, or say what would be released\s*$/; next }
    if (!defined $indent) { $indent = length($1) + 2 if /^(\s*)run: \|\s*$/; next }
    last unless /^\s*$/ || /^ {$indent}/;
    s/^ {$indent}//;
    print;
  }' "$workflow" > "$work/publish.sh" 2> /dev/null
if ! grep -q 'gh release create' "$work/publish.sh"; then
  echo "publish-test: $workflow has no step \"Release, or say what would be released\" that makes a release"
  exit 1
fi

# The stand-in for gh. RELEASED and DRAFTS are files of tags, a line each. CREATED gets a
# line for each release it was asked to make, and the notes that went with it.
mkdir "$work/bin"
cat > "$work/bin/gh" <<'GH'
#!/bin/sh
case "$1 $2" in
  "release view")
    if grep -qxF "$3" "$DRAFTS" 2> /dev/null; then
      case "$*" in *isDraft*) echo true ;; esac
    elif grep -qxF "$3" "$RELEASED" 2> /dev/null; then
      case "$*" in *isDraft*) echo false ;; esac
    else
      echo "release not found" >&2
      exit 1
    fi ;;
  "release create")
    echo "$*" >> "$CREATED"
    cat notes.md >> "$CREATED.notes"
    echo "$3" >> "$RELEASED" ;;
  *)
    echo "the stand-in for gh was asked what the step is not known to ask: $*" >&2
    exit 64 ;;
esac
GH
chmod +x "$work/bin/gh"
# The step runs on Linux, where the tool is called this. A Mac calls it something else.
if ! command -v sha256sum > /dev/null 2>&1; then
  printf '#!/bin/sh\nexec shasum -a 256 "$@"\n' > "$work/bin/sha256sum"
  chmod +x "$work/bin/sha256sum"
fi

# manifest <folder> <name> <version>
manifest() {
  printf '{\n  "package": {\n    "name": "@thatplatypus/%s",\n    "version": "%s"\n  }\n}\n' "$2" "$3" > "$1/packmoji.json"
}

# locked <name> <version>: an entry of a lockfile, a key to a line, as pmj writes one.
locked() {
  printf '    {\n      "name": "@thatplatypus/%s",\n      "version": "%s",\n      "releaseTag": "%s-v%s",\n      "sha256": "%s"\n    }' "$1" "$2" "$1" "$2" "$3"
}

# rehearsed <repository> <version>: what a rehearsal of the repository keeps. The archives
# are plain ones: the step unpacks them with tar, and does not ask that pmj packed them.
rehearsed() {
  local kept="$1/rehearsed" name digest
  rm -rf "$kept" && mkdir -p "$kept/files" "$kept/locks"
  : > "$kept/summary.txt"
  for name in one grapevine; do
    (cd "$1/packages/$name" && COPYFILE_DISABLE=1 tar -czf "$kept/files/$name-$2.pmj.tar.gz" packmoji.json README.md "$name.🍇")
    digest=$(PATH="$work/bin:$PATH" sha256sum "$kept/files/$name-$2.pmj.tar.gz" | cut -d' ' -f1)
    echo "@thatplatypus/$name $2 $digest $name-$2.pmj.tar.gz" >> "$kept/summary.txt"
  done
  { printf '{\n  "packages": [\n'; locked one "$2" 00; printf '\n  ]\n}\n'; } > "$kept/locks/one.lock"
  { printf '{\n  "packages": [\n'; locked grapevine "$2" 00; printf ',\n'; locked one "$2" 00; printf '\n  ]\n}\n'; } > "$kept/locks/grapevine.lock"
}

# repository <name> [version]: a repository of two packages, of which grapevine needs one,
# with its one commit on main, and what a rehearsal of it keeps.
repository() {
  repo="$work/$1"
  local version=${2:-0.1.0} name
  for name in one grapevine; do
    mkdir -p "$repo/packages/$name/tests"
    manifest "$repo/packages/$name" "$name" "$version"
    printf '# %s\n' "$name" > "$repo/packages/$name/README.md"
    printf '💭 %s\n' "$name" > "$repo/packages/$name/$name.🍇"
    printf '💭 a test, which no release holds\n' > "$repo/packages/$name/tests/main.🍇"
  done
  printf 'rehearsed/\nunpacked/\nnotes.md\nreleased\ndrafts\ncreated*\n' > "$repo/.gitignore"
  git -C "$repo" init --quiet --initial-branch=main
  git -C "$repo" add -A && git -C "$repo" commit --quiet -m "a repository of two packages"
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  : > "$repo/released"; : > "$repo/drafts"; : > "$repo/created"; : > "$repo/created.notes"
  rehearsed "$repo" "$version"
}

# step <tag>: the step as a pushed tag runs it. step: the step as a dry run.
step() {
  local dry=true
  [ -z "${1:-}" ] || dry=false
  out=$(cd "$repo" && env PATH="$work/bin:$PATH" GITHUB_REPOSITORY=thatplatypus/Grapevine GITHUB_WORKSPACE="$repo" \
    GITHUB_SHA="$(git -C "$repo" rev-parse HEAD)" GITHUB_REF_NAME="${1:-main}" DRY_RUN="$dry" \
    RELEASED="$repo/released" DRAFTS="$repo/drafts" CREATED="$repo/created" bash "$work/publish.sh" 2>&1)
  status=$?
}

# digest <name>: the digest of the package's file, as the rehearsal's summary gives it.
digest() { awk -v name="@thatplatypus/$1" '$1 == name { print $3 }' "$repo/rehearsed/summary.txt"; }

# says <case> <words>: what the step printed holds the words.
says() { grep -qF -- "$2" <<< "$out" || fail "$1: did not say \"$2\": $out"; }

# created <case> <the line>: what gh was asked to create is that, and nothing else.
created() {
  [ "$(cat "$repo/created")" = "$2" ] || fail "$1: gh was asked to create \"$(cat "$repo/created")\", not \"$2\""
}

# refuses <case> <tag> <words>: the tag is refused with the words, and nothing is created.
refuses() {
  cases=$((cases + 1))
  step "$2"
  [ "$status" -eq 1 ] || fail "$1: status $status, not 1: $out"
  says "$1" "::error::$2 was not released: $3"
  created "$1" ""
}

# ── A dry run

repository dry-run
cases=$((cases + 1))
step
[ "$status" -eq 0 ] || fail "a dry run: status $status: $out"
says "a dry run" "  one-0.1.0.pmj.tar.gz, sha256 $(digest one)"
says "a dry run" "  grapevine-0.1.0.pmj.tar.gz, sha256 $(digest grapevine)"
says "a dry run" "  would release"
says "a dry run" "  would refuse: it needs one-v0.1.0, which is not released yet: release that first"
created "a dry run" ""

repository dry-run-of-what-is-released
echo one-v0.1.0 > "$repo/released"
cases=$((cases + 1))
step
[ "$status" -eq 0 ] || fail "a dry run when a version is released: status $status: $out"
says "a dry run when a version is released" "  nothing to release: it is released"
says "a dry run when a version is released" "  would release"
created "a dry run when a version is released" ""

repository dry-run-off-main
printf '💭 more\n' >> "$repo/packages/one/one.🍇"
git -C "$repo" commit --quiet -am "a commit that main does not have"
rehearsed "$repo" 0.1.0
cases=$((cases + 1))
step
[ "$status" -eq 0 ] || fail "a dry run of a commit that is not on main: status $status: $out"
says "a dry run of a commit that is not on main" "  would refuse: its commit is not on main"

# ── A pushed tag

repository a-package-that-needs-nothing
cases=$((cases + 1))
step one-v0.1.0
[ "$status" -eq 0 ] || fail "a package that needs nothing: status $status: $out"
created "a package that needs nothing" \
  "release create one-v0.1.0 rehearsed/files/one-0.1.0.pmj.tar.gz --verify-tag --title one 0.1.0 --notes-file notes.md --latest=false"
grep -qxF "pmj add @thatplatypus/one@0.1.0 --repository github.com/thatplatypus/grapevine" "$repo/created.notes" \
  || fail "a package that needs nothing: its notes do not say how to add it: $(cat "$repo/created.notes")"
grep -qF "\`one-0.1.0.pmj.tar.gz\` has the SHA-256 \`$(digest one)\`." "$repo/created.notes" \
  || fail "a package that needs nothing: its notes do not give the digest of its file"

# The package the repository is named for, once what it needs is released.
cases=$((cases + 1))
: > "$repo/created"; : > "$repo/created.notes"
step grapevine-v0.1.0
[ "$status" -eq 0 ] || fail "the package the repository is named for: status $status: $out"
created "the package the repository is named for" \
  "release create grapevine-v0.1.0 rehearsed/files/grapevine-0.1.0.pmj.tar.gz --verify-tag --title grapevine 0.1.0 --notes-file notes.md"
grep -qxF "pmj add @thatplatypus/grapevine@0.1.0" "$repo/created.notes" \
  || fail "the package the repository is named for: its notes do not say how to add it: $(cat "$repo/created.notes")"

repository a-pre-release 0.2.0-rc.1
cases=$((cases + 1))
step one-v0.2.0-rc.1
[ "$status" -eq 0 ] || fail "a version that is a pre-release: status $status: $out"
created "a version that is a pre-release" \
  "release create one-v0.2.0-rc.1 rehearsed/files/one-0.2.0-rc.1.pmj.tar.gz --verify-tag --title one 0.2.0-rc.1 --notes-file notes.md --prerelease --latest=false"
cases=$((cases + 1))
: > "$repo/created"
step grapevine-v0.2.0-rc.1
created "a pre-release of the package the repository is named for" \
  "release create grapevine-v0.2.0-rc.1 rehearsed/files/grapevine-0.2.0-rc.1.pmj.tar.gz --verify-tag --title grapevine 0.2.0-rc.1 --notes-file notes.md --prerelease --latest=false"

# ── What is refused

repository no-such-package
refuses "a tag that names no package" nothing-v1.0.0 "there is no package in packages/nothing"

repository another-version
refuses "a tag for a version the manifest does not have" one-v0.2.0 \
  "packages/one/packmoji.json names another version at this commit: the rehearsal packed one-0.1.0.pmj.tar.gz"

# What the rehearsal packed is no longer what the commit holds.
repository a-file-that-differs
printf '💭 changed after it was packed\n' > "$repo/packages/one/one.🍇"
refuses "an archive with a file that is not the commit's" one-v0.1.0 \
  "its file holds what packages/one does not hold at this commit: one.🍇"

repository a-file-too-many
printf '💭 packed, and in no commit\n' > "$repo/packages/one/stray.🍇"
(cd "$repo/packages/one" && COPYFILE_DISABLE=1 tar -czf "$repo/rehearsed/files/one-0.1.0.pmj.tar.gz" packmoji.json README.md one.🍇 stray.🍇)
rm "$repo/packages/one/stray.🍇"
refuses "an archive with a file that the commit does not have" one-v0.1.0 \
  "its file holds what packages/one does not hold at this commit: stray.🍇"

repository off-main
printf '💭 more\n' >> "$repo/packages/one/one.🍇"
git -C "$repo" commit --quiet -am "a commit that main does not have"
rehearsed "$repo" 0.1.0
refuses "a commit that is not on main" one-v0.1.0 "its commit is not on main"

repository a-neighbour-not-released
refuses "a package whose neighbour is not released" grapevine-v0.1.0 \
  "it needs one-v0.1.0, which is not released yet: release that first"

repository a-neighbour-in-draft
echo one-v0.1.0 > "$repo/drafts"
refuses "a package whose neighbour's release is a draft" grapevine-v0.1.0 \
  "it needs one-v0.1.0, which is not released yet: release that first"

repository no-lockfile
rm "$repo/rehearsed/locks/grapevine.lock"
echo one-v0.1.0 > "$repo/released"
refuses "a package the rehearsal kept no lockfile for" grapevine-v0.1.0 \
  "the rehearsal kept no lockfile for it, so what it needs is not known"

repository released-already
echo one-v0.1.0 > "$repo/released"
refuses "a version that is released already" one-v0.1.0 \
  "it is released already, and a published version never changes"

if [ "$failures" -gt 0 ]; then
  echo "publish-test: $failures failed"
  exit 1
fi
echo "publish-test: $cases cases"
