#!/usr/bin/env bash
# Looks for what would make a release of a package wrong, as far as that can be seen without
# packing one. A release of a package is its own folder and nothing above it, and holds the
# files that the package's manifest names. So the manifest has to be there and name the
# folder's package, the byte helpers and the license have to be in the folder as files of
# their own, and neither a source nor a native file may be built from anything that the
# manifest's patterns leave out.
#
# It is no proof that a packed release builds: that takes packing one and building from
# what was packed, which is Packmoji's to do. Nor does it say whether a manifest is a good
# one, which is Packmoji's as well. It asks a manifest five things, which tests/packages.pl
# reads out of it, and goes by the two patterns the manifests have today: *.🍇 for sources
# and native/*.cpp for native files. A package that comes to keep its sources anywhere else
# changes its manifest and this script together.
#
# Every folder under packages/ is a package but shared, which holds what the packages have
# copies of. tests/packages-test.sh tests this script.
#   tests/packages.sh [root]     (default: the repository this script is in)
set -uo pipefail
# The same answer on every machine. What counts as a space is otherwise the locale's to say,
# and this runs on a Mac at a desk and in the image on GitHub.
export LC_ALL=C
here="$(cd "$(dirname "$0")" && pwd)"
cd "${1:-$here/..}" || exit 2
problems=0
report() { problems=$((problems + 1)); echo "  $1"; }

# same <package> <file> <what it is a copy of> <that, as a report calls it>
same() {
  if [ -L "packages/$1/$2" ]; then
    report "$1: $2 is a link, and a release has to hold the file itself"
  elif [ ! -f "packages/$1/$2" ]; then
    report "$1: $2 is missing"
  elif [ -f "$3" ] && ! cmp -s "packages/$1/$2" "$3"; then
    report "$1: $2 differs from $4: edit that one, then copy it over this"
  fi
}

# Said once here, and not once for each package as a copy that differs from nothing.
[ -f packages/shared/bytes.🍇 ] || report "packages/shared/bytes.🍇 is missing, which every package has a copy of"
[ -f LICENSE ] || report "the LICENSE at the root is missing, which every package has a copy of"

checked=0
for folder in packages/*/; do
  folder=${folder%/}
  package=${folder#packages/}
  [ -d "$folder" ] && [ "$package" != shared ] || continue
  checked=$((checked + 1))

  name=; entry=; sources=; native=no; native_sources=; unreadable=
  if [ ! -f "$folder/packmoji.json" ]; then
    report "$package: no packmoji.json"
  else
    while IFS= read -r said; do
      case "$said" in
        name=*) name=${said#name=} ;;
        entry=*) entry=${said#entry=} ;;
        sources=*) sources=${said#sources=} ;;
        native=*) native=${said#native=} ;;
        native.sources=*) native_sources=${said#native.sources=} ;;
        unreadable=*) unreadable=${said#unreadable=} ;;
      esac
    done <<< "$(perl "$here/packages.pl" manifest "$folder/packmoji.json")"

    if [ -n "$unreadable" ]; then
      report "$package: packmoji.json cannot be read: $unreadable"
    else
      # The scope is this repository's owner on GitHub, which is who may publish its packages.
      [ "$name" = "@thatplatypus/$package" ] \
        || report "$package: packmoji.json names ${name:-nothing}, and this folder's package is @thatplatypus/$package"
      case "$entry" in
        "") report "$package: packmoji.json names no entry" ;;
        */*) report "$package: the entry $entry is not at the top of the package's folder" ;;
        *) [ -f "$folder/$entry" ] || report "$package: the entry $entry is not there" ;;
      esac
      # What follows goes by this pattern, so a manifest that has another is not one that
      # this check can speak for.
      if [ -z "$sources" ]; then
        report "$package: packmoji.json gives no sources, and this check goes by *.🍇"
      elif [ "$sources" != "*.🍇" ]; then
        report "$package: packmoji.json gives $sources as its sources, and this check goes by *.🍇"
      fi
      if [ "$native" = yes ] && [ ! -d "$folder/native" ]; then
        report "$package: packmoji.json has a native section, and there is no native folder"
      elif [ "$native" != yes ] && [ -d "$folder/native" ]; then
        report "$package: has a native folder, and packmoji.json has no native section"
      elif [ "$native" = yes ] && [ -z "$native_sources" ]; then
        report "$package: packmoji.json gives no native sources, and this check goes by native/*.cpp"
      elif [ "$native" = yes ] && [ "$native_sources" != "native/*.cpp" ]; then
        report "$package: packmoji.json gives $native_sources as its native sources, and this check goes by native/*.cpp"
      fi
    fi
  fi

  same "$package" bytes.🍇 packages/shared/bytes.🍇 packages/shared/bytes.🍇
  same "$package" LICENSE LICENSE "the LICENSE at the root"

  # *.🍇 is the top of the folder and nothing below it. So a file that is included from
  # anywhere else is either not the package's, or is compiled here and left out of a
  # release, and so is one of any other kind.
  included=$(perl "$here/packages.pl" includes "$folder"/*.🍇)
  if [ -n "$included" ]; then
    while IFS= read -r line; do
      file=${line%%:*}; rest=${line#*:}; number=${rest%%:*}; path=${rest#*:}
      case "$path" in
        */*) report "$package: $file:$number includes $path, which is not at the top of the package's folder" ;;
        *.🍇) ;;
        *) report "$package: $file:$number includes $path, which *.🍇 does not take" ;;
      esac
    done <<< "$included"
  fi

  # native/*.cpp is the top of the native folder, and C++ files only. A header there, or a
  # file further down, is compiled with here and left out of a release.
  if [ -d "$folder/native" ]; then
    found=$(find "$folder/native" -mindepth 1 \( -type f -o -type l \) | sort)
    if [ -n "$found" ]; then
      while IFS= read -r file; do
        inside=${file#"$folder"/native/}
        case "$inside" in
          */*) taken=no ;;
          *.cpp) taken=yes; [ -L "$file" ] && taken=no ;;
          *) taken=no ;;
        esac
        [ "$taken" = yes ] || report "$package: native/$inside is not taken by native/*.cpp, so a release would leave it out"
      done <<< "$found"
    fi
    for file in "$folder"/native/*.cpp; do
      [ -f "$file" ] || continue
      included=$(grep -n '^[[:space:]]*#[[:space:]]*include[[:space:]]*"' "$file" || true)
      [ -n "$included" ] || continue
      while IFS= read -r line; do
        path=$(sed 's/^[0-9]*:[[:space:]]*#[[:space:]]*include[[:space:]]*"\([^"]*\)".*/\1/' <<< "$line")
        case "$path" in
          ../*|*/../*) report "$package: $file:${line%%:*} includes $path, which is outside the package's native folder" ;;
        esac
      done <<< "$included"
    done
  fi
done

[ "$checked" -gt 0 ] || report "no package under packages/"

if [ "$problems" -eq 1 ]; then
  echo "packages: 1 problem"
  exit 1
elif [ "$problems" -gt 0 ]; then
  echo "packages: $problems problems"
  exit 1
fi
echo "packages: $checked checked, no problem found"
