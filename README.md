# 🍇 Grapevine

An ASP.NET / NestJS-style HTTP framework written in [Emojicode](https://www.emojicode.org),
plus a Todo API built on it and the same API in ASP.NET Core for comparison.

It exists to answer one question: **what does a real, non-toy codebase look like in
Emojicode, and what does it cost in tokens compared to C#?** Answer so far: about
3.4× the tokens for the same app (see [Token comparison](#token-comparison)).

The framework is being built out into a serious one, phase by phase. The server core is
done: a worker pool, keep-alive, timeouts, graceful shutdown and strict HTTP/1.1 framing.
[`packages/grapevine/README.md`](packages/grapevine/README.md) is its reference, and the
[roadmap](docs/superpowers/specs/2026-10-06-buildout-roadmap.md) says what comes next.

```
🍇 Grapevine listening on http://localhost:8080
   GET /todos
   GET /todos/:id
   POST /todos
   ...
  POST /todos → 201
  GET /todos/1 → 200
```

## What's in the framework

| Grapevine | ASP.NET / Nest equivalent |
|---|---|
| `🍷` app: `📥 📮 ✏️ 🛠 🗑` for GET/POST/PUT/PATCH/DELETE | `WebApplication`, `MapGet`… |
| `🧱` middleware `(request, next) ➡️ response` | `app.Use(...)` |
| `🗂` route groups | `MapGroup` / `@Controller('/path')` |
| `🎛` controller protocol, constructor-injected services | controllers / Nest providers |
| `:id` route params, `📍` int params, `🔎` query, `🏷` case-insensitive headers | route values, `[FromQuery]`, headers |
| `🌸` JSON body → `🍯🐚⚪️🍆`, `🧾` JSON writer | model binding / `System.Text.Json` |
| `✅ 🌸 🐣 🕳 🚫 👻 💥 📛` result factories | `Results.Ok/Json/Created/NoContent/BadRequest/NotFound/Problem` |
| `🎒 / 🎁` per-request items bag | `HttpContext.Items` |
| `🧪` in-memory dispatch, no socket | `TestServer` / `WebApplicationFactory` |
| `🎞` in-memory wire session: real request bytes in, real response bytes out | none; `TestServer` skips the wire |
| automatic HEAD and OPTIONS, `Allow` on 405, 501 for unknown methods | same |
| `📦` byte bodies, `🌊` streamed (chunked) responses | `Results.Bytes`, `Results.Stream` |
| repeated headers: `📚` every value, `📎` append | `StringValues`, `Headers.Append` |
| strict HTTP/1.1 parsing: chunked bodies, `Expect: 100-continue`, keep-alive, pipelining, request-smuggling defences | Kestrel |
| `🎚` settings for limits and timeouts | `KestrelServerLimits` |
| automatic 400, 404, 405, 408, 413, 414, 417, 431, 501 and 505, as problem+json | same |
| a pool of worker threads, keep-alive, pipelining, idle connections shed under load | Kestrel |
| graceful stop on SIGTERM, with a grace period and an exit code | `IHostApplicationLifetime` |

A route and a middleware look like this:

```
📥 app 🔤/hello/:name🔤 🍇🎍🥡 r 📨 ➡️ 📬
  🆕🧾❗️ ➡️ json
  🔡 json 🔤message🔤 🆕🔡 🍿 🔤Hello, 🔤 🍺📌 r 🔤name🔤❗️ 🔤!🔤 🍆 🔤🔤❗️❗️
  ↩️ 🌸🐇📬 📤 json❗️❗️
🍉❗️

🧱 app 🍇🎍🥡 r 📨 next 🍇📨➡️📬🍉 ➡️ 📬
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
  grapevine/            the framework (an Emojicode package)
    README.md             the package's API, settings and limits
    build.sh              builds the package: libgrapevine.a and its interface 🏛
    grapevine.🍇          package entry + overview docs
    app.🍇               🍷 app, middleware pipeline, in-memory dispatch
    router.🍇             🧭 router, 🗂 route groups, 🎛 controller protocol
    request.🍇            📨 the request: target, query, headers, body
    response.🍇           📬 responses, result factories, 🚿 stream writer
    parser.🍇             🧐 byte-level request parser, 🍰 chunked decoder
    connection.🍇         ☎️ per-connection loop, 🎞 in-memory wire session
    transport.🍇          🚇 transport protocol and its in-memory implementation
    net.🍇                🔩 bindings to the socket shim, 🔌 the transport over a socket
    native/net.cpp        the shim: sockets, poll, signals, the clock and a random key, in C++
    server.🍇             🚉 worker pool, saturation shedding, graceful stop
    json.🍇               🧾 JSON writer
    util.🍇               🧰 string helpers, percent-decoding, 📅 HTTP dates
    headers.🍇            🗄 ordered, multi-valued header collection
    map.🍇                🗝 names and their places, 📓 text under names (no stock dictionary)
    settings.🍇           🎚 integer settings with defaults and ranges
    tests/unit/           white-box unit tests, including a suite that measures leaks
    tests/fuzz/           mutation fuzzer for the HTTP engine
    tests/host/           diagnostic app the tests talk to, and wire-host, which serves it
app/                  Todo API sample
  main.🍇               entry point (reads $PORT)
  startup.🍇            builds the app; shared by main and tests (like Program.cs)
  todos.🍇              model, store, 📒 controller
  tests.🍇              in-memory tests through 🧪
tests/
  lint.sh, lint.pl      reject the constructs that leak, crash or corrupt memory
  smoke.sh              end-to-end test of the sample over real HTTP with curl
  wire/                 wire-level tests against containers: C#, xUnit, Shouldly, Testcontainers
build.sh              builds every package and links every program
test-wire.sh          builds the image and runs the wire tests
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
docker run --rm -p 8080:8080 grapevine          # serve
docker run --rm grapevine ./build.sh test       # every suite that needs no network
```

`./build.sh test` runs the lint, the unit tests for `packages/shared` and
`packages/grapevine`, 100,000 fuzz cases against the HTTP engine and as many against the JSON
reader, the sample's in-memory tests, and the curl smoke test. It needs no network.

The wire tests drive containers of the image over real sockets: timeouts, more clients than
workers, SIGTERM, a soak. They run on the host and need Docker and the .NET 10 SDK:

```sh
./test-wire.sh
```

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

### Memory leaks the compiler writes for you

Emojicode counts references, and the 1.0 beta 2 compiler puts some of the releases in the wrong
place. A long-running server finds every one of them. `tests/lint.sh` rejects these patterns and
the `grapevine/leaks` suite measures the engine for growth; the roadmap has the compiler source
references.

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
  is a double free. See Limits.

## Limits

No TLS: run it behind a reverse proxy. Bodies are held in memory, 1 MB by default
(`limits.bodyBytes`). A panic cannot be caught in Emojicode and ends the process, so run it
under a supervisor that restarts it.

Reading a request body as JSON (`🌸 request❗️`) leaks the whole parsed value, because values
from the stock JSON parser cannot be released safely: about 2 KB for a small object, 7 MB for a
390 kB object with 20,000 members. That parser has no depth limit either, so it is not for
bodies you do not trust, and the sample caps its bodies at 16 KB for that reason. Everything
else the engine does is measured to be leak-free. The framework's own JSON reader replaces the
stock parser in the next phase and ends this.
