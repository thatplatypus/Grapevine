#!/usr/bin/env bash
# Rehearses a release of each package, and releases nothing.
#
# pmj packs each package and adds each to an application, from a stand-in for GitHub on this
# machine: that is tests/release.sh. Then the packages are built in the image from the files
# pmj unpacked, and from nothing else of theirs, and the programs that import a package are
# built on them and tried out: that is ./build.sh released. Two tests go first, of
# tests/release.sh and of the step that makes a release when a tag is pushed, and that step
# is then run on what pmj packed and locked, as a dry run.
#   ./test-release.sh
# Needs a pmj (the one PMJ names, or one on the PATH), git, perl, python3 and Docker. The
# image is the one GRAPEVINE_IMAGE names, as in the other suites, or grapevine.
set -euo pipefail
cd "$(dirname "$0")"
image=${GRAPEVINE_IMAGE:-grapevine}
tests/publish-test.sh
# The first of the two tests the rehearsal, the second makes it.
tests/release-test.sh
tests/release.sh
# The step's own test writes its archives and lockfiles by hand. Here it meets pmj's, so a
# pmj that came to write either in another form is seen in a rehearsal, and not at a tag.
tests/publish-test.sh rehearsed
docker build --platform linux/amd64 -t "$image" .
# Each release where pmj unpacked it into its cache: nothing of the repository's own copy of
# the package is beside it there, and it is mounted so that it cannot be written to.
mounts=()
while read -r name version digest _; do
  mounts+=(-v "$PWD/build/release/home/cache/${name#@}/$version/$digest:/released/${name#*/}:ro")
done < build/release/summary.txt
docker run --rm --platform linux/amd64 "${mounts[@]}" "$image" ./build.sh released /released
echo "release: rehearsed, and nothing was released"
