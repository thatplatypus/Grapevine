#!/usr/bin/env bash
# Asks the Todo sample and its ASP.NET twin the same things, and compares what they answer.
#
#   comparison/parity.sh                        starts both, asks, and stops both
#   comparison/parity.sh SAMPLE_URL TWIN_URL    asks two servers that are already running
#
# Started here, the sample is a container of the image (GRAPEVINE_IMAGE, or grapevine) and
# the twin is `dotnet run` in comparison/aspnet. Both are given the same settings from the
# same variables: a key for tokens, a password, and an origin whose pages may call. Two
# servers that are already running have to be given those too, and to be fresh: the check
# counts on an empty list and on nobody having tried to sign in.
#
# What is compared is what a client can rely on: the status, the kind of body, a JSON
# answer value for value, and for a refusal that it is a problem document (RFC 9457) with
# the same fields named under `errors`. The words of a refusal are compared only where
# both programs choose them. Where the two are known to differ, the check says so and
# goes on; the repository's README has the list, and a difference that has gone away
# fails the check, so that the list stays true.
set -uo pipefail
cd "$(dirname "$0")/.."

KEY='the key of the parity check: 32 bytes and more'
PASSWORD='correct horse battery'
ORIGIN='https://page.example'
work=$(mktemp -d)
started=()
cleanup() {
  for what in "${started[@]:-}"; do
    case "$what" in
      container:*) docker rm -f "${what#container:}" > /dev/null 2>&1 ;;
      process:*) kill "${what#process:}" 2> /dev/null ;;
    esac
  done
  rm -rf "$work"
}
trap cleanup EXIT

