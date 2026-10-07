# grapevine

An HTTP/1.1 server framework for Emojicode: routes, middleware, controllers, and a
connection engine that is strict about how requests are framed. It is an Emojicode
package. The repository's [README](../../README.md) has the build instructions and the
list of Emojicode pitfalls; this file is the reference for using the package.

```
📦 grapevine 🏠

🏁 ➡️ 🔢 🍇
  🆕🍷❗️ ➡️ app
  🧱 app 📝 app❗️❗️

  📥 app 🔤/hello/:name🔤 🍇🎍🥡 r 📨 ➡️ 📬 🚧🚧
    🔤stranger🔤 ➡️ 🖍🆕name
    ↪️ 📌 r 🔤name🔤❗️ ➡️ given 🍇
      given ➡️ 🖍name
    🍉
    🆕🧾❗️ ➡️ json
    🔡 json 🔤message🔤 🆕🔡 🍿 🔤Hello, 🔤 name 🍆 🔤🔤❗️❗️
    ↩️ 🌸🐇📬 📤 json❗️❗️
  🍉❗️

  📂 app❗️
  ↩️ 🚀 app❗️
🍉
```

`📂` takes settings from a config file and the environment, `PORT` among them, and `🚀`
serves where they say: on port 8080 of every address unless told otherwise. It serves
until the process is asked to stop and returns the exit code, so `🏁` returns it.

## The app: 🍷

