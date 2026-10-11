#!/usr/bin/env bash
# Asks the Todo sample and its ASP.NET twin the same things, and compares what they answer.
#
#   comparison/parity.sh                        starts both, asks, and stops both
#   comparison/parity.sh SAMPLE_URL TWIN_URL    asks two servers that are already running
#
# Started here, the sample is a container of the image (GRAPEVINE_IMAGE, or grapevine) and
# the twin is `dotnet run` in comparison/aspnet. Both are given the same settings from the
# same variables: a key for tokens, who issues them and for whom, a password, and an origin
# whose pages may call, as a deployment has them (GRAPEVINE_APP_ENVIRONMENT=Production).
# Two servers that are already running have to be given those too (the five variables
# below, with these values), and to be fresh: the check counts on an empty list and on
# nobody having tried to sign in. What needs servers started otherwise (the settings that
# keep either from starting, and two pairs behind proxies) is asked only when the check
# starts them itself.
#
# What is compared is what a client can rely on: the status, the kind of body, a JSON
# answer value for value, and for a refusal that it is a problem document (RFC 9457) with
# the same fields named under `errors`. The words of a refusal are compared where both
# programs choose them. Where the two are known to differ, the check says so and goes on;
# the repository's README has the list, and a difference that has gone away fails the
# check, so that the list stays true. The list is what this check asks and no proof that
# the two differ nowhere else.
set -uo pipefail
cd "$(dirname "$0")/.."

# Long enough to sign with SHA-512 too, so that a token signed that way is refused for the
# way it was signed and not for the key.
KEY='the key of the parity check, which is sixty-four bytes long and then some more'
PASSWORD='correct horse battery'
ORIGIN='https://page.example'
ISSUER='https://todo.example'
AUDIENCE='todo-page'
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
    -e GRAPEVINE_AUTH_TOKENKEY="$KEY" -e GRAPEVINE_AUTH_ISSUER="$ISSUER" -e GRAPEVINE_AUTH_AUDIENCE="$AUDIENCE" \
    -e GRAPEVINE_TODO_ADMINPASSWORD="$PASSWORD" -e GRAPEVINE_TODO_ALLOWEDORIGINS="$ORIGIN" \
    -e GRAPEVINE_APP_ENVIRONMENT=Production "${GRAPEVINE_IMAGE:-grapevine}" > /dev/null || exit 2
  started+=("container:$name")
  ( cd comparison/aspnet && PORT=18081 GRAPEVINE_AUTH_TOKENKEY="$KEY" GRAPEVINE_AUTH_ISSUER="$ISSUER" \
      GRAPEVINE_AUTH_AUDIENCE="$AUDIENCE" GRAPEVINE_TODO_ADMINPASSWORD="$PASSWORD" \
      GRAPEVINE_TODO_ALLOWEDORIGINS="$ORIGIN" GRAPEVINE_APP_ENVIRONMENT=Production \
      exec dotnet run -c Release > "$work/twin.log" 2>&1 ) &
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
    elif part == 'said':
        # What is said of each field. Asked where both programs choose the words.
        problem = value()
        errors = problem.get('errors') if isinstance(problem, dict) else None
        said.append('said: ' + '; '.join(sorted(name.lower() + ' ' + ' / '.join(told) for name, told in errors.items()))
                    if isinstance(errors, dict) else 'nothing said')
    elif part == 'detail':
        problem = value()
        said.append(str(problem.get('detail')) if isinstance(problem, dict) else '')
    elif part.startswith('is:'):
        # What both are to answer. Two that are alike by being wrong alike are not passed:
        # a status that is not this one counts as no answer, which no check lets through.
        if status != part[3:]:
            said[0] = '000 (answered ' + status + ' where ' + part[3:] + ' was to be)'
    elif part == 'challenge':
        # Why a token was refused, as WWW-Authenticate codes it. Its words are each framework's own.
        told = headers.get('www-authenticate', '')
        code = told.split('error="', 1)[1].split('"', 1)[0] if 'error="' in told else ''
        said.append('refused as ' + code if code else ('asked for a token' if told else 'no challenge'))
    elif part.startswith('unlike:'):
        # Whether a header of the answer is what the request said it should be.
        name, wanted = part[7:].split(':', 1)
        got = headers.get(name.lower())
        said.append(name + (' is not there' if got is None else ' is what was sent' if got == wanted else ' is another'))
    elif part.startswith('member:'):
        problem = value()
        said.append(part[7:] + (' is there' if isinstance(problem, dict) and part[7:] in problem else ' is not there'))
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
    elif part == 'bounds':
        # What the document says of how long a new todo's title may be.
        schemas = ((value() or {}).get('components') or {}).get('schemas') or {}
        title = ((schemas.get('NewTodo') or {}).get('properties') or {}).get('title') or {}
        said.append('a title of at most ' + str(title['maxLength']) if 'maxLength' in title else 'a title of any length')
    elif part.startswith('parameters:'):
        # The parameters the document gives a path's GET.
        operation = (((value() or {}).get('paths') or {}).get(part[11:]) or {}).get('get') or {}
        said.append('parameters: ' + ','.join(sorted(parameter.get('name', '') for parameter in operation.get('parameters') or [])))
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
letters=$(printf 'x%.0s' $(seq 200))
grapes=$(printf '🍇%.0s' $(seq 200))
printf '{"title":"%s"}' "$(printf 'x%.0s' $(seq 20000))" > "$work/large.json"