if [[ $# -eq 2 ]]; then
  A=${1%/}; B=${2%/}
elif [[ $# -eq 0 ]]; then
  A=http://127.0.0.1:18080; B=http://127.0.0.1:18081
  name=grapevine-parity-$$
  docker run -d --rm --platform linux/amd64 --name "$name" -p 127.0.0.1:18080:8080 \
    -e GRAPEVINE_AUTH_TOKENKEY="$KEY" -e GRAPEVINE_TODO_ADMINPASSWORD="$PASSWORD" \
    -e GRAPEVINE_TODO_ALLOWEDORIGINS="$ORIGIN" "${GRAPEVINE_IMAGE:-grapevine}" > /dev/null || exit 2
  started+=("container:$name")
  ( cd comparison/aspnet && PORT=18081 GRAPEVINE_AUTH_TOKENKEY="$KEY" GRAPEVINE_TODO_ADMINPASSWORD="$PASSWORD" \
      GRAPEVINE_TODO_ALLOWEDORIGINS="$ORIGIN" exec dotnet run -c Release > "$work/twin.log" 2>&1 ) &
  started+=("process:$!")
  for base in "$A" "$B"; do
    for _ in $(seq 240); do curl -s -o /dev/null "$base/todos" && break; sleep 0.5; done
    curl -s -o /dev/null "$base/todos" || { echo "no answer from $base"; cat "$work/twin.log" 2> /dev/null | tail -20; exit 2; }
  done
else
  sed -n '2,6p' "$0"; exit 2
fi

cat > "$work/project.py" <<'PY'
import hashlib, json, sys
kind, prefix = sys.argv[1], sys.argv[2]
head = open(prefix + '.head', 'rb').read().decode('latin-1')
body = open(prefix + '.body', 'rb').read()
blocks = [block for block in head.split('\r\n\r\n') if block.strip()]
lines = blocks[-1].split('\r\n') if blocks else ['HTTP/1.1 000 none']
status = (lines[0].split(' ') + ['000'])[1]
headers = {}
for line in lines[1:]:
    if ':' in line:
        name, value = line.split(':', 1)
        headers.setdefault(name.strip().lower(), value.strip())
media = headers.get('content-type', '').split(';')[0].strip()


def value():
    try:
        return json.loads(body.decode('utf-8'))
    except Exception:
        return None


said = [status]
for part in kind.split('+'):
    if part == 'answered':
        # Whatever the status: that there was an answer is all that is asked.
        said[0] = 'answered' if status != '000' else status
    elif part == 'type':
        said.append(media)
    elif part == 'json':
        said.append(json.dumps(value(), sort_keys=True, ensure_ascii=False))
    elif part == 'problem':
        problem = value()
        whole = isinstance(problem, dict) and all(name in problem for name in ('type', 'title', 'status'))
        said.append(media)
        said.append('a problem' if whole and str(problem['status']) == status else 'no problem document')
        # Which fields are wrong, whatever case their names are written in: that the two
        # write them differently is one difference, and is asked about once, below.
        errors = problem.get('errors') if isinstance(problem, dict) else None
        said.append('errors: ' + ','.join(sorted(name.lower() for name in errors)) if isinstance(errors, dict) else 'no errors')
    elif part == 'fields':
        problem = value()
        errors = problem.get('errors') if isinstance(problem, dict) else None
        said.append('errors: ' + ','.join(sorted(errors)) if isinstance(errors, dict) else 'no errors')
    elif part == 'detail':
        problem = value()
        said.append(str(problem.get('detail')) if isinstance(problem, dict) else '')
    elif part == 'bytes':
        said.append(hashlib.sha256(body).hexdigest()[:16] + ' of ' + str(len(body)) + ' bytes')
    elif part == 'keys':
        answer = value()
        said.append(','.join(sorted(answer)) if isinstance(answer, dict) else 'no object')
    elif part == 'paths':
        document = value() or {}
        said.append(' | '.join(sorted(
            method.upper() + ' ' + path
            for path, item in (document.get('paths') or {}).items()
            for method in item if method in ('get', 'post', 'put', 'patch', 'delete'))))
    elif part.startswith('header:'):
        said.append(part[7:] + ': ' + headers.get(part[7:].lower(), '(none)'))
    elif part.startswith('list:'):
        # A header that is a list: the same list, however its commas are spaced.
        items = [item.strip() for item in headers.get(part[5:].lower(), '(none)').split(',')]
        said.append(part[5:] + ': ' + ', '.join(items))
    elif part.startswith('has:'):
        said.append(part[4:] + (' is there' if part[4:].lower() in headers else ' is not there'))
print(' ; '.join(said))
PY

pass=0; fail=0; known=0
TOKEN_A=; TOKEN_B=

# asked SIDE CURL-ARGS...: one request to one side. {B} is that side's address and {T} its token.
asked() {
  local side=$1 base token args=() arg
  shift
  if [[ $side == a ]]; then base=$A; token=$TOKEN_A; else base=$B; token=$TOKEN_B; fi
  for arg in "$@"; do arg=${arg//\{B\}/$base}; args+=("${arg//\{T\}/$token}"); done
  curl -s -D "$work/$side.head" -o "$work/$side.body" "${args[@]}" || true
}

both() { # KIND CURL-ARGS...: asks both, and leaves what each said in $said_a and $said_b
  local kind=$1; shift
  asked a "$@"; asked b "$@"
  said_a=$(python3 "$work/project.py" "$kind" "$work/a")
  said_b=$(python3 "$work/project.py" "$kind" "$work/b")
}

same() { # NAME KIND CURL-ARGS...
  local name=$1 kind=$2; shift 2
  both "$kind" "$@"
  if [[ "$said_a" == "$said_b" && "$said_a" != 000* ]]; then
    pass=$((pass+1)); printf '  ✅ %-58s %s\n' "$name" "${said_a:0:60}"
  else
    fail=$((fail+1)); printf '  ❌ %s\n     the sample: %s\n     the twin:   %s\n' "$name" "$said_a" "$said_b"
  fi
}

differs() { # NAME WHY KIND CURL-ARGS...: a difference that the README names
  local name=$1 why=$2 kind=$3; shift 3
  both "$kind" "$@"
  if [[ "$said_a" != "$said_b" ]]; then
    known=$((known+1)); printf '  ≠  %s\n     the sample: %s\n     the twin:   %s\n     %s\n' "$name" "$said_a" "$said_b" "$why"
  else
    fail=$((fail+1)); printf '  ❌ %s\n     both say: %s\n     which the README lists as a difference: take it off the list\n' "$name" "$said_a"
  fi
}

json=(-H 'Content-Type: application/json')
long=$(printf 'x%.0s' $(seq 201))

echo "The list"
same "the list is empty"                         json   "{B}/todos"
same "a todo is made"                            json+header:Location -X POST "{B}/todos" "${json[@]}" -d '{"title":"Ship it"}'
same "its title is kept without the space around it" json -X POST "{B}/todos" "${json[@]}" -d '{"title":"  Port Hermes  "}'
same "one todo"                                  json   "{B}/todos/1"
same "a todo is changed"                         json   -X PUT "{B}/todos/1" "${json[@]}" -d '{"done":true}'
same "and renamed"                               json   -X PUT "{B}/todos/2" "${json[@]}" -d '{"title":"Port Hermes to 🍇"}'
same "a change of nothing changes nothing"       json   -X PUT "{B}/todos/1" "${json[@]}" -d '{}'
same "the whole list"                            json   "{B}/todos"
same "the todos that are done"                   json   "{B}/todos?done=true"
same "and those that are not"                    json   "{B}/todos?done=false"
same "a todo is deleted"                         status -X DELETE "{B}/todos/2"
same "and is not there to delete again"          problem -X DELETE "{B}/todos/2"

echo "What is refused"
same "a todo without a title"                    problem -X POST "{B}/todos" "${json[@]}" -d '{"nope":1}'
same "one whose title is blank"                  problem -X POST "{B}/todos" "${json[@]}" -d '{"title":"   "}'
same "one whose title has 201 characters"        problem -X POST "{B}/todos" "${json[@]}" -d "{\"title\":\"$long\"}"
same "a change whose title has 201 characters"   problem -X PUT "{B}/todos/1" "${json[@]}" -d "{\"title\":\"$long\"}"
same "a body that is no JSON"                    status+type -X POST "{B}/todos" "${json[@]}" -d 'not json'
same "a body that is no object"                  status+type -X POST "{B}/todos" "${json[@]}" -d '[1]'
same "a title that is no text"                   status+type -X POST "{B}/todos" "${json[@]}" -d '{"title":7}'
same "a todo sent as plain text"                 status+type -X POST "{B}/todos" -H 'Content-Type: text/plain' -d '{"title":"typed wrong"}'
differs "a field that is wrong, as it is named under errors" \
  "The sample names a field as the request wrote it. ASP.NET names it as the C# record does, with a capital." \
  fields -X POST "{B}/todos" "${json[@]}" -d '{"nope":1}'
differs "a filter that is neither true nor false" \
  "The sample refuses it. ASP.NET reads a value it cannot parse for a parameter that may be missing as a missing one, and answers the whole list." \
  status "{B}/todos?done=maybe"
same "an id that is no number"                   status+type "{B}/todos/abc"
same "a todo that is not there"                  problem+detail "{B}/todos/99"
same "a change to a todo that is not there"      problem+detail -X PUT "{B}/todos/99" "${json[@]}" -d '{"done":true}'
same "a method that the list does not have"      status -X PATCH "{B}/todos"
same "a path that nothing answers"               status+type "{B}/nothing/here"
same "none of that changed the list"             json   "{B}/todos"

echo "Signing in, and the numbers"
same "the numbers ask for a token"               status+has:WWW-Authenticate "{B}/admin/stats"
same "a wrong password is refused"               problem+detail+header:Cache-Control -X POST "{B}/login" "${json[@]}" -d '{"user":"admin","password":"a guess"}'
same "a wrong name is told the same"             problem+detail -X POST "{B}/login" "${json[@]}" -d "{\"user\":\"root\",\"password\":\"$PASSWORD\"}"
same "a sign-in without a password is the binder's to refuse" problem -X POST "{B}/login" "${json[@]}" -d '{"user":"admin"}'
same "the right name and password are answered with a token" keys+header:Cache-Control -X POST "{B}/login" "${json[@]}" -d "{\"user\":\"admin\",\"password\":\"$PASSWORD\"}"
token() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("token",""))' "$1" 2> /dev/null; }
TOKEN_A=$(token "$work/a.body"); TOKEN_B=$(token "$work/b.body")
expires() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("expiresIn"))' "$1" 2> /dev/null; }
if [[ "$(expires "$work/a.body")" == 3600 && "$(expires "$work/b.body")" == 3600 && "$TOKEN_A" == *.*.* && "$TOKEN_B" == *.*.* ]]; then
  pass=$((pass+1)); printf '  ✅ %s\n' "each token has three parts and lasts an hour"
else
  fail=$((fail+1)); printf '  ❌ %s\n' "each token has three parts and lasts an hour"
fi
same "the token opens the numbers"               json   -H 'Authorization: Bearer {T}' "{B}/admin/stats"
same "a token that was changed does not"         status+has:WWW-Authenticate -H 'Authorization: Bearer {T}x' "{B}/admin/stats"
# A token that holds and says its bearer is a guest, signed here with the key both were given.
guest=$(python3 - "$KEY" <<'PY'
import base64, hashlib, hmac, json, sys, time
def part(value): return base64.urlsafe_b64encode(json.dumps(value, separators=(',', ':')).encode()).rstrip(b'=').decode()
now = int(time.time())
signed = part({'alg': 'HS256', 'typ': 'JWT'}) + '.' + part({'sub': 'ada', 'iat': now, 'exp': now + 300, 'roles': 'guest'})
mark = hmac.new(sys.argv[1].encode(), signed.encode(), hashlib.sha256).digest()
print(signed + '.' + base64.urlsafe_b64encode(mark).rstrip(b'=').decode())
PY
)
same "a token of someone who is no admin will not do" status -H "Authorization: Bearer $guest" "{B}/admin/stats"
# Each server takes the other's token: one key, one way of signing.
swap=$TOKEN_A; TOKEN_A=$TOKEN_B; TOKEN_B=$swap
same "each takes a token that the other issued"  json   -H 'Authorization: Bearer {T}' "{B}/admin/stats"
swap=$TOKEN_A; TOKEN_A=$TOKEN_B; TOKEN_B=$swap
# Four tries so far from this address. One more, and the sixth within the minute is one too many.
same "the fifth try is still looked at"          status -X POST "{B}/login" "${json[@]}" -d '{"user":"admin","password":"a guess"}'
same "the sixth is turned away, and told when to come again" status+has:Retry-After -X POST "{B}/login" "${json[@]}" -d "{\"user\":\"admin\",\"password\":\"$PASSWORD\"}"
same "the list is not counted with them"         status "{B}/todos"

echo "The page, and what it needs"
same "the page"                                  type+bytes "{B}/"
same "its script"                                type+bytes "{B}/app.js"
same "its style sheet"                           type+bytes "{B}/style.css"
same "its icon"                                  type+bytes "{B}/favicon.svg"
same "where the page finds the API"              json+header:Cache-Control "{B}/config.json"
same "the server says it is well"                json   "{B}/health"
same "the headers that make a browser careful"   status+header:X-Content-Type-Options+header:X-Frame-Options+header:Referrer-Policy+header:Content-Security-Policy "{B}/"
same "every answer has an ID for its request"    status+has:X-Request-Id "{B}/todos"
same "a long list goes out as gzip to a client that takes it" status+header:Content-Encoding -H 'Accept-Encoding: gzip' "{B}/openapi.json"

echo "Pages on other origins"
ask=(-H "Origin: $ORIGIN" -H 'Access-Control-Request-Method: POST' -H 'Access-Control-Request-Headers: content-type')
same "a preflight from an origin that may call is answered" status+header:Access-Control-Allow-Origin+list:Access-Control-Allow-Headers+header:Access-Control-Max-Age -X OPTIONS "${ask[@]}" "{B}/todos"
same "and its POST is taken, and may be read"    status+header:Access-Control-Allow-Origin+list:Access-Control-Expose-Headers -X POST -H "Origin: $ORIGIN" "${json[@]}" -d '{"title":"from another origin"}' "{B}/todos"
same "a page elsewhere is not told that it may read" answered+header:Access-Control-Allow-Origin -H 'Origin: https://evil.example' "{B}/health"
differs "a request from an origin that may not call" \
  "The sample refuses it with a 403 before a handler runs. ASP.NET answers it and leaves the refusing to the browser, which does not hand the answer to the page, and does not send a request that needs a preflight at all." \
  status -H 'Origin: https://evil.example' "{B}/health"

echo "What each says of itself"
same "an OpenAPI document"                       status+type "{B}/openapi.json"
differs "the paths and methods in it" \
  "ASP.NET's document leaves out its health endpoint, which is no part of what it calls the API." \
  status+paths "{B}/openapi.json"

if [[ $# -eq 0 ]]; then
  echo "What keeps each from starting"
  # refuses NAME VARIABLE=VALUE: neither program starts with that setting.
  refuses() {
    local name=$1 setting=$2 code_a code_b=124 twin
    docker run --rm --platform linux/amd64 -e "$setting" "${GRAPEVINE_IMAGE:-grapevine}" timeout 20 ./build/bin/todo-api > /dev/null 2>&1; code_a=$?
    # The twin runs here, where there may be no timeout: it is given thirty seconds to end by itself.
    ( cd comparison/aspnet && exec env "$setting" PORT=18082 dotnet run -c Release --no-build > /dev/null 2>&1 ) &
    twin=$!
    for _ in $(seq 120); do
      if ! kill -0 $twin 2> /dev/null; then wait $twin; code_b=$?; break; fi
      sleep 0.25
    done
    if [[ $code_b -eq 124 ]]; then kill $twin 2> /dev/null; wait $twin 2> /dev/null; fi
    if [[ $code_a -ne 0 && $code_a -ne 124 && $code_b -ne 0 && $code_b -ne 124 ]]; then
      pass=$((pass+1)); printf '  ✅ %s\n' "$name"
    else
      fail=$((fail+1)); printf '  ❌ %s\n     the sample ended with %s and the twin with %s, where 124 is a server that started\n' "$name" "$code_a" "$code_b"
    fi
  }
  refuses "a key that is too short to sign with"  GRAPEVINE_AUTH_TOKENKEY=short
  refuses "a password that is blank"              "GRAPEVINE_TODO_ADMINPASSWORD=   "
  refuses "room for no todo at all"               GRAPEVINE_TODO_CAPACITY=0
fi

echo
echo "$pass the same, $fail not, $known known to differ"
[[ $fail -eq 0 ]]
