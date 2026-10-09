#!/usr/bin/env bash
# Builds and runs every program in this folder, and holds each to what README.md says of it.
#
# It needs emojicodec on the path, and Linux: it reads /proc and uses timeout. README.md
# says how the release was set up where this was written.
#
#   ./run.sh
#
# A line for each program: what was expected of it, and whether that is what it did. The
# script ends with 0 only when every program did what the README says, which is to say
# when every defect is still there.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -R "$here"/. "$work"/
cd "$work" || exit 2

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ✅ %-30s %s\n' "$1" "$2"; }
no() { fail=$((fail+1)); printf '  ❌ %-30s %s\n' "$1" "$2"; }

# build NAME: compiles NAME.🍇. The compiler's words are left in NAME.build, its status in $built.
build() {
  if [[ ! -f "$1.🍇" ]]; then built=127; echo "no such program" > "$1.build"; return; fi
  # In a shell of its own that goes on to say how it ended, so that a compiler which aborts
  # is announced to nobody.
  ( emojicodec "$1.🍇" > "$1.build" 2>&1; exit $? ) 2> /dev/null; built=$?
}

# run NAME: runs the program. Its output is left in NAME.out, its status in $ran.
run() {
  ( timeout 300 "./$1" > "$1.out" 2>&1; exit $? ) 2> /dev/null; ran=$?
}

how() { # STATUS: a status in words
  case $1 in
    0) echo "ended well" ;; 124) echo "did not end" ;; 127) echo "was not built" ;;
    134) echo "aborted" ;; 135) echo "bus error" ;; 136) echo "arithmetic error" ;; 139) echo "segmentation fault" ;;
    *) echo "status $1" ;;
  esac
}

# crashes NAME: it compiles, and the program dies of a signal.
crashes() {
  build "$1"
  if [[ $built -ne 0 ]]; then no "$1" "did not compile: $(grep -a -m1 'error' "$1.build")"; return; fi
  run "$1"
  if [[ $ran -ge 129 ]]; then ok "$1" "$(how $ran)"; else no "$1" "wanted a crash: $(how $ran): $(tail -n 1 "$1.out")"; fi
}

# prints NAME TEXT: it compiles and ends well, and TEXT is among what it printed.
prints() {
  build "$1"
  if [[ $built -ne 0 ]]; then no "$1" "did not compile: $(grep -a -m1 'error' "$1.build")"; return; fi
  run "$1"
  if [[ $ran -eq 0 ]] && grep -a -q -F -- "$2" "$1.out"; then ok "$1" "printed: $2"
  else no "$1" "wanted \"$2\": $(how $ran): $(tail -n 1 "$1.out")"; fi
}

# refuses NAME TEXT: the compiler does not build it, and says TEXT.
refuses() {
  build "$1"
  if [[ $built -ne 0 ]] && grep -a -q -F -- "$2" "$1.build"; then ok "$1" "the compiler: $2"
  else no "$1" "wanted the compiler to say \"$2\": status $built: $(grep -a -v 'Run-time type' "$1.build" | grep -a -m1 .)"; fi
}

# passes NAME TEXT: the compiler says TEXT, which is an error of its own making, and reports success.
passes() {
  build "$1"
  if [[ $built -eq 0 ]] && grep -a -q -F -- "$2" "$1.build"; then ok "$1" "the compiler said \"$2\" and ended with 0"
  else no "$1" "wanted \"$2\" and a status of 0: status $built"; fi
}

# folder NAME TEXT: a program of more than one file. Its build.sh says how it is built, and TEXT
# is among what the compiler or the linker says when it fails.
folder() {
  ( "./$1/build.sh" > "$1.build" 2>&1; exit $? ) 2> /dev/null
  if grep -a -q -F -- "$2" "$1.build" && [[ ! -x "$1/main" ]]; then ok "$1" "$2"
  else no "$1" "wanted \"$2\": $(grep -a -v 'Run-time type' "$1.build" | tail -n 1)"; fi
}

# peak PROGRAM: the high-water mark of the program's resident memory in kB, as the kernel
# keeps it (VmHWM). It is read with the shell's own words and without a pause: some of
# these programs end sooner than another program can be started to look at them. How the
# program ended is left in PROGRAM.status.
peak() {
  local pid most=0 key value rest
  "./$1" > /dev/null 2>&1 &
  pid=$!
  while [[ -e /proc/$pid/status ]]; do
    while read -r key value rest; do
      if [[ $key == VmHWM: ]]; then (( value > most )) && most=$value; break; fi
    done 2> /dev/null < "/proc/$pid/status"
  done
  wait $pid
  echo $? > "$1.status"
  echo "$most"
}

