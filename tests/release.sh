#!/usr/bin/env bash
# Rehearses a release of each package as far as that goes without a compiler, and releases
# nothing. Each package is packed by pmj, which is the only thing that ever makes the file
# of a release. The files are then served from this machine, laid out as GitHub's download
# addresses are, and each package is added to an application of its own by pmj, as whoever
# uses the package will add it. So pmj has to take each release for what it says it is,
# find what the package depends on, and lock the very bytes that were packed.
#
# Three things are held on the way. Nothing may be in a release that git does not track,
# for pmj packs what is on the disk. A version that is already tagged must still pack to
# what its tag packs, for a published version never changes. And what an application
# locked must be what was packed here.
#
# Whether a release builds is not asked here: ./test-release.sh goes on to build from what
# pmj unpacked. Every folder under packages/ is a package but shared, as in
# tests/packages.sh. tests/release-test.sh tests this script.
#   tests/release.sh [root]     (default: the repository this script is in)
# Needs a pmj (the one PMJ names, or one on the PATH), git, perl and python3. Everything it
# makes is under build/release, but for the target/ that pmj pack leaves in a package.
set -uo pipefail
invoked="$PWD"
here="$(cd "$(dirname "$0")" && pwd)"
cd "${1:-$here/..}" || exit 2
root="$PWD"

# Whose packages these are, and the repository whose releases they would be. Packmoji
# writes a repository in lowercase, whatever GitHub shows.
OWNER=thatplatypus
REPOSITORY=github.com/thatplatypus/grapevine
OWN=${REPOSITORY##*/}

# What keeps the rehearsal from being made at all ends it with status 2. Status 1 is a
# rehearsal that found a problem.
stop() { echo "release: $1" >&2; exit 2; }

# PMJ is a path, from where this was run if it is not from the root, or a name on the PATH.
pmj=${PMJ:-pmj}
case "$pmj" in
  /*) ;;
  */*) pmj="$invoked/$pmj" ;;
  *) pmj=$(command -v "$pmj" || true) ;;
esac
[ -n "$pmj" ] || stop "there is no pmj to pack with. Name one with PMJ, or put one on the PATH. Packmoji's README says how to build it: https://github.com/thatplatypus/Packmoji"
[ -f "$pmj" ] && [ -x "$pmj" ] || stop "$pmj, which PMJ names, is not a program that can be run"
for tool in git perl python3; do
  command -v "$tool" > /dev/null 2>&1 || stop "it needs $tool, which is not on the PATH"
done
git rev-parse --is-inside-work-tree > /dev/null 2>&1 \
  || stop "$root is not a checkout. It is git that says which files are the repository's and which versions are tagged"
if command -v sha256sum > /dev/null 2>&1; then
  sha256() { sha256sum "$1" | cut -d' ' -f1; }
else
  sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
fi

work="$root/build/release"
rm -rf "$work"
mkdir -p "$work/files" "$work/locks" "$work/site" "$work/apps" "$work/tagged" || stop "$work cannot be made"

problems=0
report() { problems=$((problems + 1)); echo "  $1"; }
# What pmj said, under the problem it belongs to.
said() { sed 's/^/      /' <<< "$1"; }

# pmj keeps its cache, and whatever else it keeps, in the rehearsal's own folder.
packing() { env PACKMOJI_HOME="$work/home" "$pmj" "$@"; }

echo "release: pmj $(packing --version 2>&1 | head -1)"

# ── Pack each package, and hold a version that is tagged to its tag

