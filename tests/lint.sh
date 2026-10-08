#!/usr/bin/env bash
# Checks the sources for constructs that are known to leak memory, crash or corrupt
# memory in Emojicode 1.0 beta 2. Each rule exists because the thing it forbids went
# wrong here once; the README's gotchas say how.
#   tests/lint.sh
set -uo pipefail
cd "$(dirname "$0")/.."
problems=0
report() { problems=$((problems + 1)); echo "  $1"; }

all=$(find packages samples -name '*.🍇' | sort)
# Code that runs for as long as a server does. Test programs may use interpolation.
served=$(find packages samples -name '*.🍇' -not -path '*/tests/unit/*' -not -path '*/tests/fuzz/*' \
  -not -path 'packages/shared/tests/*' -not -name 'check.🍇' -not -name 'tests.🍇' | sort)

# 1. Early exits and reassignments the compiler mishandles. These need to know which block
#    and which function a line is in, so they live in lint.pl.
out=$(perl tests/lint.pl $all)
[ -n "$out" ] && while IFS= read -r line; do report "$line"; done <<< "$out"

# 2. String interpolation leaks the text of every value it inserts.
for file in $served; do
  out=$(grep -n '🧲' "$file" | grep -v '^[0-9]*: *💭' || true)
  [ -n "$out" ] && while IFS= read -r line; do report "string interpolation in served code (join a list instead): $file:$line"; done <<< "$out"
done

# 3. Standard library calls that leak or write past their buffer.
for file in $all; do
  out=$(grep -n '🔫' "$file" | grep -v '🔫🐇🧮' | grep -v '🐇❗️ 🔫' | grep -v '^[0-9]*: *💭' | grep -v "library's 🔫" || true)
  [ -n "$out" ] && while IFS= read -r line; do report "the standard library's 🔫 leaks (use 🔫🐇🧮): $file:$line"; done <<< "$out"
  out=$(grep -n -E '(📪|📫) ' "$file" | grep -v -E '(📪|📫)🐇' | grep -v '🐇❗️ 📪' | grep -v '^[0-9]*: *💭' | grep -v "library's" | grep -v '📗' || true)
  [ -n "$out" ] && while IFS= read -r line; do report "the standard library's 📪 and 📫 overflow (use 📪🐇🧮): $file:$line"; done <<< "$out"
done

# The library's text for a number is wrong for one number, and a server prints numbers
# it was sent. The rule needs lint.pl's view of a line, without strings and comments.
out=$(perl tests/lint.pl --served $served)
[ -n "$out" ] && while IFS= read -r line; do report "$line"; done <<< "$out"

# 4. A panic cannot be caught, so nothing in a package may force-unwrap.
out=$(grep -rn '🍺' packages --include='*.🍇' | grep -v ': *💭' | grep -v '📗' | grep -v 'No 🍺\|no 🍺' || true)
[ -n "$out" ] && while IFS= read -r line; do report "🍺 in a package: $line"; done <<< "$out"

# 5. Unsafe code stays in one file.
out=$(grep -rl '☣️' packages --include='*.🍇' | grep -v '^packages/shared/bytes.🍇$' || true)
[ -n "$out" ] && while IFS= read -r line; do report "☣️ outside packages/shared/bytes.🍇: $line"; done <<< "$out"

if [ "$problems" -gt 0 ]; then
  echo "lint: $problems problems"
  exit 1
fi
echo "lint: clean"
