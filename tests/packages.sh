#!/usr/bin/env bash
# Says whether each package can be released by itself. A release of a package is its own
# folder and nothing above it, so all that a package is built from has to be in that
# folder: its manifest, its copy of the byte helpers, its license, and every source that
# its entry includes. tests/packages-test.sh tests this script.
#
# Whether a manifest is a good one is for Packmoji to say. This reads a manifest as text,
# a key to a line, and takes its name and its entry from it and nothing else.
#   tests/packages.sh [root]     (default: the repository this script is in)
set -uo pipefail
cd "${1:-$(dirname "$0")/..}" || exit 2
problems=0
report() { problems=$((problems + 1)); echo "  $1"; }

# said <manifest> <key>: the text under a key that begins a line. A key that is spoken of
# inside another text, a description say, does not begin one.
said() { sed -n 's/^[[:space:]]*"'"$2"'":[[:space:]]*"\(.*\)",\{0,1\}[[:space:]]*$/\1/p' "$1" | head -n 1; }

# same <package> <file> <the one it is a copy of>
same() {
  if [ ! -f "packages/$1/$2" ]; then
    report "$1: $2 is missing"
  elif ! cmp -s "packages/$1/$2" "$3"; then
    report "$1: $2 differs from $4: copy that one over it"
  fi
}

for package in crypto deflate grapevine; do
  folder="packages/$package"

  if [ ! -f "$folder/packmoji.json" ]; then
    report "$package: no packmoji.json"
  else
    name=$(said "$folder/packmoji.json" name)
    [ "$name" = "@thatplatypus/$package" ] || report "$package: packmoji.json names ${name:-nothing}, and the folder is $package"
    entry=$(said "$folder/packmoji.json" entry)
    if [ -z "$entry" ]; then
      report "$package: packmoji.json names no entry"
    elif [ ! -f "$folder/$entry" ]; then
      report "$package: the entry $entry is not there"
    fi
  fi

  same "$package" bytes.🍇 packages/shared/bytes.🍇 packages/shared/bytes.🍇
  same "$package" LICENSE LICENSE "the LICENSE at the root"

  # The manifests give *.🍇 as the sources, which is the top of the folder and nothing
  # below it. So a file that is included from anywhere else is either not the package's,
  # or is compiled here and left out of a release.
  for file in "$folder"/*.🍇; do
    [ -f "$file" ] || continue
    included=$(grep -n '📜[[:space:]]*🔤' "$file" | grep -v '^[0-9]*:[[:space:]]*💭' || true)
    [ -n "$included" ] || continue
    while IFS= read -r line; do
      path=$(sed 's/.*📜[[:space:]]*🔤\(.*\)🔤.*/\1/' <<< "$line")
      case "$path" in
        */*) report "$package: $file:${line%%:*} includes $path, which is not at the top of the package's folder" ;;
      esac
    done <<< "$included"
  done
done

if [ "$problems" -eq 1 ]; then
  echo "packages: 1 problem"
  exit 1
elif [ "$problems" -gt 0 ]; then
  echo "packages: $problems problems"
  exit 1
fi
echo "packages: each fit to be released by itself"
