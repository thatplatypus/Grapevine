# 🍇 Grapevine

An ASP.NET / NestJS-style HTTP framework written in [Emojicode](https://www.emojicode.org),
plus a Todo API built on it and the same API in ASP.NET Core for comparison.

It exists to answer one question: **what does a real, non-toy codebase look like in
Emojicode, and what does it cost in tokens compared to C#?** The answer: about 1.9× the
tokens for the same app (see [Token comparison](#token-comparison)).

The framework was built out, phase by phase, into one that does what an HTTP framework
is expected to do: a worker pool, keep-alive, timeouts, graceful shutdown and strict
HTTP/1.1 framing; a JSON reader of its own; configuration from a file and the
environment; leveled logging and request IDs; errors as RFC 9457 problem documents;
routes matched by how specific they are; a binder that reads and checks what a handler
was sent; forms, cookies, files and static directories; CORS, security headers, rate
limits, compression and what a proxy forwards; signed tokens and a guard; and a
description of an API as OpenAPI, written from what the routes say of themselves.
[`packages/grapevine/README.md`](packages/grapevine/README.md) is its reference.

```
2026-10-07T12:34:56.001Z INFO  Grapevine listening on http://0.0.0.0:8080 environment=Production workers=64
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
| `🎖` signed tokens (JSON Web Tokens, HS256), issued and checked with a key from `auth.tokenKey`, on the Emojicode [`packages/crypto`](packages/crypto/README.md); `🛃` a guard as middleware: who may call a route, by a note on it (`anyone`, `signed-in`, `role:NAME`, `scope:NAME`), with the 401 and the 403 of RFC 6750 | `AddAuthentication().AddJwtBearer`, `AddAuthorization`, `RequireAuthorization`, `[Authorize(Roles = …)]` |
| `🧬` a shape: what a body, a query or an answer is made of, said once. The binder checks a request by its route's shape, and `📖` serves the app's description of itself as an OpenAPI 3.1 document: paths, parameters, schemas, answers and who may call | `AddOpenApi`, `MapOpenApi`, `Produces`, data annotations on a record |
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
  shared/               source that is not a package itself
    bytes.🍇              🧳 byte buffer, 🧮 bounds-checked reads, UTF-8 validation, keyed hash: the copy to edit
    check.🍇              🔬 assertion helper for test programs
    tests/                unit tests for the two files above
  crypto/               hashing and signing (an Emojicode package): SHA-256, HMAC, base64url
    README.md             what each call is checked against, and what the package is not for
    packmoji.json         what Packmoji is told of the package: its name, its version, what it needs
    build.sh              builds the package: libcrypto.a and its interface 🏛
    crypto.🍇             🖋 the digest, the signature, the comparison and the encodings
    bytes.🍇              its copy of shared/bytes.🍇: a release of a package is its own folder and no more
    LICENSE               its copy of the license at the root
    tests/                unit tests, and a comparison with sha256sum, openssl and perl
  deflate/              a compressor (an Emojicode package): bytes in, a gzip stream out
    README.md             what a stream is made of, what it gives and what it costs
    packmoji.json         what Packmoji is told of the package: its name, its version, what it needs
    build.sh              builds the package: libdeflate.a and its interface 🏛
    deflate.🍇            🎈 the compressor and the checksum
    bytes.🍇              its copy of shared/bytes.🍇
    LICENSE               its copy of the license at the root
    tests/                unit tests, and a round trip of every fixture through the system's gzip
  grapevine/            the framework (an Emojicode package), which imports deflate
    README.md             the package's API, settings and limits
    packmoji.json         what Packmoji is told of the package: its name, its version, what it needs
    build.sh              builds the package: libgrapevine.a and its interface 🏛
    grapevine.🍇          package entry + overview docs
    bytes.🍇              its copy of shared/bytes.🍇
    LICENSE               its copy of the license at the root
    app.🍇               🍷 app, middleware pipeline, in-memory dispatch
    router.🍇             🧭 route table, 🛤 routes and their patterns, 🗂 route groups, 🎛 controller protocol
    request.🍇            📨 the request: target, query, headers, body
    response.🍇           📬 responses, result factories, 🚿 stream writer
    problem.🍇            🆘 problem documents, 🚧🔸🌐 the error that carries one
    rescue.🍇             🚑 what becomes of an error: mappers, the problem, or a logged 500
    binder.🍇             🧷 typed, checked values from the body, the query, the route, a form, cookies and headers
    shape.🍇              🧬 what a body, a query or an answer is made of, said once, and what a binder read by it
    openapi.🍇            the app's description of itself as an OpenAPI document, behind 📖
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
    tokens.🍇             🎖 signed tokens: what is issued, what is checked, and why one is refused
    guard.🍇              🛃 who may call a route, by its note, and the middleware that holds requests to it
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
  packages.sh           says whether each package can be released by itself (packages-test.sh tests it)
  smoke.sh              end-to-end test of the sample over real HTTP with curl
  lines.sh              every log line whole, with sixteen clients and a slowly read pipe
  numbers.sh            200,000 numbers read and 100,000 written, against Python (optional)
  wire/                 wire-level tests against containers: C#, xUnit, Shouldly, Testcontainers
  e2e/                  the sample's page in a headless browser: the same, with Playwright
.github/workflows/ci.yml  what GitHub runs for every pull request, and for main after a merge
build.sh              builds every package and links every program
serve.sh              what the image runs when it is given no command: the sample, to be tried out
test-wire.sh          builds the image and runs the wire tests
test-e2e.sh           builds the image and runs the browser tests
LICENSE               the license: MIT
build/                everything generated (ignored by git)
emojicode-defects/      a program for each defect of the compiler and its library that this ran into, for the language's author
docs/
  research/sha256.🍇    the trial that came before packages/crypto: SHA-256 in Emojicode alone
comparison/
  aspnet/               the same sample as an ASP.NET Core minimal API
  parity.sh             asks both the same things and compares what they answer
  tokens.py             token counts for both
```

## Packages

The repository holds three Emojicode packages. Each has a `packmoji.json` in its folder,
which describes it to [Packmoji](https://github.com/thatplatypus/Packmoji), the package
manager for Emojicode, and gives its version:

| Package | Folder | Needs |
|---|---|---|
| `@thatplatypus/crypto` | [packages/crypto](packages/crypto/README.md) | nothing |
| `@thatplatypus/deflate` | [packages/deflate](packages/deflate/README.md) | nothing |
| `@thatplatypus/grapevine` | [packages/grapevine](packages/grapevine/README.md) | `crypto` and `deflate` |

A version of a package is a release of this repository, tagged with the package's name
and its version, as in `crypto-v0.1.0`. No release has been made yet: the file of a
release is made by Packmoji, and the part of Packmoji that makes it is not finished.

A release holds the package's own folder and nothing above it. So each package has all
that it is built from in its folder, its own copy of the byte helpers and of the license
among it, and `tests/packages.sh` says with every run of the tests whether that is still
so.

## Build and run

Emojicode 1.0 beta 2 is the last release (2023) and ships **x86_64 binaries only**.

**Docker (most reliable, works on Apple Silicon via emulation):**

```sh
docker build -t grapevine .
docker run --rm -p 8080:8080 grapevine          # serve the Todo sample: open http://localhost:8080/
docker run --rm grapevine ./build.sh test       # every suite that needs no network
```

The first of those tries the sample out: the image's own command runs it as
`Development`, with the password of its README and a key made for the run. As a
deployment it starts with neither: the [sample's README](samples/todo/README.md) has
the command.

What is served is the [Todo sample](samples/todo/README.md): its API, and a page that
uses it.

`./build.sh test` runs the lint, a check that each package can be released by itself, the
unit tests for `packages/shared`, `packages/crypto`,
`packages/deflate` and `packages/grapevine`, a comparison of the crypto package's digests and
signatures with the system's own tools, a round trip of the compressor's streams through the
system's `gzip`,
100,000 fuzz cases against the HTTP engine and as many against the JSON reader, the sample's
in-memory tests, the curl smoke test, and a check that log lines stay whole under load. It
needs no network.

The wire tests drive containers of the image over real sockets: timeouts, more clients than
workers, SIGTERM, a soak, settings from the environment and from a file, log lines and request
IDs. They check tokens both ways against .NET's JWT library, and have .NET's OpenAPI reader
take the documents that the diagnostic app and the sample serve. They run on the host and
need Docker and the .NET 10 SDK:

```sh
./test-wire.sh
```

The browser tests open the sample's page in a headless Chromium, against containers of the
image: on the API's own origin, on another origin that the API allows, and on one that it does
not. They sign in on the page, look for the token wherever a page could have put it, and
follow the page's link to the API's description. They need Docker and the .NET 10 SDK as
well, and the first run downloads Chromium for Playwright:

```sh
./test-e2e.sh
```

`tests/numbers.sh` checks how numbers are read and written against Python, bit for bit, on far
more cases than the unit tests hold. It needs Python 3 on the host and is not part of either of
the above.

On GitHub, every pull request and every merge into `main` runs the first three of these:
`./build.sh test` in the image, `./test-wire.sh` and `./test-e2e.sh`, a job each in
[the workflow](.github/workflows/ci.yml).

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

The ASP.NET twin, which serves the sample's own page and takes the sample's settings
from the same variables (it needs the .NET 10 SDK):

```sh
cd comparison/aspnet && PORT=8081 dotnet run
```

Try either one:

```sh
curl -X POST localhost:8080/todos -H 'content-type: application/json' -d '{"title":"Ship it"}'
curl localhost:8080/todos
```

The list's numbers are for whoever has signed in. The sample gives a token for a name
and a password, which are `admin` and `vineyard` until it is given others:

```sh
token=$(curl -s -X POST localhost:8080/login -H 'content-type: application/json' \
  -d '{"user":"admin","password":"vineyard"}' | sed 's/.*"token":"\([^"]*\)".*/\1/')
curl -H "Authorization: Bearer $token" localhost:8080/admin/stats
```

What the sample's API takes and gives, as an OpenAPI 3.1 document that the framework writes
from what the routes say of themselves:

```sh
curl localhost:8080/openapi.json
```

Whether the two answer alike is checked by a script that starts both, asks each the same
hundred and more things and compares what a client can rely on. It needs Docker, the
.NET 10 SDK, `curl` and Python 3:

```sh
comparison/parity.sh
```

## Token comparison

The same sample twice: [`samples/todo`](samples/todo) on Grapevine, and
[`comparison/aspnet`](comparison/aspnet) on ASP.NET Core, written as ASP.NET is written.
Both serve the same page, read the same settings from the same variables, sign in the
same way and describe themselves as OpenAPI.

`python3 comparison/tokens.py` (needs `pip install "anthropic==0.38.0" tokenizers`, which
bundles the legacy Claude tokenizer; current models use a newer vocabulary, so the ratio
matters more than the absolute numbers). Comments and empty lines are taken out of both:

|  | lines | bytes | tokens |
|---|---:|---:|---:|
| Grapevine sample (Emojicode): `main.🍇`, `startup.🍇`, `todos.🍇` | 392 | 17,041 | 7,499 |
| ASP.NET minimal API (C#): `Program.cs` | 267 | 15,078 | 3,998 |
| **ratio** | 1.5× | 1.1× | **1.9×** |

With their comments the two are 9,683 and 4,586 tokens. Counted is each program's own
source, which is what a person writes to have the sample on a framework that is already
there. Not counted on either side: tests, the page, build scripts and the project file,
and the frameworks. The `grapevine` package itself is 41 files, 10,931 lines and 165,239
tokens, which ASP.NET ships in the box.

Where the tokens go, in numbers that the script prints too:

- **The syntax is most of it.** Each of `🍇 🍉 ❗️ ➡️ ↩️ ↪️` is 3 tokens and a `🔤` is 2,
  where `{ } ( ) ; => "` and `return` are 1 each. Those marks alone are 2,906 of the
  sample's tokens, 39 in every 100, and their counterparts are 1,092 of the twin's. Every
  call ends in `❗️`: 342 of them are 1,026 tokens. Every text has a `🔤` at each end: 388
  of them are 776.
- **Names are emoji.** Seven of every ten of the sample's tokens are in runs of emoji. A
  method called `📤` costs 3 tokens where `Ok` costs 1.
- **What is said in words costs the same.** The texts between quotes are 689 tokens in
  the sample and 714 in the twin.
- **Missing language features.** No properties, records, or reflection-based JSON, so
  the todo has hand-written getters and a serializer, and an optional is unwrapped with
  `↪️ … ➡️ x 🍇 … 🍉` where C# writes `is { } x`.

The ratio was 3.4× for the first, much smaller version of the two (3,423 tokens to
1,014). It fell as the sample grew: settings, a pipeline for browsers and a sign-in are
mostly names, numbers and texts, which cost C# about as much as they cost Emojicode,
and ASP.NET has no line for some of what Grapevine has a line for (the security
headers, the request's ID). The last step, from 2.3× to 2.1×, was the twin's: a review
found it doing less than the sample (it let a title of nothing but spaces through a
change, and read nothing of who issues a token, for whom, and how far two clocks may
differ), and what it lacked was written. And from 2.1× to 1.9× when a deployment was
asked for a key and a password of its own and proxies could be named by address: in
the sample the first is three lines and the second is the framework's setting, and the
twin writes both out.

### Whether the two are the same program

`comparison/parity.sh` starts both and asks each the same things: the list made, changed
and deleted; each kind of refusal, and what it says of a field where the programs choose
the words; the sign-in, the numbers and the limit on tries; tokens made elsewhere, each
wrong in one thing; the page's files, byte for byte; the headers for a browser; calls
from other origins; the OpenAPI document; and the settings that keep either from
starting. It compares what a client can rely on: the status, the kind of body, a JSON
answer value for value, and for a refusal that it is a problem document with the same
fields under `errors`. It also starts a second pair behind proxies that are named by
their networks, and plays the proxy, and a third whose proxies are named and are not
this machine, where nothing it forwards is to be believed. A hundred and one of those
are the same in both.

Twenty-five are known to differ, and the check fails if one of them goes away unnoticed.
By what causes them:

| | The sample | The twin |
|---|---|---|
| A field that is wrong, under `errors` | `title`, as the request wrote it | `Title`, as the C# record does |
| A field of the wrong kind, `{"title":7}` | 400 with `title` under `errors` | 400 that names no field: the reader of JSON gives up on the body |
| A problem that the framework makes itself, such as the 404 for no route | Has a `detail` that says what was wrong | Has a title and a status |
| How long a title is | Characters, once the space around it is gone: 200 emoji fit, and 200 letters with a space on each side | UTF-16 units, before the space is taken off: neither fits |
| How names are matched: `{"Title":…}`, `GET /TODOS`, `?done=TRUE`, `/todos/+1` | Letter for letter, and an id is digits: 400, 404, 400, 404 | In any case, and a number may have a sign: all four are taken |
| `GET /todos//1` | The todo: an empty segment is passed over | 404 |
| A member that is there twice | 400: the body is not taken | The last of them counts |
| `GET /todos?done=maybe` | 400: neither true nor false | 200 and the whole list: a value that cannot be read for a parameter that may be missing counts as missing |
| `HEAD /todos`, and `OPTIONS /todos` from no origin | 200, and 204 with `Allow` | 405 for both: HEAD is answered for files, and for a route only when it says so |
| A request from an origin that may not call, and a preflight for a method pages may not use | 403 for both, before a handler runs | 200 without the header that lets a page read it, and 204 with the methods pages may use, this one not among them. The browser does the refusing |
| A token whose `roles` is one text of two names | Two roles, as a scope is written | One role with a space in it |
| A token whose `exp` is a text of digits | Refused: a time is a number | Taken |
| What a 403 for the want of a role carries, and a 401 for the want of a token | `WWW-Authenticate` on the 403, `Cache-Control: no-store` on the 401 | Neither |
| A body over the limit, a 413 | Refused by the server before the app's layers see it: no headers for a browser, no request ID | Refused inside the pipeline, with both |
| The `X-Request-Id` of a proxy of the server's own that is said to write it | Taken as the request's ID. One that anyone else wrote is not, in either | Never read: the ID is the connection's own |
| The OpenAPI document | Has `GET /health` and how long a title may be, and not the `greeting` that `/hello` takes | Has neither health nor any bound, and has `greeting` |

The list is what the check asks. Most of it was found by a review that asked both
programs a hundred further things, and nothing says the two differ nowhere else.

Not compared, because each framework words them itself: what a refusal says in `detail`
(but for the two the programs choose, a todo that is not there and a sign-in that is
refused), why a token is refused beyond its code in `WWW-Authenticate`, a problem's
`type`, the `Allow` of a 405, the ID a request is given, the log, and the odd spellings
of an address that .NET's parser takes for `server.trustedProxies`. Not asked, since
the check would have to stop a server in the middle: what the health endpoint says of a
server that is stopping, which the sample answers with `stopping` and a 503, and the
twin has no word for. And two things that one program has and the other does not:

- **Who may call, in the document.** Grapevine reads it off the guard's notes: the numbers
  are described with the bearer scheme, a 401 and a 403. ASP.NET's document says nothing
  of it until a transformer of some twenty lines is written, which the twin does not have.
- **Validation that finds a record.** The validation that .NET 10 has for minimal APIs
  validates a record only when it is `public` and its attributes stand on the record's
  parameters. Otherwise it validates nothing and says nothing: the twin answered a todo
  without a title with a 500, until its records were made public. And an attribute
  looks at a text before the handler takes the space off it, so "not blank" is asked
  in a pattern: without it a change's title of three spaces was taken, and kept as
  nothing.

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
- Closures stored for later need `🎍🥡` to be escaping. So does a closure in a function of
  one or two statements in a package: such a function is compiled a second time by every
  program that imports the package, and a closure without `🎍🥡` then fails there with
  "Using non-escaping closure as escaping value", though the package itself compiled.
- **`📪` and `📫` (lower and upper case) overflow their buffer** for letters whose other case
  needs more bytes, such as Ⱥ. Grapevine folds case with its own ASCII-only `📪🐇🧮`.
- **`🔡 data❗️` does not validate UTF-8**, whatever its documentation says. Grapevine converts
  bytes to text through `🔡🐇🧮`, which does.
- **Interpolating `🐽 list index❗️` directly in a string literal miscompiles** and crashes at run
  time. Bind the element to a variable first.
- **A `🤝` or a `👐` frees every temporary object that its statement made before it.** A
  call that is handed a fresh text and then a test with `🤝` in it gets a text that has
  been freed: `👌 t 🔤a is 🧲a🧲🔤 a 🙌 3 🤝 b 🙌 5❗️` crashes. Put the test into a variable
  first. Found as "interpolation beside `🤝`", which was one case of it.
- **A value of any type (`⚪️`) held in a variable, cast, and the cast bound, is released
  twice.** A downcast of a class is the other way round: it has to be bound. And a
  parameter of type `⚪️` aborts the compiler.
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

[`emojicode-defects/`](emojicode-defects/README.md) has a short program for each of these
and of those below, a report written for the language's author, and a script that runs
them all and holds each to what the report says.

### Memory leaks the compiler writes for you

Emojicode counts references, and the 1.0 beta 2 compiler puts some of the releases in the wrong
place. A long-running server finds every one of them. `tests/lint.sh` rejects these patterns in
the shapes it knows (its own tests, `tests/lint-cases`, show which), and the `grapevine/leaks`
suite counts what the engine leaves allocated; the report in `emojicode-defects/` says where in
the compiler each comes from.
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

## License

MIT: see [LICENSE](LICENSE). Each package has a copy of it in its own folder, because a
release of a package holds that folder and nothing above it.
