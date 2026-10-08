# 🍇 Grapevine

An ASP.NET / NestJS-style HTTP framework written in [Emojicode](https://www.emojicode.org),
plus a Todo API built on it and the same API in ASP.NET Core for comparison.

It exists to answer one question: **what does a real, non-toy codebase look like in
Emojicode, and what does it cost in tokens compared to C#?** Answer so far: about
3.4× the tokens for the same app (see [Token comparison](#token-comparison)).

The framework is being built out into a serious one, phase by phase. The server core is
done: a worker pool, keep-alive, timeouts, graceful shutdown and strict HTTP/1.1 framing.
So are a JSON reader of its own, configuration from a file and the environment, leveled
logging, request IDs, and errors: handlers raise, and every failure the server reports is
an RFC 9457 problem document. Routes are matched by how specific they are, and a binder
reads and checks what a handler was sent.
[`packages/grapevine/README.md`](packages/grapevine/README.md) is its reference, and the
[roadmap](docs/superpowers/specs/2026-10-06-buildout-roadmap.md) says what comes next.

```
2026-10-07T12:34:56.001Z INFO  Grapevine listening on http://0.0.0.0:8080 workers=64
2026-10-07T12:34:56.001Z INFO  route GET /todos
2026-10-07T12:34:56.001Z INFO  route POST /todos
...
2026-10-07T12:35:02.417Z INFO  POST /todos 201 0ms method=POST path=/todos status=201 durationMs=0 requestId=5f2b7c1e9a4d4e0b8c3a6d1f0e2b9a47
2026-10-07T12:35:02.431Z INFO  GET /todos/1 200 0ms method=GET path=/todos/1 status=200 durationMs=0 requestId=0c9e1d4a7b3f48e2a15d6c8b9f7e2d30
```

## What's in the framework

| Grapevine | ASP.NET / Nest equivalent |
|---|---|
| `🍷` app: `📥 📮 ✏️ 🛠 🗑` for GET/POST/PUT/PATCH/DELETE | `WebApplication`, `MapGet`… |
| `🧱` middleware `(request, next) ➡️ response` | `app.Use(...)` |
| `🗂` route groups | `MapGroup` / `@Controller('/path')` |
| `🎛` controller protocol, constructor-injected services | controllers / Nest providers |
| `:id` route params, `📍` int params, `🔎` query, `🏷` case-insensitive headers, each as an optional or, with a fallback, as a plain value | route values, `[FromQuery]`, headers |
| patterns with `:id:int`, an optional `:name?` and a catch-all `*rest`; the most specific route wins, whatever the order of registration | route constraints, optional and catch-all parameters, route precedence |
| the route is matched before middleware runs; `🔖` puts notes on routes and groups, and middleware reads them with `🏷🔸🛤` | endpoint routing, endpoint metadata |
| `🌸` JSON body → `💠` value, read strictly (no repeated keys, limits on depth and size), and only from a request that says it is JSON, with a 415 for any other; `🧾` JSON writer | `System.Text.Json`, `[Consumes]` |
| `📋` the fields of a form, plain or in parts, and `📁` the files of one, each a `📎` with its name, type and bytes | `Request.Form`, `IFormFile`, `[FromForm]` |
| `🎯` the one of several media types that the client's `Accept` likes best, or none, for a 406 | output formatters, `[Produces]`, `ReturnHttpNotAcceptable` |
| `🧷` binder: typed, checked values from the body, the query, the route, a form, the cookies and the headers, and one 400 that lists everything wrong by field | model binding, `[FromBody]` `[FromQuery]` `[FromRoute]` `[FromForm]` `[FromHeader]`, data annotations |
| `✅ 🌸 🐣 🕳 🚫 👻 💥 📛` result factories | `Results.Ok/Json/Created/NoContent/BadRequest/NotFound/Problem` |
| `🆘` problem documents (RFC 9457) with `errors` by field; `🚧🔸🌐`, an error that carries one, for a handler to raise | `ProblemDetails`, `ValidationProblemDetails`, `BadHttpRequestException` |
| `🚑` error mappers: an application's own errors become responses; anything unmapped is a logged 500 that says more only when `app.environment` is `Development` | `IExceptionHandler`, `UseExceptionHandler`, the developer exception page |
| `🔀` redirects, with a form that only goes to a path on this site | `Results.Redirect`, `Results.LocalRedirect` |
| `🍪` cookies: read by name, set with `Path`, `Max-Age`, `Secure`, `HttpOnly`, `SameSite`, any text as a value | `Request.Cookies`, `Response.Cookies.Append`, `CookieOptions` |
| `♻️ 🔏` validators: `ETag` from the body, `If-None-Match` and `If-Modified-Since`, 304 | `entityTag` and `lastModified` on `Results.Bytes`, `Results.File` and `Results.Stream` |
| `💾` a response as a download, with its name | `Results.File(…, fileDownloadName)` |
| `📁` a file as a response: media type by extension, sent in pieces, `Range` and 206, `ETag` and 304; a form that looks for a client's name under a directory and nowhere else | `Results.File`, `PhysicalFileProvider` |
| `🗃` a directory of static files under a prefix: index files, `Cache-Control`, hidden names kept hidden, links out of it not followed | `UseStaticFiles`, `MapStaticAssets` |
| `🛂` a CORS policy as middleware: origins, methods, headers and credentials that are allowed, preflights answered, and a request from any other origin refused before its handler runs | `AddCors`, `UseCors` (which lets the request run and leaves the refusing to the browser) |
| `🛡` security headers on every answer: `nosniff`, no framing, no referrer, and HSTS and a content security policy when asked for | `UseHsts`; the others by hand or with a package |
| `server.trustedProxies` and `server.forwardedHeaders`: behind proxies of its own the server knows the client's address (`🌐`), the origin it used (`🏠`) and the prefix a proxy took off (`🛣🔸🧱`), from those of the `X-Forwarded-` headers that it was told the proxies write, and believes none of them otherwise | `UseForwardedHeaders`, `ForwardedHeaders`, `KnownProxies`, `ForwardLimit` |
| `🚰` a rate limit as middleware: so many requests a window for each client, or for whatever a closure counts by, and a 429 with `Retry-After` beyond | `AddRateLimiter`, `AddFixedWindowLimiter`, `UseRateLimiter` |
| `🤐` gzip for answers that are text, to clients that take it, with `Vary` and a weakened `ETag`, from a compressor written in Emojicode ([`packages/deflate`](packages/deflate/README.md)) | `AddResponseCompression`, `UseResponseCompression` |
| `💓` a health endpoint with checks, which says `stopping` once the server was asked to stop, and `server.shutdownDelayMs` to go on answering until that has been noticed | `AddHealthChecks`, `MapHealthChecks`, `IHostApplicationLifetime` |
| `🦎` what an answer varies by | `Response.Headers.Vary` |
| `🎒 / 🎁` per-request items bag | `HttpContext.Items` |
| `🧪` in-memory dispatch, no socket | `TestServer` / `WebApplicationFactory` |
| `📊` what a request left allocated, for an application's own leak tests | none; `dotnet-counters`, or a memory profiler |
| `🎞` in-memory wire session: real request bytes in, real response bytes out | none; `TestServer` skips the wire |
| automatic HEAD and OPTIONS, `Allow` on 405, 501 for unknown methods | same |
| `📦` byte bodies, `🌊` streamed responses: chunked, or with `Content-Length` when the length is known | `Results.Bytes`, `Results.Stream` |
| repeated headers: `📚` every value, `📎` append | `StringValues`, `Headers.Append` |
| strict HTTP/1.1 parsing: chunked bodies, `Expect: 100-continue`, keep-alive, pipelining, request-smuggling defences | Kestrel |
| `🎚` settings for limits and timeouts; `📂` loads them from `grapevine.json`, `PORT` and `GRAPEVINE_*` variables; `🌱` declares an application's own | `KestrelServerLimits`, `appsettings.json`, `IConfiguration` |
| `📢` logger: levels, fields, text or JSON lines; `📝 app` request logger | `ILogger`, request logging middleware |
| `X-Request-Id` on every response, `🆔` on the request | `TraceIdentifier` |
| automatic 400, 404, 405, 408, 413, 414, 417, 431, 501 and 505, each a problem document | same |
| a pool of worker threads, keep-alive, pipelining, idle connections shed under load | Kestrel |
| graceful stop on SIGTERM, with a grace period and an exit code | `IHostApplicationLifetime` |

A route and a middleware look like this:

```
📥 app 🔤/hello/:name🔤 🍇🎍🥡 r 📨 ➡️ 📬 🚧🚧
  🆕🧾❗️ ➡️ json
  🔡 json 🔤message🔤 🆕🔡 🍿 🔤Hello, 🔤 📌 r 🔤name🔤 🔤stranger🔤❗️ 🔤!🔤 🍆 🔤🔤❗️❗️
  ↩️ 🌸🐇📬 📤 json❗️❗️
🍉❗️

🧱 app 🍇🎍🥡 r 📨 next 🍇📨➡️📬🍉 ➡️ 📬 🚧🚧
  ↩️ 🔖 ⁉️ next r❗️ 🔤X-Powered-By🔤 🔤Grapevine🔤❗️
🍉❗️
```

## Layout

```
packages/
  shared/               source that packages include with 📜; not a package itself
    bytes.🍇              🧳 byte buffer, 🧮 bounds-checked reads, UTF-8 validation, keyed hash
    check.🍇              🔬 assertion helper for test programs
    tests/                unit tests for the two files above
  crypto/               hashing and signing (an Emojicode package): SHA-256, HMAC, base64url
    README.md             what each call is checked against, and what the package is not for
    build.sh              builds the package: libcrypto.a and its interface 🏛
    crypto.🍇             🖋 the digest, the signature, the comparison and the encodings
    tests/                unit tests, and a comparison with sha256sum, openssl and perl
  deflate/              a compressor (an Emojicode package): bytes in, a gzip stream out
    README.md             what a stream is made of, what it gives and what it costs
    build.sh              builds the package: libdeflate.a and its interface 🏛
    deflate.🍇            🎈 the compressor and the checksum
    tests/                unit tests, and a round trip of every fixture through the system's gzip
  grapevine/            the framework (an Emojicode package), which imports deflate
    README.md             the package's API, settings and limits
    build.sh              builds the package: libgrapevine.a and its interface 🏛
    grapevine.🍇          package entry + overview docs
    app.🍇               🍷 app, middleware pipeline, in-memory dispatch
    router.🍇             🧭 route table, 🛤 routes and their patterns, 🗂 route groups, 🎛 controller protocol
    request.🍇            📨 the request: target, query, headers, body
    response.🍇           📬 responses, result factories, 🚿 stream writer
    problem.🍇            🆘 problem documents, 🚧🔸🌐 the error that carries one
    rescue.🍇             🚑 what becomes of an error: mappers, the problem, or a logged 500
    binder.🍇             🧷 typed, checked values from the body, the query, the route, a form, cookies and headers
    form.🍇               📎 a file from a form, and the reader of forms, plain and in parts, behind 📋 and 📁
    accept.🍇             what a client accepts, behind 🎯
    parser.🍇             🧐 byte-level request parser, 🍰 chunked decoder
    connection.🍇         ☎️ per-connection loop, 🎞 in-memory wire session
    transport.🍇          🚇 transport protocol and its in-memory implementation
    net.🍇                🔩 bindings to the socket shim, 🔌 the transport over a socket
    native/net.cpp        the shim: sockets, poll, signals, the clock, random bits, log lines, files, in C++
    server.🍇             🚉 worker pool, saturation shedding, graceful stop
    json.🍇               🧾 JSON writer
    number.🍇             📐 exact conversion between a number's digits and a real
    sources.🍇            🧺 settings from the config file and the environment
    log.🍇                📢 the logger, 🗞 where its lines go
    value.🍇              💠 a JSON value: read it, ask it, build it, write it
    reader.🍇             🗜 the strict JSON reader behind 💠 and 🌸
    util.🍇               🧰 string helpers, percent-decoding, 📅 HTTP dates
    headers.🍇            🗄 ordered, multi-valued header collection
    cookie.🍇             🍪 a cookie to set, and how a request's cookies are read
    files.🍇              📁 a file as a response, ranges, media types, a client's name kept under a directory
    static.🍇             🗃 a directory of static files to mount under a prefix
    cors.🍇               🛂 a CORS policy, and what its middleware does with a request
    forwarded.🍇          what proxies forward of a request, and how much of it is believed
    limit.🍇              🚰 a rate limit, its table and its middleware
    compress.🍇           🤐 which answers go out as gzip, and the middleware that sends them so
    shield.🍇             🛡 security headers for every answer
    health.🍇             💓 what the health endpoint answers
    gauge.🍇              📊 for tests: what the program has allocated, and what a request left behind
    map.🍇                🗝 names and their places, 📓 text under names (no stock dictionary)
    settings.🍇           🎚 integer settings with defaults and ranges
    tests/unit/           white-box unit tests, including a suite that measures leaks
    tests/fuzz/           mutation fuzzer for the HTTP engine
    tests/host/           diagnostic app the tests talk to, and wire-host, which serves it
samples/
  todo/                 the Todo sample: an API, and a page that uses it
    main.🍇               entry point: settings, then the pipeline, then 🚀
    startup.🍇            builds the app; shared by main and tests (like Program.cs)
    todos.🍇              model, store, 📒 controller
    tests.🍇              in-memory tests through 🧪, and every route weighed for leaks
    web/                  the page: HTML, CSS and one script, with no build step
tests/
  lint.sh, lint.pl      reject the constructs that leak, crash or corrupt memory
  smoke.sh              end-to-end test of the sample over real HTTP with curl
  lines.sh              every log line whole, with sixteen clients and a slowly read pipe
  numbers.sh            200,000 numbers read and 100,000 written, against Python (optional)
  wire/                 wire-level tests against containers: C#, xUnit, Shouldly, Testcontainers
  e2e/                  the sample's page in a headless browser: the same, with Playwright
build.sh              builds every package and links every program
test-wire.sh          builds the image and runs the wire tests
test-e2e.sh           builds the image and runs the browser tests
build/                everything generated (ignored by git)
comparison/
  aspnet/               the same API as an ASP.NET Core minimal API
  tokens.py             token counts for both
```

## Build and run

Emojicode 1.0 beta 2 is the last release (2023) and ships **x86_64 binaries only**.

**Docker (most reliable, works on Apple Silicon via emulation):**

```sh
docker build -t grapevine .
docker run --rm -p 8080:8080 grapevine          # serve the Todo sample: open http://localhost:8080/
docker run --rm grapevine ./build.sh test       # every suite that needs no network
```

What is served is the [Todo sample](samples/todo/README.md): its API, and a page that
uses it.

`./build.sh test` runs the lint, the unit tests for `packages/shared`, `packages/crypto`,
`packages/deflate` and `packages/grapevine`, a comparison of the crypto package's digests and
signatures with the system's own tools, a round trip of the compressor's streams through the
system's `gzip`,
100,000 fuzz cases against the HTTP engine and as many against the JSON reader, the sample's
in-memory tests, the curl smoke test, and a check that log lines stay whole under load. It
needs no network.

The wire tests drive containers of the image over real sockets: timeouts, more clients than
workers, SIGTERM, a soak, settings from the environment and from a file, log lines and request
IDs. They run on the host and need Docker and the .NET 10 SDK:

```sh
./test-wire.sh
```

The browser tests open the sample's page in a headless Chromium, against containers of the
image: on the API's own origin, on another origin that the API allows, and on one that it does
not. They need Docker and the .NET 10 SDK as well, and the first run downloads Chromium for
Playwright:

```sh
./test-e2e.sh
```

`tests/numbers.sh` checks how numbers are read and written against Python, bit for bit, on far
more cases than the unit tests hold. It needs Python 3 on the host and is not part of either of
the above.

The server listens on port 8080 unless `PORT` or `GRAPEVINE_SERVER_PORT` says otherwise, and
takes every other setting the same way: `docker run --rm -p 8080:8080 -e GRAPEVINE_LOG_FORMAT=json
grapevine`. The package README lists the settings.

**Linux x86_64:** install the
[release](https://github.com/emojicode/emojicode/releases/tag/v1.0-beta.2) (it needs
`libtinfo5`; on Ubuntu 24.04 grab `libtinfo5_6.3-2_amd64.deb` from the jammy pool), then:

```sh
./build.sh test
PORT=8080 ./build/bin/todo-api
```

**macOS:** there's a `Darwin-x86_64` release that should run under Rosetta. Untested on
Apple Silicon: the compiler shells out to `c++` to link, and that has to produce
x86_64 objects too. If it fights you, use Docker.

The ASP.NET twin:

```sh
cd comparison/aspnet && PORT=8081 dotnet run
```

Try either one:

```sh
curl -X POST localhost:8080/todos -H 'content-type: application/json' -d '{"title":"Ship it"}'
curl localhost:8080/todos
curl -H 'x-api-key: vineyard' localhost:8080/admin/stats
```

## Token comparison

These numbers were measured before the build-out began and describe the original, much
smaller framework. They are refreshed when the build-out is complete.

`python3 comparison/tokens.py` (needs `pip install "anthropic==0.38.0" tokenizers`, which
bundles the legacy Claude tokenizer; current models use a newer vocabulary, so the ratio
matters more than the absolute numbers). Comments stripped:

|  | lines | bytes | tokens |
|---|---:|---:|---:|
| Grapevine app (Emojicode) | 213 | 7,197 | 3,423 |
| ASP.NET minimal API (C#) | 90 | 3,349 | 1,014 |
| **ratio** | 2.4× | 2.1× | **3.4×** |

Plus 566 lines / 8,847 tokens for the framework itself, which ASP.NET ships in the box.

Why it's bigger:

- **The syntax itself: most of the gap.** `🍇 🍉 ❗️ ➡️ ↩️ ↪️` are 3 tokens each, where
  `{ } return if =>` are 1. Every call ends in `❗️`, every block is `🍇…🍉`, and every
  optional needs an explicit `↪️ … ➡️ x 🍇 … 🍉` unwrap where C# writes `is { } x`.
- **Missing language features.** No properties, records, or reflection-based JSON, so the
  Todo model needs hand-written getters and a serializer, and bodies are cast field by
  field. That's about 450 tokens (model + body helpers) of the ~2,400-token gap.
- **No method overloading**, so related methods need distinct emoji names (`📌` string param
  vs `📍` int param).

## Emojicode gotchas found along the way

- **`🔧` (trim) corrupts a trailing multi-byte character.** `"Port Hermes to 🍇"` comes back
  as `"Port Hermes to \xF0"`. Grapevine uses its own byte-safe `🧽🐇🧰` instead.
- **Compiler assertion crash** when binding an optional `⚪️` and then casting it
  (`↪️ 🐽 dict key❗️ ➡️ v 🍇 ↩️ 🔲 v 🔡 🍉`). Casting the optional directly works:
  `🔲 🐽 dict key❗️ 🔡`.
- **Package link order.** The compiler links every imported package, including ones that only
  another package imports, but it can put a dependency before the package that needs it, and with
  static archives that fails with undefined references. `build.sh` therefore compiles each program
  to an object and links it itself, with all package archives in one group, so a program imports
  only the packages it uses directly.
- **Reserved emoji:** `🍱` (bento) and `🔗` have special meaning and can't be type or method
  names; `🩹` is too new for the compiler's emoji table.
- **`❌` is the string escape character**, so a literal ❌ is written `❌❌`.
- Closures stored for later need `🎍🥡` to be escaping.
- **`📪` and `📫` (lower and upper case) overflow their buffer** for letters whose other case
  needs more bytes, such as Ⱥ. Grapevine folds case with its own ASCII-only `📪🐇🧮`.
- **`🔡 data❗️` does not validate UTF-8**, whatever its documentation says. Grapevine converts
  bytes to text through `🔡🐇🧮`, which does.
- **Interpolating `🐽 list index❗️` directly in a string literal miscompiles** and crashes at run
  time. Bind the element to a variable first.
- The compiler's emoji table predates Unicode 12, so newer emoji cannot be used as names.
- **A 🧵 must be joined (`🛂`) before its last reference is dropped.** Otherwise the process
  aborts when the thread finishes. The server keeps its workers in a list and joins them all.
- **The mutex's try-lock (`🔐 mutex❗️`) returns garbage**: its native side returns nothing.
  Only `🔒` and `🔓` are used.
- **The list's `🐼` (remove last) does not check for an empty list.** Check the count first.
- **Every comparison with a real that is not a number is true**, equality too: the compiler
  emits unordered comparisons. `x 🙌 0.0` holds for a NaN, and a loop that waits for a comparison
  to turn false never ends on one. What is not finite is found by taking the real from itself and
  asking whether the result is both below and above zero.
- **The lowest integer cannot be turned into text.** `🔡 n 10❗️` gives twenty bytes of memory it
  never wrote to for -9223372036854775808. Grapevine writes integers with `🔡🐇🧰`.
- **A range counts down when its end is before its start.** `🆕⏩ 5 3❗️` is 5 and 4, so a loop
  over `🆕⏩ 0 count❗️` runs when the count is negative.
- **A real cannot be written with an exponent.** `2.5e21` is read as 2.5 and a variable named
  e21. Write the digits out.
- **`📣` is taken by the compiler** and cannot name anything. The logger is `📢`.
- **An override may not keep a parameter that the method it overrides only uses.** Where
  implementations must be free to keep what they are given, use a protocol.
- **The compiler aborts on a fresh object of a class it has not looked at yet**, with
  `MFFlowCategory::isEscaping(): Assertion '!isUnknown()' failed`, when that object is
  handed straight to something that only borrows it: `📤 🆕🆘 404❗️❗️` in a file included
  before 🆘's. Assign the object to a variable first.
- **There is no safe way to pass an error on.** `🔺` corrupts memory (see below), so a call
  that may raise is handled where it is made, with `🆗 value … 🙅‍♀️ error`, and an error that
  should travel is raised again as a call's result: `🚨 🔄🐇🧰 error❗️`. Grapevine turns an
  error into a response at the call that raised it, so middleware never has to.

### Memory leaks the compiler writes for you

Emojicode counts references, and the 1.0 beta 2 compiler puts some of the releases in the wrong
place. A long-running server finds every one of them. `tests/lint.sh` rejects these patterns in
the shapes it knows (its own tests, `tests/lint-cases`, show which), and the `grapevine/leaks`
suite counts what the engine leaves allocated; the roadmap has the compiler source references.
The last five in this list do not leak. They crash.

- **String interpolation leaks** the text of every value it inserts. Join a list instead:
  `🆕🔡 🍿 a b 🍆 🔤🔤❗️`.
- **`↩️` directly inside a ☣️ block or a plain `🙅 🍇` block releases nothing**, so every local
  that holds an object leaks. Write an else that returns as `🙅↪️ 👍 🍇`, and hand a value out of a
  ☣️ block before returning it.
- **A variable declared directly inside a plain `🙅 🍇` block is never released.**
- **Returning a local variable from the middle of a function** stops the compiler releasing
  other variables for the rest of that function. A local is only returned by the last statement;
  earlier exits return a literal or a call.
- **`🆕🍨🐚🔡🍆❗️ ➡️ 🖍list` over an existing list leaks the old one.** Empty it with 🐗.
- **The standard library's 🔪 and ➕ on 📇 and 🔫 on 🔡 leak on every call.** Grapevine uses
  `🔪🐇🧮`, 🧳 and `🔫🐇🧮`.
- **The standard library's dictionary leaks an entry whenever two keys share a bucket.** Its
  hash is seeded at random when the process starts, so the same program leaks in one run and
  not in the next. Grapevine keeps strings under names in a `📓` of its own, and so can a
  handler.
- **A value from the stock JSON parser cannot be cast to a dictionary and then released**: that
  is a double free, and the one shape that avoids it leaks the whole value. The parser has no
  depth limit either, so a body of 200,000 `[` ends the process. Grapevine reads JSON with a
  reader of its own.
- **A call wrapped in 🔺, or handled by a 🆗 that binds no value, corrupts memory.** The
  compiler does not see what such a call does with its arguments and may put an object that the
  call keeps on the stack. Handle an error where the call is made, with `🆗 value … 🙅‍♀️ error`.
- **Returning a parameter, or a variable a closure captured, frees it while it is in use.** The
  function gives away a reference it does not own. Assign it to a variable and return that.
- **A method that ends in `↩️ 👇` hands back an object that may be on its caller's stack.** The
  compiler takes such a method to have only borrowed its object, so a fresh object it is called
  on (`📝 🆕🆘 404❗️ text❗️`) is built in the caller's frame, and the result is that object: gone
  when the caller returns it. A setter that chains writes `👇 ➡️ same` and returns `same`, which
  tells the compiler the object leaves. Every setter of 📬 and 🆘 does.
- **A variable declared without a value after a `🆗 … 🙅‍♀️` is assigned as if it already
  held an object.** The handler's value and its error share a slot, and the compiler goes on
  believing the slot is filled once the handler is over. `🖍🆕 later 🔡` further down the
  same function can land in it, and the first assignment then frees whatever is on the
  stack. Declare the variable before the `🆗`, or with a value.
- **A cast that fails frees its object unless the cast was bound to a variable.**
  `↪️ 🔲 error 🚧🔸🈵 ➡️ full 🍇` is right. `👀 🔲 error 🚧🔸🈵❗️`, with the cast handed
  straight to a call, releases an error that nobody retained. Error mappers cast for a
  living, so this is the one to remember.

## Limits

No TLS: run it behind a reverse proxy. Bodies are held in memory, 1 MB by default
(`limits.bodyBytes`). A panic cannot be caught in Emojicode and ends the process, so run it
under a supervisor that restarts it.

A JSON body is held as values while it is handled, 150 to 1,500 bytes for each, which is far
more than the text it came from. `limits.jsonValues` (100,000) bounds it, at 145 MB for the
heaviest body there is; the package README has the numbers. What the engine does is measured
to be leak-free, by a suite that counts what stays allocated and by the fuzzers.
