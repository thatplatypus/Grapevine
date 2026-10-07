#!/usr/bin/env bash
# Builds the Grapevine package, the sample app and the in-memory test runner.
#   ./build.sh            build
#   ./build.sh test       build, then run in-memory tests and the HTTP smoke test
set -euo pipefail
cd "$(dirname "$0")"
EC=${EC:-emojicodec}

( cd packages/grapevine \
  && $EC grapevine.🍇 -p grapevine -c -o grapevine.o -i 🏛 \
  && ar rcs libgrapevine.a grapevine.o && rm grapevine.o )
( cd app \
  && $EC main.🍇 -S ../packages -o todo-api \
  && $EC tests.🍇 -S ../packages -o tests \
  && rm -f main.o tests.o )
echo "built app/todo-api and app/tests"

if [[ "${1:-}" == "test" ]]; then
  echo; echo "── in-memory tests"; ./app/tests
  echo; echo "── HTTP smoke test"; ./tests/smoke.sh
fi