# mint ALG CLAIMS: a token signed here with the key both were given. CLAIMS is JSON that is
# laid over the claims of a token that holds, and null takes a claim out.
mint() {
  python3 - "$KEY" "$ISSUER" "$AUDIENCE" "$1" "$2" <<'PY'
import base64, hashlib, hmac, json, sys, time
key, issuer, audience, alg, more = sys.argv[1:6]
def part(value): return base64.urlsafe_b64encode(json.dumps(value, separators=(',', ':')).encode()).rstrip(b'=').decode()
now = int(time.time())
claims = {'sub': 'ada', 'iat': now, 'exp': now + 300, 'iss': issuer, 'aud': audience, 'roles': 'admin'}
claims.update(json.loads(more))
claims = {name: value for name, value in claims.items() if value is not None}
signed = part({'alg': alg, 'typ': 'JWT'}) + '.' + part(claims)
digest = {'HS256': hashlib.sha256, 'HS512': hashlib.sha512}.get(alg)
mark = hmac.new(key.encode(), signed.encode(), digest).digest() if digest else b''
print(signed + '.' + base64.urlsafe_b64encode(mark).rstrip(b'=').decode())
PY
}

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
same "a space that is no blank is a title"       json   -X POST "{B}/todos" "${json[@]}" -d '{"title":"\u00a0"}'
same "and the list has it"                       json   "{B}/todos"

echo "What is refused"
same "a todo without a title"                    problem+said -X POST "{B}/todos" "${json[@]}" -d '{"nope":1}'
same "one whose title is empty"                  problem+said -X POST "{B}/todos" "${json[@]}" -d '{"title":""}'
same "one whose title is blank"                  problem+said -X POST "{B}/todos" "${json[@]}" -d '{"title":" \t\r\n "}'
same "one whose title has 201 characters"        problem+said -X POST "{B}/todos" "${json[@]}" -d "{\"title\":\"$long\"}"
same "a change whose title is empty"             problem+said -X PUT "{B}/todos/1" "${json[@]}" -d '{"title":""}'
same "a change whose title is blank"             problem+said -X PUT "{B}/todos/1" "${json[@]}" -d '{"title":"   "}'
same "a change whose title has 201 characters"   problem+said -X PUT "{B}/todos/1" "${json[@]}" -d "{\"title\":\"$long\"}"
same "a body that is no JSON"                    status+type -X POST "{B}/todos" "${json[@]}" -d 'not json'
same "a body that is no object"                  status+type -X POST "{B}/todos" "${json[@]}" -d '[1]'
same "a title that is no text"                   status+type -X POST "{B}/todos" "${json[@]}" -d '{"title":7}'
same "a todo sent as plain text"                 status+type -X POST "{B}/todos" -H 'Content-Type: text/plain' -d '{"title":"typed wrong"}'
same "a body that is larger than a body may be"  status -X POST "{B}/todos" "${json[@]}" -d "@$work/large.json"
differs "what a refusal carries that is made before any route is chosen" \
  "The sample's server refuses such a body itself, and the app's layers never see it: no headers for a browser, no ID. ASP.NET refuses it inside its pipeline." \
  status+has:X-Content-Type-Options+has:X-Request-Id -X POST "{B}/todos" "${json[@]}" -d "@$work/large.json"
