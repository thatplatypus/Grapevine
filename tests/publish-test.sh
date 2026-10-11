#!/usr/bin/env bash
# Tests the step that makes a release. That step is written in .github/workflows/release.yml
# and nowhere else, so that nothing at a desk can make a release by being run. This takes it
# out of the workflow as it stands and runs it with a stand-in for gh that makes nothing: it
# keeps which tags have a release, and what it was asked to create.
#
# A release never changes once it is published, so each thing the step refuses is planted
# here, in a made-up repository with what a rehearsal keeps beside it, and has to be
# refused with its own words. The made-up archives and lockfiles are written by hand, so
# the step is also run, as a dry run, on what tests/release.sh kept of the real packages:
# that is where it meets the archives pmj packs and the lockfiles pmj writes.
#   tests/publish-test.sh              the made-up repository
#   tests/publish-test.sh rehearsed    the step on build/release, after tests/release.sh
# Needs git, perl and tar.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
root="$PWD"
workflow="$root/.github/workflows/release.yml"
case "${1:-}" in
  ""|rehearsed) ;;
  *) echo "usage: tests/publish-test.sh [rehearsed]" >&2; exit 2 ;;
esac

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

# The stand-in for gh. RELEASED and DRAFTS are files of tags, a line each. TAGGED is the
# commit that GitHub says a tag names, or nothing when GitHub will not say. CREATED gets a
# line for each release it was asked to make, and the notes that went with it, unless
# CREATE_FAILS says that GitHub would not make one. Where the real gh fails it writes
# GitHub's answer to standard output all the same, and so does this.
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
    if [ -n "$CREATE_FAILS" ]; then
      echo "HTTP 502: Bad Gateway" >&2
      exit 1
    fi
    echo "$*" >> "$CREATED"
    cat notes.md >> "$CREATED.notes"
    echo "$3" >> "$RELEASED" ;;
  "api repos/$GITHUB_REPOSITORY/commits/tags/"*)
    if [ -n "$TAGGED" ]; then
      echo "$TAGGED"
    else
      echo '{"message":"No commit found for SHA: tags/it","status":"422"}'
      echo "gh: No commit found for SHA (HTTP 422)" >&2
      exit 1
    fi ;;
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

# step <tag>: the step as a pushed tag runs it. step: the step as a dry run. GitHub says
# the tag names the commit of the run, unless a case has set $tagged to something else.
step() {
  local dry=true commit
  [ -z "${1:-}" ] || dry=false
  commit=$(git -C "$repo" rev-parse HEAD)
  out=$(cd "$repo" && env PATH="$work/bin:$PATH" GITHUB_REPOSITORY=thatplatypus/Grapevine GITHUB_WORKSPACE="$repo" \
    GITHUB_SHA="$commit" GITHUB_REF_NAME="${1:-main}" DRY_RUN="$dry" TAGGED="${tagged-$commit}" \
    CREATE_FAILS="${create_fails-}" \
    RELEASED="$repo/released" DRAFTS="$repo/drafts" CREATED="$repo/created" bash "$work/publish.sh" 2>&1)
  status=$?
}

# says <case> <words>: what the step printed holds the words.
says() { grep -qF -- "$2" <<< "$out" || fail "$1: did not say \"$2\": $out"; }

# created <case> <the line>: what gh was asked to create is that, and nothing else.
created() {
  [ "$(cat "$repo/created")" = "$2" ] || fail "$1: gh was asked to create \"$(cat "$repo/created")\", not \"$2\""
}

# ── The step on what the rehearsal kept of the real packages