| Call | Meaning |
|---|---|
| `🆕🍷❗️` | A new app. |
| `📥 app path handler❗️` | GET route. `📮` is POST, `✏️` PUT, `🛠` PATCH, `🗑` DELETE. A handler is `🍇📨➡️📬🚧🚧🍉`: it returns a response or raises. |
| `🧱 app layer❗️` | Adds middleware, `🍇📨🍇📨➡️📬🍉➡️📬🚧🚧🍉`: the request and the rest of the pipeline, which never raises. Runs in the order added. |
| `🗂 app prefix❗️` | A route group. It has the same five route methods, under the prefix. |
| `🎛 app prefix controller❗️` | Registers a controller: anything that conforms to `🎛` and adds its routes to the group it is given. |
| `🚑 app mapper❗️` | Adds an error mapper, `🍇🚧 📨➡️🍬📬🍉`: the answer for an error, or no value. See [Errors and problems](#errors-and-problems). |
| `📝 app❗️` | The built-in request logger, as middleware. See [Logging](#logging). |
| `📢 app❗️` | The app's logger. |
| `🎚 app key number❗️`, `🎚🔸🔡 app key text❗️` | Set a setting. `🔧 app key❗️` and `🔧🔸🔡 app key❗️` read one. See [Settings](#settings). |
| `🌱 app key initial low high❗️`, `🌱🔸🔡 app key initial❗️` | Declare a setting of the application's own. |
| `📂 app❗️` | Lays the config file and the environment over the settings. |
| `🚀 app❗️` | Serves on `server.host` and `server.port`. Returns 0 after a clean stop and 1 when it could not start. |
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
| `🌸🔸🚩 r❗️` | What was wrong with the body the last time `🌸` read it, and where: `repeated key at byte 7`. Empty when `🌸` gave a value, and before it was asked. |
| `🌸🔸🆘 r❗️` | A 400 problem that says the body is not valid JSON, and why. For a handler to raise: `🚨 🧨 🌸🔸🆘 r❗️❗️`. |
| `🎒 r key❗️`, `🎁 r key value❗️` | A bag of text items that lives as long as the request, for middleware to pass things to handlers. |
| `🆔 r❗️` | The request's ID. See [Request IDs](#request-ids). |
| `🥩 r❗️`, `🥩🔸🛣 r❗️` | The target exactly as it was sent, and the part of it before the question mark. These are the forms to write to a log: the decoded path can hold line breaks that were sent as escapes. |
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

## Errors and problems

Every error the server reports is a problem document (RFC 9457), of the media type
`application/problem+json; charset=utf-8`:

```json
{"type":"about:blank","title":"Bad Request","status":400,"detail":"The todo is not valid","errors":{"title":["is required"]}}
```

`🆘` is one. It always has `type`, `title` and `status`; the rest is there when it was set.
Every setter returns the problem, so they chain.

| Call | Meaning |
|---|---|
| `🆕🆘 status❗️` | A problem with that status, the status's reason phrase as its title, and the type `about:blank`. |
| `📝 p detail❗️` | Sets `detail`: what went wrong this time. |
| `🔖 p title❗️`, `🏷 p uri❗️`, `📍 p uri❗️` | Set `title`, `type` and `instance`. |
| `📎 p name text❗️`, `🧩 p name value❗️` | Add a member of your own: a string, or any `💠`. The six names a problem has itself cannot be used. |
| `🚩 p field message❗️` | Adds a message under `errors[field]`. A field can have several. |
| `🚥 p❗️`, `💬 p❗️`, `📤 p❗️` | The status. The detail, or the title when there is none. The document as JSON text. |
| `📬 p❗️` | The response that carries it. |
| `🧨 p❗️` | The problem as an error to raise. |

The factories `🚫🐇📬`, `👻🐇📬`, `💥🐇📬` and `📛🐇📬` make a problem's response from a
status and a detail in one call.

**A handler fails by raising.** Its type is `🍇📨➡️📬🚧🚧🍉`: it returns a response or
raises an error. `🚧🔸🌐` is an error that carries a problem:

```
📥 group 🔤/:id🔤 🍇🎍🥡 r 📨 ➡️ 📬 🚧🚧
  ↪️ 📍 r 🔤id🔤❗️ ➡️ id 🍇
    ↪️ 🔍 store id❗️ ➡️ todo 🍇
      ↩️ 🌸🐇📬 🌸 todo❗️❗️
    🍉
    🚨 🆕🚧🔸🌐 404 🔤No todo with that id🔤❗️
  🍉
  🚨 🧨 🚩 🆕🆘 400❗️ 🔤id🔤 🔤must be an integer🔤❗️❗️
🍉❗️
```

`🆕🚧🔸🌐 status detail❗️` is the short form, `🧨 problem❗️` makes one from any problem,
and `🆘 error❗️` gives the problem back.

What becomes of an error that a handler or a layer of middleware raises:

1. **The app's mappers are asked**, in the order they were added with `🚑 app mapper❗️`.
   A mapper is `🍇🚧 📨➡️🍬📬🍉`: it is handed the error and the request, and gives a
   response or no value. The first response is the answer, and the mappers after it are
   not asked. A mapper knows its errors by casting, and the cast has to be bound to a
   variable as it is here. A cast that fails and was handed straight to a call frees the
   error while it is still in use, which is this compiler's doing and not Grapevine's:

   ```
   🚑 app 🍇🎍🥡 error 🚧 r 📨 ➡️ 🍬📬
     ↪️ 🔲 error 🚧🔸🈵 ➡️ full 🍇
       ↩️ 📛🐇📬 409 💬 full❗️❗️
     🍉
     ↩️ 🤷‍♀️
   🍉❗️
   ```

2. Otherwise **an error that carries a problem is answered with that problem**.
3. **Any other error is unexpected.** It is answered with a 500 and logged at error, with
   its message and the request's ID, method and path:
   `ERROR unhandled error: the disk is full requestId=… method=GET path=/todos`. The 500
   says `An unexpected error occurred` and nothing else, unless the setting
   `app.environment` is `Development`: then its detail is the error's message.

**An error never crosses a middleware boundary.** It becomes a response at the call that
raised, and the layers outside are handed that response like any other. So the `next` a
layer is given never raises, and middleware that wants to react to a failure looks at the
status of what `next` returned. Middleware may raise too, before or after it calls `next`,
and is answered for in the same way.

To let an error from something a handler called pass on to the mappers, catch it and raise
it again with `🔄🐇🧰`:

```
🆗 todo 🌱 store title❗️ 🍇
  ↩️ 🐣🐇📬 🌸 todo❗️❗️
🍉
🙅‍♀️ error 🍇
  🚨 🔄🐇🧰 error❗️
🍉
```

That is the whole of it, and it is needed: this compiler's `🔺` cannot be used (the
repository's README says why), and raising the caught variable itself from inside the
block makes the compiler skip releases.

A status outside 200 to 599 cannot be sent, whether a handler, a layer or a mapper
returned it or a raised problem carries it. The response is replaced by a 500 where it
arrives, so the layers outside and the request log see the status that is sent, and the
status it was is logged at error: `a response had the status 99, which cannot be sent`.

A panic is not an error and cannot be caught: it ends the process. The framework has no
`🍺` in it and is fuzzed; a handler that panics needs the supervisor.

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
`💯` and `🌡` give any number as a real: the real nearest to the number as it is
written, however many digits that is, as far as its first twenty-nine show: measured
against numbers one step away from the middle between two reals, every one of up to
twenty-nine digits is read right, and a few of thirty are not. A number too large for any
real is refused; one too small for any is zero.

The reader takes exactly what RFC 8259 defines: no comments, no trailing commas, no
leading zeros or plus signs, no control characters inside a string. It also refuses three
things the RFC allows, because each has been used against servers: an object with the
same key twice, a string with a zero character in it, and nesting deeper than
`limits.jsonDepth` (`📖🐇💠` follows 64 levels). Text that is not UTF-8, half of a
surrogate pair and a number too large for a real are refused as well.

It also stops at `limits.jsonValues` values, 100,000 unless you say otherwise, where a
value is every null, boolean, number, string, array and object in the document. The
reason is memory. While a body is held, a null takes about 150 bytes, a number or a
string 300, and an object about 1.5 kB with its first member, though `{"a":1}` is seven
bytes of body. Without the limit a 1 MB body could hold 250 MB. With it, the heaviest
body there is, objects nested one inside another, holds about 145 MB, and one of plain
records holds 60 MB. A body of bare numbers, coordinates for one, reaches 100,000 values
at well under 1 MB: raise the limit on a server that takes such bodies, and lower it on
one that has little memory to give each of its workers.

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
written in as few digits as read back as the same real, fifteen at the least and
seventeen at the most, and as null when it is not finite.

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

A setting is a whole number with a range, or a text, which may be limited to a few
values. Set one in code with `🎚 app key number❗️` or `🎚🔸🔡 app key text❗️` before `🚀`,
and read it with `🔧 app key❗️` or `🔧🔸🔡 app key❗️`.

`📂 app❗️` then lays the outside world over what the code set, each source over the one
before:

1. **A config file**: the one the environment variable `GRAPEVINE_CONFIG` names, or
   `grapevine.json` where the process runs, if there is one. It is a JSON object, and an
   object inside it stands for the keys that start with its name:
   `{"server":{"workers":8},"log":{"level":"debug"}}`. A number sets a whole-number
   setting, and a string sets a text setting or, when it is digits, a whole-number one.
2. **`PORT`**, which sets `server.port`, as hosting platforms expect.
3. **A variable for each setting**: `GRAPEVINE_`, then the key in capitals with an
   underscore for whatever is not a letter or a digit. `GRAPEVINE_SERVER_WORKERS` is
   `server.workers` and `GRAPEVINE_LIMITS_JSONDEPTH` is `limits.jsonDepth`.

So what the code sets before `📂` is a default, and what it sets afterwards wins. A
variable that is set to nothing counts as not set.

Anything wrong stops the server from starting: `🚀` logs each problem and returns 1. That
covers an unknown key, a value of the wrong kind or outside its range, a text the setting
does not allow, a config file that was named and is not there, one that cannot be read or
is over 1 MB, and one that is not a JSON object. A problem caused by a file or a variable
says which: `log.level must be one of debug, info, warn, error, off, got loud (from
GRAPEVINE_LOG_LEVEL)`. Only a missing `grapevine.json` is fine.

A variable that begins with `GRAPEVINE_` and names no setting, other than
`GRAPEVINE_CONFIG`, does not stop the server. It is warned about when the server starts:
`WARN  the variable GRAPEVINE_LIMITS_BODY_BYTES names no setting`. The variable for
`limits.bodyBytes` is `GRAPEVINE_LIMITS_BODYBYTES`, and a limit that was meant to be set
and is not should not go unsaid. It is a warning and no more because the environment is
not the application's alone: Kubernetes sets `GRAPEVINE_SERVICE_HOST`, `GRAPEVINE_PORT`
and five like them in every pod that runs beside a Service called `grapevine`, unless the
pod says `enableServiceLinks: false`. A Service called `grapevine-server` is worse: its
`GRAPEVINE_SERVER_PORT=tcp://…` is the variable of `server.port`, and a value like that
does stop the server. Declare an application's own settings before `📂`, or their
variables are warned about too.

An application declares settings of its own with `🌱 app key initial low high❗️` for a
whole number and `🌱🔸🔡 app key initial❗️` for a text, before `📂`. They are then set,
read and loaded like the ones below: `🌱 app 🔤todos.pageSize🔤 20 1 100❗️` can be set
with `GRAPEVINE_TODOS_PAGESIZE`.

| Key | Default | Range | Meaning |
|---|---|---|---|
| `app.environment` | `Production` | `Development` or `Production` | In `Development` the 500 for an unexpected error gives the error's message. See [Errors and problems](#errors-and-problems) |
| `server.host` | `0.0.0.0` | an IPv4 or IPv6 address | The address to listen on, as numbers: `127.0.0.1`, `::1`. A name such as `localhost` is not looked up, and stops the server from starting |
| `server.port` | 8080 | 1 to 65535 | |
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
| `limits.jsonValues` | 100000 | 1 to 100000000 | How many values a JSON body may hold. Each takes 150 to 1,500 bytes while the body is handled |
| `log.level` | `info` | `debug`, `info`, `warn`, `error` or `off` | The lowest level that is written |
| `log.format` | `text` | `text` or `json` | |

## Logging

`📢 app❗️` is the app's logger. Handlers and middleware capture it:

```
📢 app❗️ ➡️ log
📥 app 🔤/warm🔤 🍇🎍🥡 r 📨 ➡️ 📬 🚧🚧
  💡 log 🔤cache warmed🔤❗️
  📝 log 🔤warn🔤 🔤slow query🔤 🍿 🔤table🔤 🔤todos🔤 🔤ms🔤 🔤812🔤 🍆❗️
  ↩️ 🕳🐇📬❗️
🍉❗️
```

| Call | Meaning |
|---|---|
| `🐛 log message❗️`, `💡 log message❗️`, `⚠️ log message❗️`, `💥 log message❗️` | A line at debug, info, warn or error. |
| `📝 log level message fields❗️` | A line at a level given by name, with fields: a list of a name, its value, the next name, and so on. A level that is not one of the four is info. |
| `👀 log level❗️` | Whether a line at that level would be written. Worth asking before building a costly message. |

A line below `log.level` is not written, and at `off` none is. What stops the server from
starting is said all the same: with the log off it goes to standard error, as a bare
line. A line is the time in UTC, the level, the message and the fields, as text or, with
`log.format` set to `json`, as one JSON object:

```
2026-10-07T12:34:56.789Z WARN  slow query table=todos ms=812
{"time":"2026-10-07T12:34:56.789Z","level":"warn","message":"slow query","table":"todos","ms":"812"}
```

One call is one line, whatever is in it. In a text line a line break or any other
control character is written out as an escape and a backslash is written twice, so an
escape is only ever an escape. A value is quoted when it is empty or has a space, a
quote, an equals sign, a backslash or a control character in it, which keeps every escape
in a value inside quotes, where readers of this format expect it. A field's name keeps
letters, digits, dots, dashes and underscores. A field named `time`, `level` or `message`
is left out, and so is a second value for a name. Lines go to standard output one at a
time for the whole process, so lines from different workers stay whole however long they
are.

`📢 app❗️` sets the logger to `log.level` and `log.format` as they stand at that moment,
and `🚀` does so once more. What the server itself says goes through it: where it listens
and its routes at info, a listener that is failing at warn, why it cannot start at error,
and each request it refuses at debug, since a client can cause as many of those as it
likes.

`📝 app❗️` is the request logger, as middleware. It logs one line for each request at
info, with the method, the path as it was sent, the status, the time the rest of the
pipeline took and the request's ID, each also as a field:

```
2026-10-07T12:34:56.789Z INFO  GET /todos 200 3ms method=GET path=/todos status=200 durationMs=3 requestId=5f2b7c1e9a4d4e0b8c3a6d1f0e2b9a47
```

To send lines somewhere else, give a logger a `🗞` of your own: a class with
`❗️ 🖨 line 🔡` and `❗️ ⏰ ➡️ 🔢` (the time in milliseconds since 1970). `🆕📢 level format
sink❗️` makes the logger and `🖊🔸📢 app logger❗️` makes it the app's. Do that before asking
for the request logger, which keeps the logger there was when it was made. Several workers
call a sink's `🖨` at once, so a sink that keeps anything needs a lock of its own.

## Request IDs

Every request has an ID by the time middleware sees it, and every response that comes
out of the app carries it in `X-Request-Id`. `🆔 r❗️` gives it to a handler.

- A request that brings an `X-Request-Id` of 1 to 64 letters, digits, dots, dashes and
  underscores keeps it. Any other is ignored, and so is one that comes twice: a client
  must not be able to write text of its choosing into the logs.
- Otherwise one is made: 128 bits from the system's random source as thirty-two hex
  digits, such as `5f2b7c1e9a4d4e0b8c3a6d1f0e2b9a47`. One does not tell the next, so a
  client cannot send an ID ahead of the request that will be given it, and two servers do
  not make the same one. It names a request and is not a secret.
- If the handler puts an `X-Request-Id` of its own on the response, the request's
  replaces it.
- What the server refuses before there is a request (see below) has no ID.

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

A connection that never sends anything is closed without an answer. A response from the
application with a status outside 200 to 599 is answered with 500.

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
- **Logs** go to standard output unbuffered and one line at a time, so they appear as
  they happen and lines from different workers stay whole. See [Logging](#logging).
  What a handler prints with `😀` goes through the C library instead: it is buffered when
  output is not a terminal (start the server with `stdbuf -oL` to see it promptly) and can
  be cut into by another thread's line. Log through `📢 app❗️`.
- **Where it listens.** `server.host` and `server.port`, which is `0.0.0.0:8080` unless
  the settings, `PORT` or `GRAPEVINE_SERVER_PORT` say otherwise. When it cannot listen
  there the line that says so gives the system's reason: `cannot start: could not listen
  on 0.0.0.0:80: Permission denied`.

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
- A JSON body is held as values while it is handled, 150 to 1,500 bytes for each one
  however little text it came from. With the usual `limits.jsonValues` that is 145 MB for
  a request at the very worst, and every worker can be holding as much at the same
  moment. See [JSON](#json).
- Nothing the engine does leaks: the `grapevine/leaks` suite and the fuzzer both measure
  the process for growth.
- The compiler misplaces releases in several patterns, and a server finds every one of
  them. If you write handlers, read "Memory leaks the compiler writes for you" in the
  repository README and run `tests/lint.sh` over your code.
- `📓` has no way to take a name out again yet.