differs "a field that is wrong, as it is named under errors" \
  "The sample names a field as the request wrote it. ASP.NET names it as the C# record does, with a capital." \
  fields -X POST "{B}/todos" "${json[@]}" -d '{"nope":1}'
differs "a field of the wrong kind, under errors" \
  "The sample's binder says which field it was. ASP.NET's reader of JSON gives up on the body, and the problem names no field." \
  problem -X POST "{B}/todos" "${json[@]}" -d '{"title":7}'
differs "a filter that is neither true nor false" \
  "The sample refuses it. ASP.NET reads a value it cannot parse for a parameter that may be missing as a missing one, and answers the whole list." \
  status "{B}/todos?done=maybe"
differs "a filter in capitals" \
  "The sample takes true and false as they are written. ASP.NET takes them in any case." \
  status "{B}/todos?done=TRUE"
differs "a path in capitals" \
  "The sample's paths are matched letter for letter. ASP.NET's are matched in any case." \
  status "{B}/TODOS"
differs "an id written with a sign" \
  "The sample takes digits. ASP.NET reads the segment as it reads any number, with a sign or space before it." \
  status "{B}/todos/+1"
differs "a path with an empty segment in it" \
  "The sample passes over an empty segment, in a pattern as in a request. To ASP.NET it is another path." \
  status "{B}/todos//1"
differs "the list asked for with HEAD" \
  "The sample answers HEAD wherever it answers GET. ASP.NET answers HEAD for its files, and for a route only when the route says so." \
  status --head "{B}/todos"
differs "what may be asked of the list, asked with OPTIONS" \
  "The sample answers OPTIONS for every path, with the methods under Allow. ASP.NET has no such answer." \
  status -X OPTIONS "{B}/todos"
differs "a refusal that the framework makes itself, and what was wrong" \
  "Every problem of the sample has a detail. ASP.NET's own have a title and a status." \
  status+member:detail "{B}/nothing/here"
same "an id that is no number"                   status+type "{B}/todos/abc"
same "a todo that is not there"                  problem+detail "{B}/todos/99"
same "a change to a todo that is not there"      problem+detail -X PUT "{B}/todos/99" "${json[@]}" -d '{"done":true}'
same "a method that the list does not have"      status -X PATCH "{B}/todos"
same "a path that nothing answers"               status+type "{B}/nothing/here"
same "none of that changed the list"             json   "{B}/todos"

echo "Signing in, and the numbers"
same "the numbers ask for a token"               status+has:WWW-Authenticate "{B}/admin/stats"
same "the right password with a space after it is a wrong one, and told how to sign in" problem+detail+header:Cache-Control+has:WWW-Authenticate -X POST "{B}/login" "${json[@]}" -d "{\"user\":\"admin\",\"password\":\"$PASSWORD \"}"
same "a wrong name is told the same"             problem+detail+has:WWW-Authenticate -X POST "{B}/login" "${json[@]}" -d "{\"user\":\"root\",\"password\":\"$PASSWORD\"}"
same "a sign-in without a password is the binder's to refuse" problem+said -X POST "{B}/login" "${json[@]}" -d '{"user":"admin"}'
same "and so is one whose name is too long"      problem+said -X POST "{B}/login" "${json[@]}" -d "{\"user\":\"$long\",\"password\":\"$PASSWORD\"}"
# Four tries so far from this address, and this is the fifth, which is still looked at.
same "the right name and password are answered with a token" keys+header:Cache-Control -X POST "{B}/login" "${json[@]}" -d "{\"user\":\"admin\",\"password\":\"$PASSWORD\"}"
token() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("token",""))' "$1" 2> /dev/null; }
TOKEN_A=$(token "$work/a.body"); TOKEN_B=$(token "$work/b.body")
expires() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("expiresIn"))' "$1" 2> /dev/null; }
if [[ "$(expires "$work/a.body")" == 3600 && "$(expires "$work/b.body")" == 3600 && "$TOKEN_A" == *.*.* && "$TOKEN_B" == *.*.* ]]; then
  pass=$((pass+1)); printf '  ✅ %s\n' "each token has three parts and lasts an hour"
