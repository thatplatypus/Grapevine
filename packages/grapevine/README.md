# grapevine

An HTTP/1.1 server framework for Emojicode: routes, middleware, controllers, and a
connection engine that is strict about how requests are framed. It is an Emojicode
package. The repository's [README](../../README.md) has the build instructions and the
list of Emojicode pitfalls; this file is the reference for using the package.

```
📦 grapevine 🏠

🏁 ➡️ 🔢 🍇
  🆕🍷❗️ ➡️ app
  🧱 app 📝🐇🍷❗️❗️

  📥 app 🔤/hello/:name🔤 🍇🎍🥡 r 📨 ➡️ 📬
    🔤stranger🔤 ➡️ 🖍🆕name
    ↪️ 📌 r 🔤name🔤❗️ ➡️ given 🍇
      given ➡️ 🖍name
    🍉
    🆕🧾❗️ ➡️ json
    🔡 json 🔤message🔤 🆕🔡 🍿 🔤Hello, 🔤 name 🍆 🔤🔤❗️❗️
    ↩️ 🌸🐇📬 📤 json❗️❗️
  🍉❗️

  ↩️ 🚀 app 8080❗️
🍉
```

`🚀` serves until the process is asked to stop and returns the exit code, so `🏁`
returns it.

## The app: 🍷