folders=0
: > "$work/packed"
for folder in packages/*/; do
  folder=${folder%/}
  package=${folder#packages/}
  [ -d "$folder" ] && [ "$package" != shared ] || continue
  folders=$((folders + 1))

  if [ ! -f "$folder/packmoji.json" ]; then
    report "$package: no packmoji.json"
    continue
  fi
  name=; version=; unreadable=
  while IFS= read -r line; do
    case "$line" in
      name=*) name=${line#name=} ;;
      version=*) version=${line#version=} ;;
      unreadable=*) unreadable=${line#unreadable=} ;;
    esac
  done <<< "$(perl "$here/release.pl" manifest "$folder/packmoji.json")"
  if [ -n "$unreadable" ]; then
    report "$package: packmoji.json cannot be read: $unreadable"
    continue
  fi
  case "$name" in
    "@$OWNER/"?*) bare=${name#"@$OWNER/"} ;;
    *) report "$package: packmoji.json names ${name:-nothing}, and a package of this repository is @$OWNER/ and its name"
       continue ;;
  esac

  file="$bare-$version.pmj.tar.gz"
  # So that a file an earlier run left there cannot stand for this one.
  rm -f "$folder/target/$file"
  if ! out=$(cd "$folder" && packing pack 2>&1); then
    report "$package: pmj pack refused it:"
    said "$out"
    continue
  fi
  if [ ! -f "$folder/target/$file" ]; then
    report "$package: pmj pack did not write target/$file:"
    said "$out"
    continue
  fi
  cp "$folder/target/$file" "$work/files/$file"
  digest=$(sha256 "$work/files/$file")

  # A published version never changes. So once a version is tagged, the folder has to go
  # on packing to what it packs at the tag, until its manifest names a new version. The
  # tag's own copy of the repository is taken out of git through an index of its own, so
  # that neither the checkout nor its index is touched, and pmj is asked what it packs:
  # nothing here says which files a release holds.
  tag="$bare-v$version"
  state="not released yet"
  if git rev-parse -q --verify "refs/tags/$tag^{commit}" > /dev/null 2>&1; then
    tagged="$work/tagged/$bare"
    mkdir -p "$tagged"
    released=
    if GIT_INDEX_FILE="$tagged.index" git read-tree "$tag" 2> /dev/null \
        && GIT_INDEX_FILE="$tagged.index" git checkout-index --all --prefix="$tagged/" 2> /dev/null \
        && [ -f "$tagged/$folder/packmoji.json" ] \
        && (cd "$tagged/$folder" && packing pack > /dev/null 2>&1) \
        && [ -f "$tagged/$folder/target/$file" ]; then
      released=$(sha256 "$tagged/$folder/target/$file")
    fi
    if [ -z "$released" ]; then
      report "$package: the tag $tag is there, and $folder as that tag has it does not pack to $file. A tag belongs on a commit whose manifest names its version"
    elif [ "$released" != "$digest" ]; then
      report "$package: $version is released (the tag $tag), and what would be packed now is not what the tag packs: sha256 $digest now, $released then. A published version never changes: give the package a new version in $folder/packmoji.json"
    else
      state="released, and unchanged since"
    fi
  fi

  mkdir -p "$work/site/$OWNER/$OWN/releases/download/$tag"
  cp "$work/files/$file" "$work/site/$OWNER/$OWN/releases/download/$tag/$file"
  echo "$bare|$version|$digest|$file|$folder|$state" >> "$work/packed"
done

[ "$folders" -gt 0 ] || report "no package under packages/"
packed=$(grep -c '' "$work/packed")

# ── Add each package to an application, from a stand-in for GitHub

# Only when every package packed: one that needs a neighbour which did not pack would be
# reported a second time, as not found.
if [ "$packed" -eq "$folders" ] && [ "$packed" -gt 0 ]; then
  python3 -u "$here/release-github.py" "$work/site" > "$work/github.log" 2>&1 &
  server=$!
  trap 'kill "$server" 2> /dev/null; wait "$server" 2> /dev/null' EXIT
  # Waited for by what it does and not by the clock: it has started when it names its
  # port, and it has failed when it is gone.
  port=
  since=$SECONDS
  while [ -z "$port" ] && [ $((SECONDS - since)) -lt 60 ]; do
    port=$(sed -n '1s/^port \([0-9][0-9]*\)$/\1/p' "$work/github.log")
    [ -n "$port" ] || { kill -0 "$server" 2> /dev/null || break; sleep 0.1; }
  done
  [ -n "$port" ] || stop "the stand-in for GitHub did not start: $(cat "$work/github.log")"

  # With no token: pmj sends one to the address of GitHub's API, which here is the stand-in.
  installing() {
    env -u GITHUB_TOKEN -u GH_TOKEN PACKMOJI_HOME="$work/home" \
      PACKMOJI_GITHUB="http://127.0.0.1:$port" PACKMOJI_GITHUB_API="http://127.0.0.1:$port" "$pmj" "$@"
  }

  while IFS='|' read -r bare version digest file folder state <&3; do
    app="uses_$bare"
    if ! out=$(cd "$work/apps" && installing new "@rehearsal/$app" 2>&1); then
      report "$bare: pmj did not make an application to add it to:"
      said "$out"
      continue
    fi
    # The version is named, so that a version that is a pre-release is rehearsed like any
    # other, and so that nothing is asked of GitHub's API, which would have to be made up.
    # A package that is not named as the repository is cannot be found from its name, and
    # is added as its README says to add it. The one that is finds its neighbours itself.
    if [ "$bare" = "$OWN" ]; then where=; else where="--repository $REPOSITORY"; fi
    # $where is nothing or two words, and is left unquoted to be either.
    # shellcheck disable=SC2086
    if ! out=$(cd "$work/apps/$app" && installing add "@$OWNER/$bare@$version" $where 2>&1); then
      report "$bare: pmj did not add it to an application:"
      said "$out"
      continue
    fi
    cp "$work/apps/$app/packmoji.lock" "$work/locks/$bare.lock"

    while read -r locked at sha; do
      [ -n "$locked" ] || continue
      here_is=$(awk -F'|' -v name="${locked#"@$OWNER/"}" '$1 == name { print $2 " with sha256 " $3 }' "$work/packed")
      [ "$here_is" = "$at with sha256 $sha" ] \
        || report "$bare: the application that added it locked $locked $at with sha256 $sha, and what was packed here is ${here_is:-nothing of that name}"
    done <<< "$(perl "$here/release.pl" lock "$work/apps/$app/packmoji.lock")"

    # pmj pack packs what is on the disk. In a checkout that is as git has it, that is the
    # commit. At a desk it may be more: a source that was tried out and never added.
    files="$work/home/cache/$OWNER/$bare/$version/$digest"
    if [ ! -d "$files" ]; then
      report "$bare: pmj added it, and its files are not in pmj's cache at $files"
      continue
    fi
    while IFS= read -r path; do
      path=${path#./}
      git ls-files --error-unmatch -- "$folder/$path" > /dev/null 2>&1 \
        || report "$bare: its release would hold $path, which git does not track in $folder"
    done <<< "$(cd "$files" && find . -type f)"
  done 3< "$work/packed"
fi

if [ "$problems" -eq 1 ]; then
  echo "release: 1 problem"
  exit 1
elif [ "$problems" -gt 0 ]; then
  echo "release: $problems problems"
  exit 1
fi

: > "$work/summary.txt"
while IFS='|' read -r bare version digest file folder state; do
  echo "  @$OWNER/$bare $version: $state"
  echo "      $file  sha256 $digest"
  echo "@$OWNER/$bare $version $digest $file" >> "$work/summary.txt"
done < "$work/packed"
echo "release: $packed packed and installed, no problem found"