else
  fail=$((fail+1)); printf '  ❌ %s\n' "each token has three parts and lasts an hour"
fi
same "the token opens the numbers"               json+is:200 -H 'Authorization: Bearer {T}' "{B}/admin/stats"
same "a token that was changed does not"         status+is:401+challenge -H 'Authorization: Bearer {T}x' "{B}/admin/stats"
# Each server takes the other's token: one key, one way of signing, one issuer and one audience.
swap=$TOKEN_A; TOKEN_A=$TOKEN_B; TOKEN_B=$swap
same "each takes a token that the other issued"  json+is:200 -H 'Authorization: Bearer {T}' "{B}/admin/stats"
swap=$TOKEN_A; TOKEN_A=$TOKEN_B; TOKEN_B=$swap
# Tokens made here, with the key both were given: each a token that holds, but for one
# thing. Each check says what both are to answer, so that two refusals are not alike only
# because no token was made.
bearer() { echo "Authorization: Bearer $(mint "$1" "$2")"; }
now=$(date +%s)
ended=$(printf '{"iat":%d,"exp":%d}' $((now - 900)) $((now - 600)))
ends_as_text=$(printf '{"exp":"%d"}' $((now + 300)))
refused=status+is:401+challenge
same "a token made elsewhere with the key opens them too" status+is:200 -H "$(bearer HS256 '{}')" "{B}/admin/stats"
same "one whose roles are a list with admin in it does"  status+is:200 -H "$(bearer HS256 '{"roles":["guest","admin"]}')" "{B}/admin/stats"
same "one for several audiences, this among them, does"  status+is:200 -H "$(bearer HS256 '{"aud":["another","todo-page"]}')" "{B}/admin/stats"
same "a token of someone who is no admin will not do"    status+is:403 -H "$(bearer HS256 '{"roles":"guest"}')" "{B}/admin/stats"
same "nor one that names no role"                status+is:403 -H "$(bearer HS256 '{"roles":null}')" "{B}/admin/stats"
same "nor one that has ended"                    "$refused" -H "$(bearer HS256 "$ended")" "{B}/admin/stats"
same "nor one that never ends"                   "$refused" -H "$(bearer HS256 '{"exp":null}')" "{B}/admin/stats"
same "nor one signed another way"                "$refused" -H "$(bearer HS512 '{}')" "{B}/admin/stats"
same "nor one that says it is not signed"        "$refused" -H "$(bearer none '{}')" "{B}/admin/stats"
same "nor one from another issuer"               "$refused" -H "$(bearer HS256 '{"iss":"https://elsewhere.example"}')" "{B}/admin/stats"
same "nor one that names no issuer"              "$refused" -H "$(bearer HS256 '{"iss":null}')" "{B}/admin/stats"
same "nor one for another audience"              "$refused" -H "$(bearer HS256 '{"aud":"another"}')" "{B}/admin/stats"
differs "a token whose roles are one text of two names" \
  "The sample reads a text of names with spaces between as that many roles, as a scope is written. To ASP.NET a text is one role." \
  status -H "$(bearer HS256 '{"roles":"guest admin"}')" "{B}/admin/stats"
differs "a token whose end is written as a text" \
  "The sample takes a time that is a number, as RFC 7519 has it. ASP.NET's reader takes a text of digits too." \
  status -H "$(bearer HS256 "$ends_as_text")" "{B}/admin/stats"
