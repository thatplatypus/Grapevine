#!/usr/bin/env bash
# Tests the lint itself: every marked line of tests/lint-cases/bad.🍇 must be reported
# with the words its 💭 expect: comment gives, nothing unmarked may be reported, and
# tests/lint-cases/good.🍇 must pass untouched.
#   tests/lint-test.sh
set -uo pipefail
cd "$(dirname "$0")/.."
bad=tests/lint-cases/bad.🍇
good=tests/lint-cases/good.🍇
failures=0
fail() { failures=$((failures + 1)); echo "  FAIL $1"; }

reports=$(perl tests/lint.pl "$bad")
checked=0
number=0
while IFS= read -r line; do
  number=$((number + 1))
  case "$line" in
    *"💭 expect: "*)
      words=${line##*💭 expect: }
      checked=$((checked + 1))
      if ! grep -F -- "$bad:$number:" <<< "$reports" | grep -qF -- "$words"; then
        fail "line $number was not reported with \"$words\""
      fi
      ;;
    *)
      if grep -qF -- "$bad:$number:" <<< "$reports"; then
        fail "line $number was reported but is not marked: $(grep -F -- "$bad:$number:" <<< "$reports")"
      fi
      ;;
  esac
done < "$bad"

clean=$(perl tests/lint.pl "$good")
if [ -n "$clean" ]; then
  while IFS= read -r line; do fail "good example reported: $line"; done <<< "$clean"
fi

if [ "$failures" -gt 0 ]; then
  echo "lint-test: $failures failed"
  exit 1
fi
echo "lint-test: $checked rules checked"
