# 🍇 Grapevine

An ASP.NET / NestJS-style HTTP framework written in [Emojicode](https://www.emojicode.org),
plus a Todo API built on it and the same API in ASP.NET Core for comparison.

It exists to answer one question: **what does a real, non-toy codebase look like in
Emojicode, and what does it cost in tokens compared to C#?** Answer so far: about
3.4× the tokens for the same app (see [Token comparison](#token-comparison)).

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
| automatic 404, 405, 413, problem+json errors | same |

A route and a middleware look like this:

```
📥 app 🔤/hello/:name🔤 🍇🎍🥡 r 📨 ➡️ 📬
  🆕🧾❗️ ➡️ json
  🔡 json 🔤message🔤 🔤Hello, 🧲🍺📌 r 🔤name🔤❗️🧲!🔤❗️
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
    bytes.🍇              🧳 byte buffer, 🧮 bounds-checked reads and UTF-8 validation
    check.🍇              🔬 assertion helper for test programs
    tests/                unit tests for the two files above
  grapevine/            the framework (an Emojicode package)
    build.sh              builds the package: libgrapevine.a and its interface 🏛
    grapevine.🍇          package entry + overview docs
    app.🍇               🍷 app, middleware pipeline, socket server loop
    router.🍇             🧭 router, 🗂 route groups, 🎛 controller protocol
    request.🍇            📨 request parsing (request line, headers, query, body)
    response.🍇           📬 responses, result factories, wire serialization
    json.🍇               🧾 JSON writer
    util.🍇               🧰 string helpers, percent-decoding, 📅 HTTP dates
    headers.🍇            🗄 ordered, multi-valued header collection
    settings.🍇           🎚 integer settings with defaults and ranges
    tests/unit/           white-box unit tests for the package
app/                  Todo API sample
  main.🍇               entry point (reads $PORT)
  startup.🍇            builds the app; shared by main and tests (like Program.cs)
  todos.🍇              model, store, 📒 controller
  tests.🍇              in-memory tests through 🧪
tests/smoke.sh        end-to-end test over real HTTP with curl
build.sh              builds every package and links every program
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

`./build.sh test` runs the unit tests for `packages/shared` and `packages/grapevine`, the
sample's in-memory tests, and the curl smoke test.

**Linux x86_64:** install the
[release](https://github.com/emojicode/emojicode/releases/tag/v1.0-beta.2) (it needs
`libtinfo5`; on Ubuntu 24.04 grab `libtinfo5_6.3-2_amd64.deb` from the jammy pool), then:

```sh
./build.sh test
PORT=8080 ./build/bin/todo-api
```

**macOS:** there's a `Darwin-x86_64` release that should run under Rosetta. Untested on
Apple Silicon — the compiler shells out to `c++` to link, and that has to produce
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

- **The syntax itself — most of the gap.** `🍇 🍉 ❗️ ➡️ ↩️ ↪️` are 3 tokens each, where
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

## Limits

One request per connection (`Connection: close`), single-threaded accept loop, no TLS,
no chunked transfer encoding, 1 MB body cap. It's a comparison specimen, not a
production server.