differs "what a refusal for the want of a role carries" \
  "The sample's 403 says how to come again, in WWW-Authenticate. ASP.NET's carries no such header." \
  status+has:WWW-Authenticate -H "$(bearer HS256 '{"roles":"guest"}')" "{B}/admin/stats"
differs "whether a refusal for the want of a token may be kept" \
  "The sample's guard marks its refusals no-store. ASP.NET's 401 says nothing of keeping." \
  status+header:Cache-Control "{B}/admin/stats"
# The sixth try at signing in within the minute is one too many.
same "the sixth is turned away, and told when to come again" status+has:Retry-After -X POST "{B}/login" "${json[@]}" -d "{\"user\":\"admin\",\"password\":\"$PASSWORD\"}"
same "the list is not counted with them"         status "{B}/todos"

echo "The page, and what it needs"
same "the page"                                  type+bytes "{B}/"
same "its script"                                type+bytes "{B}/app.js"
same "its style sheet"                           type+bytes "{B}/style.css"
same "its icon"                                  type+bytes "{B}/favicon.svg"
same "where the page finds the API"              json+header:Cache-Control "{B}/config.json"
same "the server says it is well"                json   "{B}/health"
careful=status+header:X-Content-Type-Options+header:X-Frame-Options+header:Referrer-Policy+header:Content-Security-Policy
same "the headers that make a browser careful"   "$careful" "{B}/"
same "which an answer of the API has too"        "$careful" "{B}/todos"
same "and a refusal"                             "$careful" "{B}/todos/99"
same "every answer has an ID for its request"    status+has:X-Request-Id "{B}/todos"
same "which is not one that a client wrote"      'status+unlike:X-Request-Id:a-client-wrote-this' -H 'X-Request-Id: a-client-wrote-this' "{B}/todos"
same "a long list goes out as gzip to a client that takes it" status+header:Content-Encoding -H 'Accept-Encoding: gzip' "{B}/openapi.json"

echo "Pages on other origins"
ask=(-H "Origin: $ORIGIN" -H 'Access-Control-Request-Method: POST' -H 'Access-Control-Request-Headers: content-type')
same "a preflight from an origin that may call is answered" status+header:Access-Control-Allow-Origin+list:Access-Control-Allow-Headers+header:Access-Control-Max-Age -X OPTIONS "${ask[@]}" "{B}/todos"
same "and its POST is taken, and may be read"    status+header:Access-Control-Allow-Origin+list:Access-Control-Expose-Headers -X POST -H "Origin: $ORIGIN" "${json[@]}" -d '{"title":"from another origin"}' "{B}/todos"
same "a page elsewhere is not told that it may read" answered+header:Access-Control-Allow-Origin -H 'Origin: https://evil.example' "{B}/health"
differs "a request from an origin that may not call" \
  "The sample refuses it with a 403 before a handler runs. ASP.NET answers it and leaves the refusing to the browser, which does not hand the answer to the page, and does not send a request that needs a preflight at all." \
  status -H 'Origin: https://evil.example' "{B}/health"
differs "a preflight for a method that pages may not use" \
  "The sample refuses it with a 403. ASP.NET answers 204 with the methods that pages may use, this one not among them, which a browser reads as a refusal." \
  status -X OPTIONS -H "Origin: $ORIGIN" -H 'Access-Control-Request-Method: PATCH' "{B}/todos"

echo "What each says of itself"
same "an OpenAPI document"                       status+type "{B}/openapi.json"
differs "the paths and methods in it" \
  "ASP.NET's document leaves out its health endpoint, which is no part of what it calls the API." \
  status+paths "{B}/openapi.json"
differs "what the document says of how long a title may be" \
  "Grapevine's document has the bounds its binder holds a body to. ASP.NET's has the fields and their types, and none of the bounds its attributes hold a body to." \
  status+bounds "{B}/openapi.json"
