#!/usr/bin/env bash
# End-to-end smoke test: starts build/bin/todo-api on a spare port and checks every route over real HTTP.
set -uo pipefail
cd "$(dirname "$0")/.."
PORT=${PORT:-8099}
B="http://127.0.0.1:$PORT"
LOG=build/smoke-server.log
PORT=$PORT ./build/bin/todo-api > "$LOG" 2>&1 &
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
check "GET / is the page"                     200 '<h1>Grapevine todos</h1>'      "$B/"
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
check "create"                                201 '"id":1'                   -X POST "$B/todos" -H 'Content-Type: application/json' -d '{"title":"Train an Emojicode model"}'
check "create sets Location"                  201 'Location: /todos/2'       -X POST "$B/todos" -H 'Content-Type: application/json' -d '{"title":"Port Hermes to 🍇"}'
check "trailing emoji survives"               200 '"Port Hermes to 🍇"'      "$B/todos/2"
check "JSON escaping"                         201 '"say \"hi\"\nbye"'       -X POST "$B/todos" -H 'Content-Type: application/json' -d '{"title":"say \"hi\"\nbye"}'
check "create rejects missing title"          400 '"detail":"The request is not valid","errors":{"title":["is required"]}' -X POST "$B/todos" -H 'Content-Type: application/json' -d '{"nope":1}'
check "create rejects a title that is no text" 400 '"errors":{"title":["must be text"]}' -X POST "$B/todos" -H 'Content-Type: application/json' -d '{"title":7}'
check "create rejects a blank title"          400 '"errors":{"title":["must not be empty"]}' -X POST "$B/todos" -H 'Content-Type: application/json' -d '{"title":"  "}'
check "create rejects invalid JSON"           400 'The body is not valid JSON: ' -X POST "$B/todos" -H 'Content-Type: application/json' -d 'not json'
check "create rejects a title given twice"    400 'The body is not valid JSON: repeated key at byte 15' -X POST "$B/todos" -H 'Content-Type: application/json' -d '{"title":"one","title":"two"}'
big=$(head -c 20000 /dev/zero | tr '\0' a)
check "a body over the sample's limit is 413"  413 'larger than the limit'    -X POST "$B/todos" -H 'Content-Type: application/json' -d "{\"title\":\"$big\"}"
check "a todo that does not say it is JSON is a 415" 415 'The body must be JSON, and its Content-Type is text/plain' -X POST "$B/todos" -H 'Content-Type: text/plain' -d '{"title":"sent as plain text"}'
check "update"                                200 '"done":true'              -X PUT "$B/todos/1" -H 'Content-Type: application/json' -d '{"done":true}'
check "filter ?done=true"                     200 '"id":1'                   "$B/todos?done=true"
check "filter ?done=false"                   200 '"id":2'                   "$B/todos?done=false"
check "a filter that is neither is refused"   400 '"errors":{"done":["must be true or false"]}' "$B/todos?done=maybe"
check "update rejects a done that is no boolean" 400 '"errors":{"done":["must be true or false"]}' -X PUT "$B/todos/1" -H 'Content-Type: application/json' -d '{"done":"yes"}'
check "update rejects a body that is no object" 400 'The body must be a JSON object' -X PUT "$B/todos/1" -H 'Content-Type: application/json' -d '[1]'
check "get unknown id"                        404 'Todo 99 not found'        "$B/todos/99"
check "an id that is no integer has no route" 404 'No route for GET /todos/abc' "$B/todos/abc"
check "nor one too large to be one"           404 'No route for GET /todos/18446744073709551617' "$B/todos/18446744073709551617"
check "delete"                                204 ''                         -X DELETE "$B/todos/2"
check "delete again"                          404 'not found'                -X DELETE "$B/todos/2"