# grown NAME: builds the program as it is and with four times its rounds, and leaves in $grown
# how much more memory the longer run held, in kB. A program says how many rounds it runs
# in a line of its own: "  200000 ➡️ rounds".
grown() {
  local rounds short long
  grown=-1; held=
  build "$1"
  [[ $built -eq 0 ]] || return
  rounds=$(sed -n 's/^  \([0-9][0-9]*\) ➡️ rounds$/\1/p' "$1.🍇" | head -n 1)
  [[ -n "$rounds" ]] || return
  sed "s/^  $rounds ➡️ rounds\$/  $((rounds * 4)) ➡️ rounds/" "$1.🍇" > "$1-long.🍇"
  ( emojicodec "$1-long.🍇" > "$1-long.build" 2>&1; exit $? ) 2> /dev/null || return
  short=$(peak "$1"); long=$(peak "$1-long")
  # A program that died says nothing of memory, whatever it held when it did.
  if [[ $(cat "$1.status") -ne 0 || $(cat "$1-long.status") -ne 0 ]]; then
    held="it $(how "$(cat "$1.status")"), and with four times the rounds it $(how "$(cat "$1-long.status")")"; return
  fi
  grown=$((long - short)); held="$short kB after $rounds rounds, $long kB after $((rounds * 4))"
}

# leaks NAME: the longer run holds at least 4 MB more.
leaks() {
  grown "$1"
  if [[ $grown -ge 4096 ]]; then ok "$1" "leaks: $held"; else no "$1" "wanted a leak: ${held:-did not compile}"; fi
}

# steady NAME: the longer run holds no more, give or take a megabyte. The measurement's own check.
steady() {
  grown "$1"
  if [[ "${held:-}" == *kB* && $grown -ge -1024 && $grown -le 1024 ]]; then ok "$1" "steady: $held"
  else no "$1" "wanted steady memory: ${held:-did not compile}"; fi
}

echo "The compiler"
passes   09-reraise-of-a-subclass     "Call parameter type does not match function signature!"
passes   09-reraise-of-a-subclass     "Detected in:"
prints   09-reraise-of-a-subclass     "of the subclass"
passes   01-interpolated-element      "Detected in:"
crashes  01-interpolated-element
prints   02-and-frees-earlier-temporaries "was freed before the call"
prints   03-nan-compares-equal        "a NaN is equal to 0.0"
refuses  05-fresh-object-of-later-class "Assertion \`!isUnknown()' failed"
refuses  06-optional-then-cast        "genericArguments_.front().type() != TypeType::Box"
folder   07-closure-in-a-small-function "Using non-escaping closure as escaping value"
refuses  45-any-as-a-parameter        "Type.cpp:91"

echo "Memory that is freed or left behind while it is in use"
crashes  10-reraise-hides-an-escape
crashes  11-returning-a-parameter
crashes  12-returning-self
crashes  13-declared-after-a-handler
crashes  14-failed-cast-frees
crashes  15-bound-cast-releases-twice

echo "Memory that is never released"
steady   20-steady
leaks    21-interpolation-leaks
leaks    22-return-in-else
leaks    23-variable-in-else
leaks    24-returning-a-local-early
leaks    25-new-list-over-a-variable
leaks    26-return-in-unsafe-block

echo "The standard library and the stock packages"
leaks    30-data-slice-leaks
leaks    31-data-join-leaks
leaks    32-text-split-leaks
leaks    33-dictionary-leaks
crashes  34-lower-case-overflows
prints   35-bytes-taken-for-text      "the bytes FF FE were taken for a text"
prints   36-lowest-integer-as-text    "the lowest integer is written as something else"
prints   37-trim-cuts-a-character     "gave another text"
prints   38-digits-above-thirty-one   "32 in base 36 is written x"
crashes  39-thread-let-go
crashes  41-last-of-an-empty-list
crashes  43-json-without-a-depth
folder   44-package-link-order        "undefined reference"

echo "Meant, it seems, and easy to step into"
refuses  04-real-with-exponent        'Variable "e3" not defined'
refuses  08-override-keeps-parameter  "lets parameter"
prints   42-range-counts-down         "a loop over a count of -2 runs"

echo
echo "$pass as the README says, $fail not"
[[ $fail -eq 0 ]]