differs "the parameters the document gives /hello" \
  "ASP.NET reads a handler's parameters off its signature, the greeting in the query among them. Grapevine's document has what a route said of itself, and this one said what it is for and no more." \
  'status+parameters:/hello/{name}' "{B}/openapi.json"

if [[ $# -eq 0 ]]; then
  echo "What keeps each from starting"
  with_key=(GRAPEVINE_AUTH_TOKENKEY="$KEY")
  with_password=(GRAPEVINE_TODO_ADMINPASSWORD="$PASSWORD")
  # alone SECONDS SETTING...: starts each program by itself with those settings and nothing
  # else, and leaves how each ended in $code_a and $code_b, where 124 is a server that was
  # still running after that many seconds, and what each said in refuse.a and refuse.b.
  alone() {
    local seconds=$1 twin envs=() setting; shift
    for setting in "$@"; do envs+=(-e "$setting"); done
    docker run --rm --platform linux/amd64 "${envs[@]}" "${GRAPEVINE_IMAGE:-grapevine}" \
      timeout "$seconds" ./build/bin/todo-api > "$work/refuse.a" 2>&1; code_a=$?
    # The twin runs here, where there may be no timeout: it is watched for as long.
    ( cd comparison/aspnet && exec env "$@" PORT=18082 dotnet run -c Release --no-build > "$work/refuse.b" 2>&1 ) &
    twin=$!; code_b=124
    for _ in $(seq $((seconds * 4))); do
      if ! kill -0 $twin 2> /dev/null; then wait $twin; code_b=$?; break; fi
      sleep 0.25
    done
    if [[ $code_b -eq 124 ]]; then pkill -P $twin 2> /dev/null; kill $twin 2> /dev/null; wait $twin 2> /dev/null; fi
  }
  # refuses NAME WORD SETTING...: neither program starts with those settings, and each says WORD
  # of why, so that the two are not alike for another reason than the one that is asked.
  refuses() {
    local name=$1 word=$2; shift 2
    alone 20 "$@"
    if [[ $code_a -ne 0 && $code_a -ne 124 && $code_b -ne 0 && $code_b -ne 124 ]] \
        && grep -q -F -- "$word" "$work/refuse.a" && grep -q -F -- "$word" "$work/refuse.b"; then
      pass=$((pass+1)); printf '  ✅ %-58s %s\n' "$name" "each names $word"
    else
      fail=$((fail+1)); printf '  ❌ %s\n     the sample ended with %s and the twin with %s, where 124 is a server that started, and each was to say "%s"\n     the sample: %s\n     the twin:   %s\n' \
        "$name" "$code_a" "$code_b" "$word" "$(grep -a -m1 -e ERROR -e rror "$work/refuse.a" | cut -c1-160)" "$(grep -a -m1 -e xception -e rror "$work/refuse.b" | cut -c1-160)"
    fi
  }
  # starts NAME SETTING...: both programs start with those settings and nothing else.
  starts() {
    local name=$1; shift
    alone 8 "$@"
    if [[ $code_a -eq 124 && $code_b -eq 124 ]]; then
      pass=$((pass+1)); printf '  ✅ %s\n' "$name"
    else
      fail=$((fail+1)); printf '  ❌ %s\n     the sample ended with %s and the twin with %s, where 124 is a server that started\n' "$name" "$code_a" "$code_b"
    fi
  }
  refuses "a key that is too short to sign with"       "too short"           "${with_password[@]}" GRAPEVINE_AUTH_TOKENKEY=short
  refuses "no key at all, in a deployment"             "auth.tokenKey"       "${with_password[@]}"
  refuses "the password of the README, in a deployment" "todo.adminPassword" "${with_key[@]}"
  refuses "a password that is blank"                   "todo.adminPassword"  "${with_key[@]}" "GRAPEVINE_TODO_ADMINPASSWORD=   "
  refuses "room for no todo at all"                    "todo.capacity"       "${with_key[@]}" "${with_password[@]}" GRAPEVINE_TODO_CAPACITY=0
  refuses "tokens that last no time"                   "auth.tokenSeconds"   "${with_key[@]}" "${with_password[@]}" GRAPEVINE_AUTH_TOKENSECONDS=0
  refuses "clocks that may be an hour apart"           "auth.leewaySeconds"  "${with_key[@]}" "${with_password[@]}" GRAPEVINE_AUTH_LEEWAYSECONDS=3600
  refuses "proxies that are neither a number nor addresses" "server.trustedProxies" "${with_key[@]}" "${with_password[@]}" GRAPEVINE_SERVER_TRUSTEDPROXIES=somewhere
  refuses "a network that is written as one of its hosts" "server.trustedProxies" "${with_key[@]}" "${with_password[@]}" GRAPEVINE_SERVER_TRUSTEDPROXIES=10.0.0.5/8
  refuses "more proxies than sixteen"                  "server.trustedProxies" "${with_key[@]}" "${with_password[@]}" GRAPEVINE_SERVER_TRUSTEDPROXIES=17
  refuses "proxies that are a comma and no more"       "server.trustedProxies" "${with_key[@]}" "${with_password[@]}" GRAPEVINE_SERVER_TRUSTEDPROXIES=,
  refuses "an environment that is neither of the two"  "app.environment"     "${with_key[@]}" "${with_password[@]}" GRAPEVINE_APP_ENVIRONMENT=Staging
  starts  "with nothing set but that it is Development" GRAPEVINE_APP_ENVIRONMENT=Development

  # behind PORT_A PORT_B PROXIES: starts another pair, each told that PROXIES are its own and
  # that they write the request's ID beside the two headers every proxy writes, makes it the
  # pair that is asked, and leaves in $up whether both answer and in $twinlog what the twin
  # wrote.
  behind() {
    local port_a=$1 port_b=$2 proxies=$3 name=grapevine-parity-$1-$$ base
    A=http://127.0.0.1:$port_a; B=http://127.0.0.1:$port_b; twinlog=$work/twin-$port_b.log
    docker run -d --rm --platform linux/amd64 --name "$name" -p "127.0.0.1:$port_a:8080" \
      -e GRAPEVINE_AUTH_TOKENKEY="$KEY" -e GRAPEVINE_TODO_ADMINPASSWORD="$PASSWORD" \
      -e GRAPEVINE_APP_ENVIRONMENT=Production -e GRAPEVINE_SERVER_TRUSTEDPROXIES="$proxies" \
      -e GRAPEVINE_SERVER_FORWARDEDHEADERS='for, proto, id' \
      "${GRAPEVINE_IMAGE:-grapevine}" > /dev/null || exit 2
    started+=("container:$name")
    ( cd comparison/aspnet && PORT=$port_b GRAPEVINE_AUTH_TOKENKEY="$KEY" GRAPEVINE_TODO_ADMINPASSWORD="$PASSWORD" \
        GRAPEVINE_APP_ENVIRONMENT=Production GRAPEVINE_SERVER_TRUSTEDPROXIES="$proxies" \
        GRAPEVINE_SERVER_FORWARDEDHEADERS='for, proto, id' \
        exec dotnet run -c Release --no-build > "$twinlog" 2>&1 ) &
    started+=("process:$!")
    up=yes
    for base in "$A" "$B"; do
      for _ in $(seq 120); do curl -s -o /dev/null "$base/todos" && break; sleep 0.5; done
      curl -s -o /dev/null "$base/todos" || up="no answer from $base"
    done
  }
  guess=(-X POST "{B}/login" "${json[@]}" -d '{"user":"admin","password":"a guess"}')

  echo "Behind proxies that are named"
  # A second pair, each told that this machine and the private networks are its proxies. The
  # check then plays the proxy: what it writes into X-Forwarded-For is who is counted.
  NETS='127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, ::1'
  behind 18083 18084 "$NETS"
  # The sample's container has to see this machine as one of those networks, which it does
  # wherever Docker reaches a container from a private address.
  if [[ $up == yes ]]; then
    asked a -H 'X-Request-Id: is-this-machine-a-proxy' "{B}/todos"
    grep -q -i '^x-request-id: is-this-machine-a-proxy' "$work/a.head" || up="the sample's container does not see this machine as one of $NETS"
  fi
  if [[ $up != yes ]]; then
    fail=$((fail+1)); printf '  ❌ the pair behind proxies could not be asked: %s\n%s\n' "$up" "$(tail -n 3 "$twinlog" 2> /dev/null | cut -c1-200)"
  else
    for try in first second third fourth fifth; do
      same "the $try try from an address that a proxy forwarded" status+is:401 "${guess[@]}" -H 'X-Forwarded-For: 203.0.113.9'
    done
    same "the sixth from that address is one too many"           status+is:429 "${guess[@]}" -H 'X-Forwarded-For: 203.0.113.9'
    same "what a client wrote in front of it is not read"        status+is:429 "${guess[@]}" -H 'X-Forwarded-For: 198.51.100.7, 203.0.113.9'
    same "another address behind the proxy is another client"    status+is:401 "${guess[@]}" -H 'X-Forwarded-For: 203.0.113.10'
    # Through a second proxy that is named, the client is the address in front of that
    # proxy's. A program that took the names for the number one would count the second
    # proxy itself, which has not tried before.
    same "passed on by a second named proxy, it is that address still" status+is:429 "${guess[@]}" -H 'X-Forwarded-For: 203.0.113.9, 10.0.0.5'
    same "and another address that it passed on is another client" status+is:401 "${guess[@]}" -H 'X-Forwarded-For: 203.0.113.12, 10.0.0.5'
    differs "the ID that a proxy wrote for a request" \
      "The sample takes a request's ID from a proxy of its own that is said to write it, and from nobody else. ASP.NET's is its own, whoever asks." \
      'status+unlike:X-Request-Id:a-proxy-wrote-this' -H 'X-Request-Id: a-proxy-wrote-this' "{B}/todos"
  fi

  echo "From an address that is none of the proxies named"
  # A third pair, whose proxies are named and are not this machine. What is written into
  # X-Forwarded-For is then a stranger's word: everyone is whoever connected, which here is
  # one address for all six. A program that believed whoever connects would see six clients.
  behind 18085 18086 '203.0.113.0/24'
  if [[ $up != yes ]]; then
    fail=$((fail+1)); printf '  ❌ the pair that this machine is no proxy of could not be asked: %s\n%s\n' "$up" "$(tail -n 3 "$twinlog" 2> /dev/null | cut -c1-200)"
  else
    stranger=0
    for try in first second third fourth fifth; do
      stranger=$((stranger + 1))
      same "the $try try, forwarded for an address of its own" status+is:401 "${guess[@]}" -H "X-Forwarded-For: 198.51.100.$stranger"
    done
    same "the sixth is one too many, whatever it was forwarded for" status+is:429 "${guess[@]}" -H 'X-Forwarded-For: 198.51.100.6'
  fi
  A=http://127.0.0.1:18080; B=http://127.0.0.1:18081
fi

# Last, since each of these leaves one list with a todo that the other does not have.
echo "Where one takes a todo and the other does not"
differs "a title of 200 characters that are not letters" \
  "The sample counts characters. ASP.NET counts the units of UTF-16, of which each of these is two." \
  status -X POST "{B}/todos" "${json[@]}" -d "{\"title\":\"$grapes\"}"
differs "a title of 200 letters with a space on each side" \
  "The sample counts once the space around a text is gone. ASP.NET counts before it takes the space off." \
  status -X POST "{B}/todos" "${json[@]}" -d "{\"title\":\" $letters \"}"
differs "a member named with a capital" \
  "The sample reads a member by its name, letter for letter. ASP.NET reads it in any case." \
  status -X POST "{B}/todos" "${json[@]}" -d '{"Title":"named with a capital"}'
differs "a member that is there twice" \
  "The sample refuses a body that names a member twice. ASP.NET takes the last of them." \
  status -X POST "{B}/todos" "${json[@]}" -d '{"title":"first","title":"second"}'

echo
echo "$pass the same, $fail not, $known known to differ"
[[ $fail -eq 0 ]]