| Call | Meaning |
|---|---|
| `🆕🍷❗️` | A new app. |
| `📥 app path handler❗️` | GET route. `📮` is POST, `✏️` PUT, `🛠` PATCH, `🗑` DELETE. A handler is `🍇📨➡️📬🍉`. |
| `🧱 app layer❗️` | Adds middleware, `🍇📨🍇📨➡️📬🍉➡️📬🍉`: the request and the rest of the pipeline. Runs in the order added. |
| `🗂 app prefix❗️` | A route group. It has the same five route methods, under the prefix. |
| `🎛 app prefix controller❗️` | Registers a controller: anything that conforms to `🎛` and adds its routes to the group it is given. |
| `📝🐇🍷❗️` | The built-in request logger, as middleware. |
| `🎚 app key value❗️` | Sets a setting. See [Settings](#settings). |
| `🚀 app port❗️` | Serves on the port. Returns 0 after a clean stop and 1 when it could not start. |
| `🛑 app❗️` | Asks the server to stop, as SIGTERM does. |
| `🧪 app request❗️` | Runs one request through middleware and routing in memory and returns the response. |

Route patterns are literal segments and `:name` parameters. The first route registered
that matches wins. Empty segments are ignored, so `/a//b/` routes like `/a/b`.

The router answers by itself where no handler can:

- **HEAD** uses the GET route when there is no HEAD route. The handler runs, the body is
  dropped, and `Content-Length` keeps the length the body had.
- **OPTIONS** on a path that has routes is 204 with an `Allow` header. `OPTIONS *` lists
  every supported method.
- A path that has routes, but none for the method, is **405** with `Allow`.
- Anything else is **404**.

These come at the end of the pipeline, so middleware sees them and can answer first.

## The request: 📨

| Call | Meaning |
|---|---|
| `🚦 r❗️` | The method, exactly as sent. Methods are case-sensitive. |
| `🛣 r❗️` | The decoded path, without the query. |
| `📌 r name❗️` | A `:name` route parameter, or no value. `📍` gives it as an integer. |
| `🔎 r name❗️` | The first query value for a name, or no value. |
| `🔭 r name❗️` | Every query value for a name, in order. |
| `🗝 r❗️` | The distinct query names, in the order first seen. |
| `🏷 r name❗️` | A header by case-insensitive name. Repeats are joined with `, ` (`; ` for `cookie`). |
| `📚 r name❗️` | Every value of a header, in the order received. |
| `🐙 r❗️` | The distinct header names, lower-cased. |
| `📇 r❗️` | The body as bytes. |
| `📄 r❗️` | The body as text. Empty when the body is not valid UTF-8. |
| `🌸 r❗️` | The body read as JSON: a `💠`, or no value when the body is not JSON. See [JSON](#json). |
| `🎒 r key❗️`, `🎁 r key value❗️` | A bag of text items that lives as long as the request, for middleware to pass things to handlers. |
| `🧬 r❗️` | The HTTP version, `1.1` or `1.0`. |
| `🌐 r❗️` | The peer's address. Behind a proxy this is the proxy. |

To build a request for a test: `🆕📨 🔤POST🔤 🔤/todos?x=1🔤❗️`, then `🔖 r name value❗️`
or `📎 r name value❗️` for headers and `📃 r text❗️` or `💾 r data❗️` for the body.

Paths are decoded one segment at a time, after `.` and `..` have been resolved, so an
encoded slash or dot can never change which route matches. In a query `+` is a space; in a
path it is a plus sign.

## The response: 📬

| Call | Status | Body |
|---|---|---|
| `✅🐇📬 text❗️` | 200 | `text/plain` |
| `🌸🐇📬 json❗️` | 200 | `application/json`, from text that is already JSON |
| `🐣🐇📬 json❗️` | 201 | `application/json` |
| `🕳🐇📬❗️` | 204 | none |
| `🚫🐇📬 message❗️` | 400 | a problem document |
| `👻🐇📬 message❗️` | 404 | a problem document |
| `💥🐇📬 message❗️` | 500 | a problem document |
| `📛🐇📬 code message❗️` | any | a problem document |
| `📦🐇📬 data contentType❗️` | 200 | bytes of any kind |
| `🌊🐇📬 contentType producer❗️` | 200 | streamed: see below |
| `🆕📬 code body contentType❗️` | any | text |

On a response, `🔖 response name value❗️` sets a header and `📎 response name value❗️`
adds a value to one (use it for `Set-Cookie`). Both return the response, so they chain:
`↩️ 🔖 ✅🐇📬 🔤ok🔤❗️ 🔤Cache-Control🔤 🔤no-store🔤❗️`. `🚥`, `🏷`, `📚`, `📄` and `📇`
read a response back, which is what tests use.

A header whose name is not a valid token is dropped, and CR, LF and zero bytes are removed
from header values, so input that reaches a header cannot split the response.
`Content-Length`, `Transfer-Encoding`, `Connection` and `Date` belong to the server; a
handler's values for them are discarded.

A streamed response is given a producer, which writes chunks to a `🚿`:

```
↩️ 🌊🐇📬 🔤text/plain; charset=utf-8🔤 🍇🎍🥡 writer 🚿
  🔂 line lines 🍇
    💬 writer line❗️
  🍉
🍉❗️
```

`💬 writer text❗️` and `📇 writer data❗️` return 👎 once the client has gone; later writes
do nothing, and the producer should stop. An HTTP/1.1 client gets chunked encoding. An
HTTP/1.0 client gets the bytes and then the end of the connection.

## JSON

A `💠` is a JSON value: null, a boolean, a number, a string, an array or an object.
`🌸 r❗️` reads a request's body into one and `📖🐇💠 text❗️` reads any text. Both give no
value when what they are given is not JSON.

```
↪️ 🌸 r❗️ ➡️ body 🍇
  🏷 body 🔤title🔤❗️       💭 the member "title" when it is a string, else no value
  ☑️ body 🔤done🔤❗️        💭 the member "done" when it is a boolean
🍉
```

| Call | Meaning |
|---|---|
| `🏷 value key❗️`, `📍 value key❗️`, `🌡 value key❗️`, `☑️ value key❗️` | A member of an object, when it is a string, an integer, a number of any kind (as a real) or a boolean. No value when the member is missing or is something else. |
| `📚 value key❗️` | The items of a member that is an array. |
| `🐽 value key❗️` | A member, whatever it is. |
| `👀 value key❗️`, `🐙 value❗️` | Whether an object has a member, and its keys in the order they were written. |
| `🔡 value❗️`, `🔢 value❗️`, `💯 value❗️`, `👌 value❗️` | The value itself, when it is a string, an integer, a number or a boolean. |
| `🍨 value❗️` | The items of an array. |
| `🕳 value❗️`, `🍯 value❗️` | Whether the value is null. Whether it is an object. |

An integer is a number written without a fraction or an exponent that fits in 64 bits.
`💯` and `🌡` give any number as a real.

The reader takes exactly what RFC 8259 defines: no comments, no trailing commas, no
leading zeros or plus signs, no control characters inside a string. It also refuses three
things the RFC allows, because each has been used against servers: an object with the
same key twice, a string with a zero character in it, and nesting deeper than
`limits.jsonDepth` (`📖🐇💠` follows 64 levels). Text that is not UTF-8, half of a
surrogate pair and a number too large for a real are refused as well.

It also stops at `limits.jsonValues` values, 100,000 unless you say otherwise, where a
value is every null, boolean, number, string, array and object in the document. The
reason is memory. While a body is held, a null takes about 150 bytes, a number or a
string 300, and an object with one member 1.8 kB, though `{"a":1}` is seven bytes of
body. Without the limit a 1 MB body could hold 230 MB. With it the worst a body can do
is about 90 MB, and one of plain records of 100,000 values holds 60 MB. A body of bare
numbers, coordinates for one, reaches 100,000 values at well under 1 MB: raise the limit
on a server that takes such bodies, and lower it on one that has little memory.

To build a value, start from `🍯🐇💠❗️`, an empty object, or `🍨🐇💠❗️`, an empty array, and
add to it with `🔖 object key value❗️` or `🐻 array value❗️`. The other kinds come from
`🔡🐇💠 text❗️`, `🔢🐇💠 number❗️`, `💯🐇💠 real❗️`, `👌🐇💠 flag❗️` and `🕳🐇💠❗️`.
`📤 value❗️` is the JSON text, which is what `🌸🐇📬` takes:

```
🍯🐇💠❗️ ➡️ todo
🔖 todo 🔤title🔤 🔡🐇💠 🔤Ship it🔤❗️❗️
↩️ 🌸🐇📬 📤 todo❗️❗️
```

A number that was read is written back as it was written. A real that was made here is
written with up to fifteen significant digits, and as null when it is not finite.

For a flat object `🧾` is shorter: `🔡 json key text❗️`, `🔢 json key number❗️`,
`💯 json key real❗️`, `👌 json key flag❗️`, `🕳 json key❗️` for null, `💠 json key value❗️`
for a value built as above, `🧩 json key rawJson❗️`, then `📤 json❗️`. `📚🐇🧾 items❗️`
joins values that are already JSON into an array, and `🧼🐇🧾 text❗️` quotes and escapes
a string.

## Text under names: 📓

The standard library's dictionary leaks (the repository README says how), so the framework
has one of its own for strings. Route parameters and the request's bag are kept in one, and
a handler that needs a dictionary can use it too.

| Call | Meaning |
|---|---|
| `🆕📓❗️` | Empty notes. |
| `value ➡️ 🐽notes name❗️` | Puts text under a name, in place of whatever was there. |
| `🐽 notes name❗️` | The text under a name, or no value. |
| `🐣 notes name❗️` | Whether anything is under a name. |
| `📏 notes❓` | How many names there are. |
| `🐙 notes❗️` | The names, in the order they were first set. |

A lookup takes the same time however many names there are. Beyond eight names it goes
through an index hashed with SipHash-1-3, under a key drawn at random when the process
starts, so a client that gets to choose the names cannot choose ones that slow it down.

## Settings

Set them with `🎚 app key value❗️` before `🚀`. An unknown key, or a value outside its
range, stops the server from starting: `🚀` prints each problem and returns 1.

| Key | Default | Range | Meaning |
|---|---|---|---|
| `server.workers` | 64 | 1 to 1024 | Worker threads. Also the most connections served at once |
| `server.backlog` | 128 | 1 to 4096 | Connections the kernel queues while every worker is busy |
| `server.maxRequestsPerConnection` | 100 | 0 to 1000000 | 0 means no limit |
| `server.keepAliveTimeoutMs` | 5000 | 0 to 600000 | How long an idle connection is kept. 0 turns keep-alive off |
| `server.headerTimeoutMs` | 10000 | 100 to 600000 | For the whole request head |
| `server.bodyTimeoutMs` | 30000 | 100 to 3600000 | For the whole request body |
| `server.writeTimeoutMs` | 30000 | 100 to 3600000 | The longest a client may go without taking any bytes of a response |
| `server.shutdownGraceMs` | 10000 | 0 to 600000 | How long a stop waits for requests in progress |
| `limits.requestLineBytes` | 8192 | 256 to 65536 | |
| `limits.headerBytes` | 32768 | 1024 to 1048576 | The request line, the headers, and any blank lines before them. Also the limit for trailers |
| `limits.headerCount` | 100 | 1 to 1000 | |
| `limits.bodyBytes` | 1048576 | 0 to 1073741824 | Bodies are held in memory |
| `limits.jsonDepth` | 64 | 1 to 1024 | How deeply the arrays and objects of a JSON body may nest |
| `limits.jsonValues` | 100000 | 1 to 100000000 | How many values a JSON body may hold. Each takes 150 to 900 bytes while the body is handled |

## What the server answers by itself

Each of these is a problem document, and each closes the connection.

| When | Status |
|---|---|
| Malformed request line, method or target; a header that is not `name: value`; a bare CR or LF anywhere; a control character or bytes that are not UTF-8 in a header value | 400 |
| An HTTP/1.1 request without `Host`; more than one `Host`; a `Host`, or the authority of an absolute target, that is not a name or address with an optional port | 400 |
| `Content-Length` together with `Transfer-Encoding`; lengths that disagree or are not numbers; a malformed chunk | 400 |
| A percent-escape that is not two hex digits, or decodes to a zero byte or to bytes that are not UTF-8; a path that climbs above the root | 400 |
| The client went quiet in the middle of a request | 408 |
| A body larger than `limits.bodyBytes` | 413 |
| A request line longer than `limits.requestLineBytes` | 414 |
| An `Expect` other than `100-continue` | 417 |
| A head larger than `limits.headerBytes`, or more headers than `limits.headerCount` | 431 |
| A method that is not GET, HEAD, POST, PUT, PATCH, DELETE or OPTIONS; a transfer coding other than `chunked` | 501 |
| A version other than HTTP/1.0 or HTTP/1.1 | 505 |

A connection that never sends anything is closed without an answer. A handler that
returns a status outside 200 to 599 is answered with 500.

Requests are framed the way RFC 9112 requires, including the cases that let a request be
smuggled past a proxy: a message with both `Content-Length` and `Transfer-Encoding`,
differing lengths, and line endings that are not CRLF are refused, never repaired.

## Running it

- **Connections.** Each of the `server.workers` threads serves one connection at a time.
  Keep-alive and pipelining are supported. When every worker is busy and a client is
  waiting, a connection that is idle or has just been answered is closed to make room:
  one connection for one waiting client.
- **Stopping.** SIGTERM, SIGINT or `🛑 app❗️` stops the server gracefully: it stops
  accepting, closes idle connections at once, lets requests in hand finish with
  `Connection: close`, and `🚀` returns 0. A request is in hand from its first byte
  until its response has been written. If any is still in hand after
  `server.shutdownGraceMs`, the process exits with 1 instead. A second signal exits
  with 1 at once.
- **Give the orchestrator longer than the grace period.** `docker stop` and Kubernetes
  send SIGKILL after their own timeout. If that is shorter than
  `server.shutdownGraceMs`, requests in progress are cut off: use `docker stop -t`,
  `--stop-timeout` or `terminationGracePeriodSeconds`.
- **Run it under a supervisor.** A panic cannot be caught in Emojicode and ends the
  process. The framework itself never panics on input, and is fuzzed to check that, but
  a handler can.
- **Put a reverse proxy in front.** There is no TLS and no HTTP/2.
- **Logs** go to standard output, each line in a single unbuffered write, so they appear
  as they happen and lines from different workers stay whole. What a handler prints with
  `😀` goes through the C library instead: it is buffered when output is not a terminal
  (start the server with `stdbuf -oL` to see it promptly) and can be cut into by another
  thread's line.

## Threads

- Routes, middleware and settings are set up before `🚀`. After that they are only read.
- Handlers and middleware run on worker threads, several at once. Anything they share
  must be guarded with a 🔐. The sample's `🏪` store shows the pattern: every method
  locks, and what it hands out is immutable.
- A `📨` and its `📬` belong to one request and need no locking.

## Testing an app

`🧪` runs a request through the app without a socket:

```
🆕📨 🔤POST🔤 🔤/todos🔤❗️ ➡️ request
📃 request 🔤{"title":"Ship it"}🔤❗️
🧪 app request❗️ ➡️ response
🚥 response❗️     💭 201
📄 response❗️     💭 the body
```

`🎞` goes one level lower: real request bytes in, every byte the server wrote out. It
runs the same connection code as a socket does, on an in-memory transport with a clock
that jumps forward instead of waiting, so timeouts can be tested in no time at all.

```
🆕🎞 app❗️ ➡️ tape
✂️ tape 1❗️          💭 deliver the request one byte at a time
⏳ tape❗️            💭 then go silent, so that timeouts fire, instead of closing
🎬 tape 📇 🔤GET / HTTP/1.1❌r❌nHost: x❌r❌n❌r❌n🔤❗️❗️    💭 the response bytes
⏱ tape❗️            💭 milliseconds that passed on the tape's clock
```

## Limits

- No TLS, no HTTP/2, no WebSockets.
- Request and response bodies are held in memory, except responses built with `🌊`.
- A JSON body is held as values while it is handled, 150 to 900 bytes for each one however
  little text it came from. With the usual `limits.jsonValues` that is 90 MB for a request
  at the very worst, and every worker can be holding as much at the same moment. See
  [JSON](#json).
- Nothing the engine does leaks: the `grapevine/leaks` suite and the fuzzer both measure
  the process for growth.
- The compiler misplaces releases in several patterns, and a server finds every one of
  them. If you write handlers, read "Memory leaks the compiler writes for you" in the
  repository README and run `tests/lint.sh` over your code.
- `📓` has no way to take a name out again yet.
