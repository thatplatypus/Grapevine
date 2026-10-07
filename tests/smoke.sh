#!/usr/bin/env bash
# End-to-end smoke test: starts build/bin/todo-api on a spare port and checks every route over real HTTP.
set -uo pipefail
cd "$(dirname "$0")/.."
PORT=${PORT:-8099}
B="http://127.0.0.1:$PORT"
LOG=build/smoke-server.log
PORT=$PORT stdbuf -oL ./build/bin/todo-api > "$LOG" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null' EXIT
for _ in $(seq 50); do curl -s -o /dev/null "$B/" && break; sleep 0.1; done

pass=0; fail=0
check() { # name expected_status expected_body_fragment curl-args...
  local name=$1 want=$2 frag=$3; shift 3
  local out status body
  out=$(curl -s -i "$@" | tr -d '\r')
  status=$(head -1 <<<"$out" | cut -d' ' -f2)
  body=$(awk 'f{print} /^$/{f=1}' <<<"$out")
  if [[ "$status" == "$want" && "$out" == *"$frag"* ]]; then
    pass=$((pass+1)); printf '  ✅ %-44s %s\n' "$name" "$status"
  else
    fail=$((fail+1)); printf '  ❌ %-44s got %s, want %s containing %q\n     body: %s\n' "$name" "$status" "$want" "$frag" "$body"
  fi
}

echo "Minimal API"
check "GET / (text)"                          200 'Hello from Grapevine'          "$B/"
check "middleware adds X-Powered-By"          200 'X-Powered-By: Grapevine'       "$B/"
check "route param + query + %-decoding"      200 '"Howdy there, Tom!"'      "$B/hello/Tom?greeting=Howdy%20there"
check "default query value"                   200 '"Hello, Ada!"'            "$B/hello/Ada"
check "UTF-8 escape in a route parameter"     200 '"Hello, café!"'           "$B/hello/caf%C3%A9"
check "plus sign stays a plus in a path"      200 '"Hello, a+b!"'            "$B/hello/a+b"
check "plus sign is a space in a query"       200 '"Good day, Tom!"'         "$B/hello/Tom?greeting=Good+day"
check "POST /echo returns body"               200 'ping 🍇'                  -X POST "$B/echo" --data-binary 'ping 🍇'

check "every response has a Date"            200 'Date: '                   "$B/"
check "lower-case method is not implemented"  501 'not implemented'          -X get "$B/"
check "bad percent-escape in the target"      400 'percent-escape'           "$B/hello/%zz"

echo "Controller: /todos"
check "list empty"                            200 '[]'                       "$B/todos"
check "HEAD has the length and no body"       200 'Content-Length: 2'        -I "$B/todos"
check "OPTIONS lists the methods"             204 'Allow: GET, HEAD, POST, OPTIONS' -X OPTIONS "$B/todos"
check "create"                                201 '"id":1'                   -X POST "$B/todos" -d '{"title":"Train an Emojicode model"}'
check "create sets Location"                  201 'Location: /todos/2'       -X POST "$B/todos" -d '{"title":"Port Hermes to 🍇"}'
check "trailing emoji survives"               200 '"Port Hermes to 🍇"'      "$B/todos/2"
check "JSON escaping"                         201 '"say \"hi\"\nbye"'       -X POST "$B/todos" -d '{"title":"say \"hi\"\nbye"}'
check "create rejects missing title"          400 'non-empty'                -X POST "$B/todos" -d '{"nope":1}'
check "create rejects invalid JSON"           400 'non-empty'                -X POST "$B/todos" -d 'not json'
big=$(head -c 20000 /dev/zero | tr '\0' a)
check "a body over the sample's limit is 413"  413 'larger than the limit'    -X POST "$B/todos" -d "{\"title\":\"$big\"}"
check "update"                                200 '"done":true'              -X PUT "$B/todos/1" -d '{"done":true}'
check "filter ?done=true"                     200 '"id":1'                   "$B/todos?done=true"
check "filter ?done=false"                   200 '"id":2'                   "$B/todos?done=false"
check "get unknown id"                        404 'Todo 99 not found'        "$B/todos/99"
check "non-integer id"                        400 'integer'                  "$B/todos/abc"
check "delete"                                204 ''                         -X DELETE "$B/todos/2"
check "delete again"                          404 'not found'                -X DELETE "$B/todos/2"

echo "Group + auth middleware: /admin"
check "no api key"                            401 'x-api-key'                "$B/admin/stats"
check "wrong api key"                         401 'x-api-key'                -H 'x-api-key: nope' "$B/admin/stats"
check "valid key (header name case-insens.)"  200 '"role":"admin"'           -H 'X-Api-Key: vineyard' "$B/admin/stats"

echo "Connection"
reused=$(curl -s -o /dev/null -w '%{num_connects}' "$B/" -o /dev/null "$B/todos")
if [[ "$reused" == "10" ]]; then
  pass=$((pass+1)); printf '  ✅ %-44s %s\n' "two requests share one connection" "$reused"
else
  fail=$((fail+1)); printf '  ❌ %-44s got %s, want 10 (one new connection, then none)\n' "two requests share one connection" "$reused"
fi

echo "Router errors"
check "unknown path"                          404 'No route for GET /nope'   "$B/nope"
check "wrong method"                          405 'No route for PATCH /'     -X PATCH "$B/"
check "405 says what is allowed"              405 'Allow: GET, HEAD, OPTIONS' -X PATCH "$B/"
check "problem+json content type"             404 'application/problem+json' "$B/nope"

echo
echo "Request log (from the 📝 middleware):"
sed 's/^/    /' "$LOG"
echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
