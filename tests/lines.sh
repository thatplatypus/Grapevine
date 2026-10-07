#!/usr/bin/env bash
# Checks that every line the server logs comes out whole when many workers log long
# lines at once and standard output is a pipe that is read slowly. One write to a pipe
# is whole only up to 4,096 bytes. The request line holds the path twice, so a path of
# 2,100 bytes makes a longer line than that, and lines written without a lock around
# them cut into each other. The second round makes the pipe non-blocking, as a shared
# standard output can be: a writer that gives up when the pipe is full drops lines.
#   tests/lines.sh      needs build/bin/wire-host, curl and perl
set -uo pipefail
cd "$(dirname "$0")/.."
# A port of its own, whatever PORT says: the image sets PORT for the sample, and the
# smoke test's server may still be on its way out of that one when this starts.
PORT=${LINES_PORT:-8098}
B="http://127.0.0.1:$PORT"
CLIENTS=16
EACH=60
LENGTH=2100
LOG=build/lines-server.log
PIPE=build/lines-server.pipe
failed=0

# round <what it is called> <command that starts the server>...
round() {
  local name=$1; shift
  rm -f "$LOG" "$PIPE"
  mkfifo "$PIPE"
  # The reader takes 4 KB every 2 ms, which is slower than the server writes, so the
  # pipe stays full and every write has to wait its turn.
  perl -e '
    open(my $out, ">", $ARGV[0]) or die "cannot write $ARGV[0]: $!";
    while (sysread(STDIN, my $block, 4096)) { print $out $block; select(undef, undef, undef, 0.002); }
  ' "$LOG" < "$PIPE" &
  local reader=$!
  PORT=$PORT "$@" > "$PIPE" 2>&1 &
  local server=$! up=0
  for _ in $(seq 50); do curl -s -o /dev/null "$B/" && up=1 && break; sleep 0.1; done
  if [[ $up -eq 0 ]]; then
    kill $server $reader 2>/dev/null
    rm -f "$PIPE"
    printf '  ❌ %-44s the server did not start: %s\n' "$name" "$(head -c 300 "$LOG")"
    failed=$((failed + 1))
    return
  fi

  # Each client asks for a path made of its own letter, so a line that holds two letters
  # holds two clients' text. The query makes sixty requests of one URL; it is not logged.
  local clients=() number letter path
  for number in $(seq 1 $CLIENTS); do
    letter=$(printf "\\$(printf '%03o' $((96 + number)))")
    path=$(head -c $LENGTH /dev/zero | tr '\0' "$letter")
    curl -s -o /dev/null "$B/$path?n=[1-$EACH]" &
    clients+=($!)
  done
  wait "${clients[@]}"

  kill -TERM $server
  wait $server
  wait $reader
  rm -f "$PIPE"

  perl -e '
    my ($name, $file, $expected, $length) = @ARGV;
    my $rest = $length - 1;
    open(my $in, "<", $file) or die "cannot read $file: $!";
    my ($whole, $broken, $example) = (0, 0, "");
    while (my $line = <$in>) {
      chomp $line;
      next if $line =~ m{^\S+ INFO  (?:Grapevine listening on |route |stopping$|stopped$|GET / 200 )};
      if ($line =~ m{^\S+ INFO  GET /((.)\2{$rest}) 404 \d+ms method=GET path=/\1 status=404 durationMs=\d+ requestId=\S+$}) {
        $whole++;
      }
      else {
        $broken++;
        $example = substr($line, 0, 60) . " ... (" . length($line) . " bytes)" if $example eq "";
      }
    }
    my $good = $broken == 0 && $whole == $expected;
    printf "  %s %-44s %d whole, %d broken, of %d\n", ($good ? "✅" : "❌"), $name, $whole, $broken, $expected;
    print "     the first broken one starts: $example\n" if $broken;
    exit($good ? 0 : 1);
  ' "$name" "$LOG" $((CLIENTS * EACH)) $LENGTH || failed=$((failed + 1))
}

round "a pipe that is read slowly" ./build/bin/wire-host
# The flag belongs to the pipe, not to the process, so it is still set after the exec.
round "the same pipe, made non-blocking" perl -e '
  use Fcntl;
  fcntl(STDOUT, F_SETFL, fcntl(STDOUT, F_GETFL, 0) | O_NONBLOCK) or die "cannot set O_NONBLOCK: $!";
  exec @ARGV or die "cannot start $ARGV[0]: $!";
' ./build/bin/wire-host

echo "$((2 - failed)) passed, $failed failed"
[[ $failed -eq 0 ]]