echo "Signing in, and the numbers: /login and /admin"
signin() { curl -s -X POST "$B/login" -H 'Content-Type: application/json' -d "{\"user\":\"admin\",\"password\":\"$1\"}"; }
check "the numbers ask for a token"           401 'WWW-Authenticate: Bearer' "$B/admin/stats"
check "the key of old opens nothing"          401 'This needs a token'       -H 'x-api-key: vineyard' "$B/admin/stats"
check "no route under /admin is a 404"        404 'No route for GET /admin/nothing' "$B/admin/nothing"
check "a wrong password is refused"           401 'The name or the password is not right' -X POST "$B/login" -H 'Content-Type: application/json' -d '{"user":"admin","password":"nope"}'
check "the README's password signs in"        200 '"expiresIn":3600'         -X POST "$B/login" -H 'Content-Type: application/json' -d '{"user":"admin","password":"vineyard"}'
token=$(signin vineyard | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
check "the token opens the numbers"           200 '"role":"admin"'           -H "Authorization: Bearer $token" "$B/admin/stats"
check "whatever the case of its scheme"       200 '"role":"admin"'           -H "authorization: bearer $token" "$B/admin/stats"
check "a token that was changed is refused"   401 'error="invalid_token"'    -H "Authorization: Bearer ${token}x" "$B/admin/stats"
check "and so is none at all, again"          401 'This needs a token'       "$B/admin/stats"
# Three tries so far from this address. Two more, and the sixth within the minute is one too many.
signin nope > /dev/null; signin nope > /dev/null
check "a sixth try in a minute is turned away" 429 'Retry-After: '            -X POST "$B/login" -H 'Content-Type: application/json' -d '{"user":"admin","password":"vineyard"}'
check "the list is not counted with them"     200 '"title"'                  "$B/todos"
if grep -q 'WARN  todo.adminPassword is the one in the sample.s README' "$LOG" && ! grep -q 'vineyard' "$LOG"; then
  pass=$((pass+1)); printf '  ✅ %s\n' "the log warns of the README's password, and does not write it"
else
  fail=$((fail+1)); printf '  ❌ %s\n%s\n' "the log warns of the README's password, and does not write it" "$(grep -i 'password\|vineyard' "$LOG" | sed 's/^/     /' | head -5)"
fi
if grep -q 'WARN  auth.tokenKey is not set' "$LOG"; then
  pass=$((pass+1)); printf '  ✅ %s\n' "and of a key made for this run"
else
  fail=$((fail+1)); printf '  ❌ %s\n' "and of a key made for this run"
fi

echo "What the API says of itself: /openapi.json"
check "the API describes itself as OpenAPI 3.1" 200 '"openapi":"3.1.1"'        "$B/openapi.json"
check "as JSON"                               200 'Content-Type: application/json; charset=utf-8' "$B/openapi.json"
check "with the list's path in it"            200 '"/todos/{id}":{"get":'       "$B/openapi.json"
check "and the numbers', which ask for a token" 200 '"/admin/stats":{"get":{"operationId":"getAdminStats"' "$B/openapi.json"
check "and a todo's bound, as the binder has it" 200 '"maxLength":200'            "$B/openapi.json"
etag=$(curl -s -I "$B/openapi.json" | tr -d '\r' | sed -n 's/^ETag: //p')
check "a client that has it is told 304"      304 ''                         -H "If-None-Match: $etag" "$B/openapi.json"

echo "Connection"
reused=$(curl -s -o /dev/null -w '%{num_connects}' "$B/" -o /dev/null "$B/todos")
if [[ "$reused" == "10" ]]; then
  pass=$((pass+1)); printf '  ✅ %-44s %s\n' "two requests share one connection" "$reused"
else
  fail=$((fail+1)); printf '  ❌ %-44s got %s, want 10 (one new connection, then none)\n' "two requests share one connection" "$reused"
fi

echo "Request IDs"
check "a request's ID comes back"            200 'X-Request-Id: smoke-1'    -H 'X-Request-Id: smoke-1' "$B/"
check "one is made when none is sent"        200 'X-Request-Id: '           "$B/"
if grep -q ' GET / 200 .* requestId=smoke-1$' "$LOG"; then
  pass=$((pass+1)); printf '  ✅ %-44s\n' "the request log has the ID"
else
  fail=$((fail+1)); printf '  ❌ %-44s no line for GET / with requestId=smoke-1\n' "the request log has the ID"
fi

echo "Router errors"
check "unknown path"                          404 'No route for GET /nope'   "$B/nope"
check "wrong method"                          405 'No route for PATCH /todos' -X PATCH "$B/todos"
check "405 says what is allowed"              405 'Allow: GET, HEAD, POST, OPTIONS' -X PATCH "$B/todos"
check "problem+json content type"             404 'application/problem+json' "$B/nope"
check "a 404 is a whole problem document"     404 '{"type":"about:blank","title":"Not Found","status":404,"detail":"No route for GET /nope"}' "$B/nope"
check "and so is what a handler refuses"      404 '{"type":"about:blank","title":"Not Found","status":404,"detail":"Todo 99 not found"}' "$B/todos/99"

echo "The page"
check "the page is HTML"                      200 'Content-Type: text/html; charset=utf-8' "$B/"
check "its stylesheet is CSS"                 200 'Content-Type: text/css; charset=utf-8' "$B/style.css"
check "its script is JavaScript"              200 'Content-Type: text/javascript; charset=utf-8' "$B/app.js"
check "its icon is an image"                  200 'Content-Type: image/svg+xml' "$B/favicon.svg"
check "a HEAD for the page says how long it is" 200 'Content-Length: '      -I "$B/"
check "the page is told where its API is"     200 '{"api":""}'               "$B/config.json"
check "and not to keep that"                  200 'Cache-Control: no-store'  "$B/config.json"
check "the server says it is well"            200 '{"status":"ok"}'          "$B/health"
check "to a POST the page's files are not there" 404 'No route for POST /style.css' -X POST "$B/style.css"
check "a path of the API is the API's for every method" 405 'No route for GET /echo' "$B/echo"
check "and the 405 lists what the API's route allows" 405 'Allow: POST, OPTIONS' "$B/echo"

echo "For a browser"
check "the page comes with a content security policy" 200 "Content-Security-Policy: default-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'" "$B/"
check "and with the headers that make a browser careful" 200 'X-Content-Type-Options: nosniff' "$B/"
check "so does what the API answers"          200 'X-Frame-Options: DENY'    "$B/todos"
check "a page on another origin may not read the API" 403 'The origin https://evil.example is not allowed' -H 'Origin: https://evil.example' "$B/todos"
check "nor post to it"                        403 'The origin https://evil.example is not allowed' -X POST -H 'Origin: https://evil.example' -H 'Content-Type: application/json' -d '{"title":"forged"}' "$B/todos"
check "and what it posted is not in the list" 200 '"title"'                  "$B/todos"
forged=$(curl -s "$B/todos" | grep -c 'forged' || true)
if [[ "$forged" == 0 ]]; then pass=$((pass+1)); printf '  ✅ %s\n' "nothing forged was taken"; else fail=$((fail+1)); printf '  ❌ %s\n' "nothing forged was taken"; fi

# What the page is made of matters as much as what it does: the content security policy
# the sample sends allows no script or style in the page itself, and text from the API is
# only safe as long as the script never hands it to the HTML parser.
W=samples/todo/web
absent() { # name pattern except file   passes when no line of the file matches pattern, but for lines that match except
  local name=$1 pattern=$2 except=$3 file=$4
  local found
  found=$(grep -n -E -- "$pattern" "$file" | grep -v -E -- "$except" || true)
  if [[ ! -f "$file" ]]; then
    fail=$((fail+1)); printf '  ❌ %s\n     %s is not there\n' "$name" "$file"
  elif [[ -z "$found" ]]; then
    pass=$((pass+1)); printf '  ✅ %s\n' "$name"
  else
    fail=$((fail+1)); printf '  ❌ %s\n%s\n' "$name" "$(sed 's/^/     /' <<<"$found" | head -5)"
  fi
}
NONE='^$'
absent "every script the page loads is a file"            '<script' 'src="[^"]+"' "$W/index.html"
absent "and has nothing written between its tags"         '<script[^>]*>' '<script[^>]*></script>' "$W/index.html"
absent "the page has no style of its own in it"           '<style|[[:space:]]style=' "$NONE" "$W/index.html"
absent "nor a handler written into a tag"                 '[[:space:]]on[a-z]+=' "$NONE" "$W/index.html"
absent "it loads nothing from another site"               '(src|href)="([a-z]+:)?//' "$NONE" "$W/index.html"
absent "and names its own files without a slash in front" '(src|href)="/' "$NONE" "$W/index.html"
absent "the script never writes markup"                   'innerHTML|outerHTML|insertAdjacentHTML|document\.write|eval\(|new Function' "$NONE" "$W/app.js"

echo "Without its page"
# The sample's source files are enough to run it. Started where the page's files are not,
# and told nothing about where they are, it serves its API and says hello.
ROOT=$PWD
ELSEWHERE=$(mktemp -d)
C="http://127.0.0.1:$((PORT + 1))"
( cd "$ELSEWHERE" && PORT=$((PORT + 1)) exec "$ROOT/build/bin/todo-api" ) > build/smoke-pageless.log 2>&1 &
BARE=$!
trap 'kill $PID $BARE 2>/dev/null' EXIT
for _ in $(seq 50); do curl -s -o /dev/null "$C/" && break; sleep 0.1; done
check "started away from its page, the sample says hello" 200 'Hello from Grapevine 🍇' "$C/"
check "in plain text"                         200 'Content-Type: text/plain; charset=utf-8' "$C/"
check "its API answers"                       200 '[]'                       "$C/todos"
check "and no file is served"                 404 'No route for GET /style.css' "$C/style.css"
if curl -s "$C/openapi.json" | grep -q '"paths":{"/login"' && ! curl -s "$C/openapi.json" | grep -q '"/":'; then
  pass=$((pass+1)); printf '  ✅ %s\n' "what stands in for the page is no part of the API's description"
else
  fail=$((fail+1)); printf '  ❌ %s\n' "what stands in for the page is no part of the API's description"
fi
if grep -q 'WARN.*no page' build/smoke-pageless.log; then
  pass=$((pass+1)); printf '  ✅ %s\n' "its log says that there is no page"
else
  fail=$((fail+1)); printf '  ❌ %s\n%s\n' "its log says that there is no page" "$(sed 's/^/     /' build/smoke-pageless.log | head -5)"
fi

# Long answers go out as gzip to a client that takes it, and curl's own zlib reads them.
for number in $(seq 1 30); do
  curl -s -o /dev/null -X POST "$C/todos" -H 'Content-Type: application/json' -d "{\"title\":\"one of thirty, number $number\"}"
done
check "a long list is sent as gzip to a client that takes it" 200 'Content-Encoding: gzip' --compressed "$C/todos"
check "and says that it depends on what a client takes" 200 'Vary: Origin, Accept-Encoding' --compressed "$C/todos"
check "a HEAD for it says the same"           200 'Content-Encoding: gzip'   -I -H 'Accept-Encoding: gzip' "$C/todos"
plain=$(curl -s "$C/todos")
unpacked=$(curl -s --compressed "$C/todos")
sent=$(curl -s -o /dev/null -w '%{size_download}' -H 'Accept-Encoding: gzip' "$C/todos")
if [[ ${#plain} -gt 1024 && "$plain" == "$unpacked" && "$sent" -lt $(( ${#plain} / 2 )) ]]; then
  pass=$((pass+1)); printf '  ✅ %s\n' "curl reads the same list out of it, from $sent bytes in place of ${#plain}"
else
  fail=$((fail+1)); printf '  ❌ %s\n     %s bytes as they are, %s read back, %s sent\n' "curl reads the same list out of the compressed answer, from less than half the bytes" "${#plain}" "${#unpacked}" "$sent"
fi
if curl -s -i "$C/todos" | grep -qi '^content-encoding'; then
  fail=$((fail+1)); printf '  ❌ %s\n' "a client that says nothing of what it takes is sent no encoding"
else
  pass=$((pass+1)); printf '  ✅ %s\n' "a client that says nothing of what it takes is sent no encoding"
fi
if curl -s -i -H 'Accept-Encoding: gzip' "$C/todos/1" | grep -qi '^content-encoding'; then
  fail=$((fail+1)); printf '  ❌ %s\n' "one todo is too little to compress"
else
  pass=$((pass+1)); printf '  ✅ %s\n' "one todo is too little to compress"
fi
kill $BARE 2>/dev/null

# A directory that someone named is another matter: one that is not there is a mistake,
# and the server does not start on a mistake.
GRAPEVINE_TODO_WEBROOT=/no/such/directory PORT=$((PORT + 2)) ./build/bin/todo-api > build/smoke-wrong-root.log 2>&1 &
WRONG=$!
for _ in $(seq 50); do kill -0 $WRONG 2>/dev/null || break; sleep 0.1; done
if kill -0 $WRONG 2>/dev/null; then
  kill $WRONG 2>/dev/null
  fail=$((fail+1)); printf '  ❌ %s\n     the server started\n' "a directory for the page that was named and is not there stops the start"
else
  wait $WRONG; code=$?
  if [[ $code == 1 ]] && grep -q 'todo.webRoot must be a directory, and is not: /no/such/directory' build/smoke-wrong-root.log; then
    pass=$((pass+1)); printf '  ✅ %s\n' "a directory for the page that was named and is not there stops the start"
  else
    fail=$((fail+1)); printf '  ❌ %s\n     exit %s\n%s\n' "a directory for the page that was named and is not there stops the start" "$code" "$(sed 's/^/     /' build/smoke-wrong-root.log | head -5)"
  fi
fi

# So is a name or a password that somebody left empty: it would let in whoever sends
# nothing. However the setting came to be blank, the server says so and does not start.
refuses() { # name what-the-log-says variable=value...
  local name=$1 said=$2; shift 2
  local out code
  out=$(env "$@" PORT=$((PORT + 2)) timeout 20 ./build/bin/todo-api 2>&1); code=$?
  if [[ $code == 1 && "$out" == *"$said"* ]]; then
    pass=$((pass+1)); printf '  ✅ %s\n' "$name"
  else
    fail=$((fail+1)); printf '  ❌ %s\n     exit %s\n%s\n' "$name" "$code" "$(sed 's/^/     /' <<<"$out" | head -5)"
  fi
}
printf '{"todo":{"adminPassword":""}}' > "$ELSEWHERE/blank.json"
refuses "a password of spaces stops the start"          'todo.adminPassword is blank' GRAPEVINE_TODO_ADMINPASSWORD='   '
refuses "so does one that a config file left empty"     'todo.adminPassword is blank' GRAPEVINE_CONFIG="$ELSEWHERE/blank.json"
refuses "and a name of spaces"                          'todo.adminUser is blank'     GRAPEVINE_TODO_ADMINUSER=' '

echo
echo "Request log (from the 📝 middleware):"
sed 's/^/    /' "$LOG"
echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