if [ "${1:-}" = rehearsed ]; then
  kept="$root/build/release"
  if [ ! -f "$kept/summary.txt" ]; then
    echo "publish-test: there is nothing in build/release to run the step on: tests/release.sh goes first"
    exit 2
  fi
  # The job's checkout: the packages as they are here, which is what was packed, in a commit
  # that is on main, with the rehearsal's artifact beside them.
  repo="$work/checkout"
  mkdir "$repo" && cp -R "$root/packages" "$repo/packages"
  printf 'rehearsed/\nunpacked/\nnotes.md\nreleased\ndrafts\ncreated*\n' > "$repo/.gitignore"
  git -C "$repo" init --quiet --initial-branch=main
  git -C "$repo" add -A && git -C "$repo" commit --quiet -m "the packages as they were packed"
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  mkdir "$repo/rehearsed" && cp -R "$kept/files" "$kept/locks" "$kept/summary.txt" "$repo/rehearsed/"
  : > "$repo/drafts"; : > "$repo/created"; : > "$repo/created.notes"

  # What each package needs, read out of its lockfile as JSON, and not as the step reads it.
  mkdir "$work/needs"
  : > "$work/tags"
  while read -r name version _; do
    bare=${name#*/}
    echo "$bare-v$version" >> "$work/tags"
    perl "$root/tests/release.pl" lock "$kept/locks/$bare.lock" | while read -r locked at _; do
      [ "$locked" = "$name" ] || echo "${locked#*/}-v$at"
    done > "$work/needs/$bare"
  done < "$kept/summary.txt"

  # expected: what a dry run has to print, to the letter, when the tags in $repo/released
  # are released: for each package its tag, its file with its digest, and what would happen.
  expected() {
    local name version digest file bare tag missing
    while read -r name version digest file; do
      bare=${name#*/}
      tag="$bare-v$version"
      echo "$tag"
      echo "  $file, sha256 $digest"
      missing=$(grep -vxFf "$repo/released" "$work/needs/$bare" | paste -sd' ' -)
      if [ -n "$missing" ]; then
        echo "  would refuse: it needs $missing, which is not released yet: release that first"
      elif grep -qxF "$tag" "$repo/released"; then
        echo "  nothing to release: it is released"
      else
        echo "  would release"
      fi
    done < "$kept/summary.txt"
  }

  # dry <case>: a dry run prints what is expected, ends well, and creates nothing.
  dry() {
    cases=$((cases + 1))
    step
    [ "$status" -eq 0 ] || fail "$1: status $status: $out"
    [ "$out" = "$(expected)" ] || fail "$1: the dry run said:
$out
and not:
$(expected)"
    created "$1" ""
  }

  : > "$repo/released"
  dry "a dry run on what the rehearsal kept, with nothing released"
  # Each package in turn as the one that is still to be released, which takes the step
  # through every file of its archive and every line of its lockfile.
  while IFS= read -r tag <&3; do
    grep -vxF "$tag" "$work/tags" > "$repo/released"
    dry "a dry run on what the rehearsal kept, with all released but $tag"
  done 3< "$work/tags"

  if [ "$failures" -gt 0 ]; then
    echo "publish-test: $failures failed"
    exit 1
  fi
  echo "publish-test: the step on what the rehearsal kept, $cases cases"
  exit 0
fi

# ── The made-up repository

# manifest <folder> <name> <version>
manifest() {
  printf '{\n  "package": {\n    "name": "@thatplatypus/%s",\n    "version": "%s"\n  }\n}\n' "$2" "$3" > "$1/packmoji.json"
}

# locked <name> <version>: an entry of a lockfile, a key to a line, as pmj writes one.
locked() {
  printf '    {\n      "name": "@thatplatypus/%s",\n      "version": "%s",\n      "releaseTag": "%s-v%s",\n      "sha256": "%s"\n    }' "$1" "$2" "$1" "$2" "$3"
}

# packed <repository> <name> <version> [more files]: an archive of the package as it is in
# the repository. A plain one: the step unpacks it with tar, and does not ask that pmj
# packed it. One file of it is below the top of the folder, as grapevine's native file is.
packed() {
  local folder="$1/packages/$2" file="$1/rehearsed/files/$2-$3.pmj.tar.gz"
  shift 3
  (cd "$folder" && COPYFILE_DISABLE=1 tar -czf "$file" packmoji.json README.md "$(basename "$folder").🍇" native/net.cpp "$@")
}

# rehearsed <repository> <version>: what a rehearsal of the repository keeps.
rehearsed() {
  local kept="$1/rehearsed" name digest
  rm -rf "$kept" && mkdir -p "$kept/files" "$kept/locks"
  : > "$kept/summary.txt"
  for name in one grapevine; do
    packed "$1" "$name" "$2"
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
  unset tagged create_fails
  local version=${2:-0.1.0} name
  for name in one grapevine; do
    mkdir -p "$repo/packages/$name/tests" "$repo/packages/$name/native"
    manifest "$repo/packages/$name" "$name" "$version"
    printf '# %s\n' "$name" > "$repo/packages/$name/README.md"
    printf '💭 %s\n' "$name" > "$repo/packages/$name/$name.🍇"
    printf '// %s\n' "$name" > "$repo/packages/$name/native/net.cpp"
    printf '💭 a test, which no release holds\n' > "$repo/packages/$name/tests/main.🍇"
  done
  printf 'rehearsed/\nunpacked/\nnotes.md\nreleased\ndrafts\ncreated*\n' > "$repo/.gitignore"
  git -C "$repo" init --quiet --initial-branch=main
  git -C "$repo" add -A && git -C "$repo" commit --quiet -m "a repository of two packages"
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  : > "$repo/released"; : > "$repo/drafts"; : > "$repo/created"; : > "$repo/created.notes"
  rehearsed "$repo" "$version"
}

# digest <name>: the digest of the package's file, as the rehearsal's summary gives it.
digest() { awk -v name="@thatplatypus/$1" '$1 == name { print $3 }' "$repo/rehearsed/summary.txt"; }

# away <tag>: how a tag that stands for no release is taken off GitHub.
away() { echo "git push origin :refs/tags/$1"; }

# refuses <case> <tag> <why> <what to do>: the tag is refused, with why and with what is to
# be done about it, and nothing is created.
refuses() {
  cases=$((cases + 1))
  step "$2"
  [ "$status" -eq 1 ] || fail "$1: status $status, not 1: $out"
  says "$1" "::error::$2 was not released: $3. $4"
  created "$1" ""
}

# ── What the step rests on outside itself

# Two lines of the workflow that are no part of the step, and without which it would
# release what was not checked, or release in a dry run.
cases=$((cases + 1))
grep -qxF "        DRY_RUN: \${{ github.event_name != 'push' }}" "$workflow" \
  || fail "the workflow: anything but a pushed tag is no longer made a dry run by the line this test knows"
grep -qxF "    needs: checks" "$workflow" \
  || fail "the workflow: the job that publishes no longer waits for the checks by the line this test knows"

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

# A dry run looks at every package, whatever it found of the one before.
repository dry-run-past-a-file-that-is-no-archive
printf 'not an archive\n' > "$repo/rehearsed/files/grapevine-0.1.0.pmj.tar.gz"
cases=$((cases + 1))
step
[ "$status" -eq 0 ] || fail "a dry run with a file that is no archive: status $status: $out"
says "a dry run with a file that is no archive" "  would refuse: its file is not an archive of the package: it does not unpack to a packmoji.json"
says "a dry run with a file that is no archive" "  would release"
created "a dry run with a file that is no archive" ""

# In a dry run no tag has been pushed, so nothing is asked of where a tag is.
repository dry-run-asks-nothing-of-the-tag
tagged=
cases=$((cases + 1))
step
[ "$status" -eq 0 ] || fail "a dry run when GitHub knows no such tag: status $status: $out"
says "a dry run when GitHub knows no such tag" "  would release"

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

repository a-pre-release 0.2.0-beta.1
cases=$((cases + 1))
step one-v0.2.0-beta.1
[ "$status" -eq 0 ] || fail "a version that is a pre-release: status $status: $out"
created "a version that is a pre-release" \
  "release create one-v0.2.0-beta.1 rehearsed/files/one-0.2.0-beta.1.pmj.tar.gz --verify-tag --title one 0.2.0-beta.1 --notes-file notes.md --prerelease --latest=false"
cases=$((cases + 1))
: > "$repo/created"
step grapevine-v0.2.0-beta.1
created "a pre-release of the package the repository is named for" \
  "release create grapevine-v0.2.0-beta.1 rehearsed/files/grapevine-0.2.0-beta.1.pmj.tar.gz --verify-tag --title grapevine 0.2.0-beta.1 --notes-file notes.md --prerelease --latest=false"

# A release that GitHub would not make is not one that was made.
repository github-would-not
create_fails=yes
cases=$((cases + 1))
step one-v0.1.0
[ "$status" -ne 0 ] || fail "a release that GitHub would not make: the step ended well: $out"
if grep -qF "  released" <<< "$out"; then fail "a release that GitHub would not make: the step said it was released: $out"; fi

# ── What is refused, and what is then to be done

repository no-such-package
refuses "a tag that names no package" nothing-v1.0.0 "there is no package in packages/nothing" \
  "Delete the tag, which names nothing here: $(away nothing-v1.0.0)"

repository another-version
refuses "a tag for a version the manifest does not have" one-v0.2.0 \
  "packages/one/packmoji.json names another version at this commit: the rehearsal packed one-0.1.0.pmj.tar.gz" \
  "Delete the tag, and put it on a commit whose manifest names 0.2.0: $(away one-v0.2.0)"

# ── What was packed has to be the package, and the commit's

untrusted="Nothing of this run is to be trusted before its rehearsal has been looked at. Delete the tag:"

repository no-archive
printf 'not an archive\n' > "$repo/rehearsed/files/one-0.1.0.pmj.tar.gz"
refuses "a file that is no archive" one-v0.1.0 \
  "its file is not an archive of the package: it does not unpack to a packmoji.json" "$untrusted $(away one-v0.1.0)"

# An archive that tar reads, and that is not a package: nothing in it differs from the
# commit, and it is all the same not what the tag is to carry.
repository no-manifest-in-the-archive
(cd "$repo/packages/one" && COPYFILE_DISABLE=1 tar -czf "$repo/rehearsed/files/one-0.1.0.pmj.tar.gz" README.md)
refuses "an archive that holds no manifest" one-v0.1.0 \
  "its file is not an archive of the package: it does not unpack to a packmoji.json" "$untrusted $(away one-v0.1.0)"

# What the rehearsal packed is no longer what the commit holds.
repository a-file-that-differs
printf '💭 changed after it was packed\n' > "$repo/packages/one/one.🍇"
refuses "an archive with a file that is not the commit's" one-v0.1.0 \
  "its file holds what packages/one does not hold at this commit: one.🍇" "$untrusted $(away one-v0.1.0)"

repository a-file-below-the-top-that-differs
printf '// changed after it was packed\n' > "$repo/packages/one/native/net.cpp"
refuses "an archive with a file below the top that is not the commit's" one-v0.1.0 \
  "its file holds what packages/one does not hold at this commit: native/net.cpp" "$untrusted $(away one-v0.1.0)"

repository a-file-too-many
printf '💭 packed, and in no commit\n' > "$repo/packages/one/stray.🍇"
packed "$repo" one 0.1.0 stray.🍇
rm "$repo/packages/one/stray.🍇"
refuses "an archive with a file that the commit does not have" one-v0.1.0 \
  "its file holds what packages/one does not hold at this commit: stray.🍇" "$untrusted $(away one-v0.1.0)"

repository two-files-that-differ
printf '💭 changed after it was packed\n' > "$repo/packages/one/one.🍇"
printf '// changed after it was packed\n' > "$repo/packages/one/native/net.cpp"
refuses "an archive with two files that are not the commit's" one-v0.1.0 \
  "its file holds what packages/one does not hold at this commit: native/net.cpp one.🍇" "$untrusted $(away one-v0.1.0)"

# ── Only what was merged, and only after what it needs

repository off-main
printf '💭 more\n' >> "$repo/packages/one/one.🍇"
git -C "$repo" commit --quiet -am "a commit that main does not have"
rehearsed "$repo" 0.1.0
refuses "a commit that is not on main" one-v0.1.0 "its commit is not on main" \
  "Delete the tag, and put it on a commit of main: $(away one-v0.1.0)"

later="Then start this run again: the tag can stay where it is"

repository a-neighbour-not-released
refuses "a package whose neighbour is not released" grapevine-v0.1.0 \
  "it needs one-v0.1.0, which is not released yet: release that first" "$later"

repository a-neighbour-in-draft
echo one-v0.1.0 > "$repo/drafts"
refuses "a package whose neighbour's release is a draft" grapevine-v0.1.0 \
  "it needs one-v0.1.0, which is not released yet: release that first" "$later"

repository no-lockfile
rm "$repo/rehearsed/locks/grapevine.lock"
echo one-v0.1.0 > "$repo/released"
refuses "a package the rehearsal kept no lockfile for" grapevine-v0.1.0 \
  "the rehearsal kept no lockfile for it, so what it needs is not known" \
  "Start this run again. If it says so again, delete the tag: $(away grapevine-v0.1.0)"

# A lockfile that says the same in another form, as a later pmj might write one. A step that
# found no tag in it would take the package to need nothing, and release it before its
# neighbour.
repository a-lockfile-in-another-form
printf '{"packages":[{"name":"@thatplatypus/grapevine","version":"0.1.0","releaseTag":"grapevine-v0.1.0"},{"name":"@thatplatypus/one","version":"0.1.0","releaseTag":"one-v0.1.0"}]}\n' > "$repo/rehearsed/locks/grapevine.lock"
refuses "a lockfile in a form the step does not read" grapevine-v0.1.0 \
  "the lockfile the rehearsal kept for it does not name grapevine-v0.1.0 where this step reads it, so what it needs is not known" \
  "The step reads a lockfile as pmj wrote one when the step was written. See what pmj writes now, and delete the tag: $(away grapevine-v0.1.0)"

# ── A published version never changes

repository released-already
echo one-v0.1.0 > "$repo/released"
refuses "a version that is released already" one-v0.1.0 \
  "it is released already, and a published version never changes" \
  "Leave the tag where it is. What is to change is released as a new version"

# gh makes a draft, gives it the file, and only then publishes it. A run that was stopped
# between leaves the draft, which is no release and is in the way of one.
repository a-draft-left-behind
echo one-v0.1.0 > "$repo/drafts"
refuses "a version of which a draft was left behind" one-v0.1.0 \
  "a draft of its release is there, which a run that did not finish left" \
  "Delete the draft with gh release delete one-v0.1.0, and start this run again: the tag can stay where it is"
cases=$((cases + 1))
step
says "a dry run when a draft was left behind" "  would refuse: a draft of its release is there, which a run that did not finish left"

# ── The tag still names what was checked

# Everything was checked of the run's commit. A tag that was moved while the checks ran,
# or the run of an old commit started again after its tag had moved, would give the tag a
# file that its commit does not pack.
repository a-tag-that-moved
printf '💭 more\n' >> "$repo/packages/one/README.md"
git -C "$repo" commit --quiet -am "the commit the tag was moved to"
tagged=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" reset --quiet --hard HEAD~1
refuses "a tag that names another commit by now" one-v0.1.0 \
  "the tag names $tagged on GitHub now, and this run checked $(git -C "$repo" rev-parse HEAD)" \
  "A tag that is pushed again starts a run of its own, so nothing is to be done to this one"

repository a-tag-github-will-not-answer-for
tagged=
refuses "a tag that GitHub does not say the commit of" one-v0.1.0 \
  "GitHub did not say which commit the tag names, and nothing is released without that" \
  "Start this run again: the tag can stay where it is"

if [ "$failures" -gt 0 ]; then
  echo "publish-test: $failures failed"
  exit 1
fi
echo "publish-test: $cases cases"
