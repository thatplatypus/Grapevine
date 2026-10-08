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
    🆕🧾❗️ ➡️ json
    🔡 json 🔤message🔤 🆕🔡 🍿 🔤Hello, 🔤 📌 r 🔤name🔤 🔤stranger🔤❗️ 🍆 🔤🔤❗️❗️
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
| `📥 app path handler❗️` | GET route. `📮` is POST, `✏️` PUT, `🛠` PATCH, `🗑` DELETE. A handler is `🍇📨➡️📬🚧🚧🍉`: it returns a response or raises. Each gives back the route, a `🛤`. |
| `🔖 route key value❗️`, `🏷 route key❗️` | Set a note on a route, and read one. See [Notes on routes](#notes-on-routes). |
| `🔇 route❗️` | Has a catch-all route stand aside for every other route, and for the methods that are not its own, and returns it. See [Route patterns](#route-patterns). |
| `🧱 app layer❗️` | Adds middleware, `🍇📨🍇📨➡️📬🍉➡️📬🚧🚧🍉`: the request and the rest of the pipeline, which never raises. Runs in the order added. |
| `🗂 app prefix❗️` | A route group. It has the same five route methods, under the prefix, and `🔖 group key value❗️` for a note on every route of the group, whenever it was registered. |
| `🎛 app prefix controller❗️` | Registers a controller: anything that conforms to `🎛` and adds its routes to the group it is given. |
| `🚑 app mapper❗️` | Adds an error mapper, `🍇🚧 📨➡️🍬📬🍉`: the answer for an error, or no value. See [Errors and problems](#errors-and-problems). |
| `📝 app❗️` | The built-in request logger, as middleware. See [Logging](#logging). |
| `🛂 app policy❗️` | The middleware that applies a CORS policy. See [Calls from another origin](#calls-from-another-origin). |
| `🛡 app shield❗️` | The middleware that puts security headers on every answer. See [Headers that make a browser careful](#headers-that-make-a-browser-careful). |
| `💓 app path❗️`, `💓 app name check❗️` | Registers a health endpoint, and adds a check to it. See [Health](#health). |
| `📢 app❗️` | The app's logger. |
| `🎚 app key number❗️`, `🎚🔸🔡 app key text❗️` | Set a setting. `🔧 app key❗️` and `🔧🔸🔡 app key❗️` read one. See [Settings](#settings). |
| `🌱 app key initial low high❗️`, `🌱🔸🔡 app key initial❗️` | Declare a setting of the application's own. |
| `📂 app❗️` | Lays the config file and the environment over the settings. |
| `🚀 app❗️` | Serves on `server.host` and `server.port`. Returns 0 after a clean stop and 1 when it could not start. |
| `🛑 app❗️` | Asks the server to stop, as SIGTERM does. From then on the health endpoint says so. |
| `🧪 app request❗️` | Runs one request through middleware and routing in memory and returns the response. |
| `⚠️ app❗️` | What would stop the server from starting: settings that are wrong, route patterns that are, a static directory that is not there, a CORS policy that cannot be meant, and whatever the application recorded itself. |
| `⚠️ app problem❗️` | Records a startup problem of the application's own, such as a setting of its own that makes no sense. `🚀` logs it and does not start. |

### Route patterns

A pattern is a path of segments. Empty segments are ignored, in a pattern as in a request,
so `/a//b/` is `/a/b`.

| Segment | Matches | The parameter holds |
|---|---|---|
| `todos` | That text, compared with the request's segment after decoding. | |
| `:name` | Any one segment. | The segment, decoded. |
| `:id:int` | One segment that is an integer: digits, with a minus sign in front for a number below zero, that 64 bits hold. | The segment as it was sent; `📍 r 🔤id🔤❗️` gives the number. |
| `:name?`, `:id:int?` | The same, or the end of the path. Only as the last segment. | The segment, or no value. |
| `*rest` | Whatever is left of the path, which may be nothing, unless a segment of it holds a slash or a backslash. Only as the last segment. | The remaining segments, decoded and joined with `/`. The empty text when there are none. |

**A parameter's value is whatever the client put in that segment.** A segment is decoded
after the path has been split, so one that was sent as `..%2F..%2Fetc` reaches a `:name`
as `../../etc`: one segment, with slashes in it. Never join a parameter to a directory
without checking it.

A catch-all is stricter, because its value is read as a path. It does not match when a
segment of what is left holds a slash or a backslash after decoding, so every slash in
its value is one the path had, and no part between two of them is `.` or `..` (the
server resolves those before it matches, and refuses the ones that were sent as
escapes). `/files/a%2Fb` is therefore not answered by `/files/*rest`, and cannot slip
past a more specific route such as `/files/private/:name` either. `🧶 r❗️` has the
segments themselves.

**The most specific route wins, whatever order the routes were registered in.** The
routes that match a path are compared segment by segment from the left, and the first
difference decides: a literal before `:id:int`, before `:id:int?`, before `:name`, before
`:name?`, before `*rest`. Where the path ends, a pattern that ends with it comes before one
with an optional parameter left over, and that before a catch-all that took nothing. So
`/todos/new` answers before `/todos/:id:int`, which answers before `/todos/:name`.

The method is settled among the routes that match:

- **HEAD** is answered by the most specific GET route. The handler runs, the body is
  dropped, and `Content-Length` keeps the length the body had.
- A more specific route that lacks the method does not hide a less specific one that has
  it: with `GET /things/:id` and `DELETE /things/special`, `GET /things/special` is
  answered by the first.
- When no route that matches has the method, **OPTIONS** is 204 and anything else is
  **405**, each with an `Allow` header that lists the methods of all of them, but for
  the routes that stand aside (below). `OPTIONS *` lists every supported method.
- When no route matches, **404**.
- **A catch-all that answers for whatever nothing else did** would make a 405 of every
  path without a route, for every method but its own: with `GET /*rest` for a page to
  fall back on, a POST to a path that is not there would be told `Allow: GET`. Have such
  a route stand aside: `🔇 📥 app 🔤/*rest🔤 page❗️❗️`. To a method that is not its own
  it is not there, so that the POST is a 404, or a 405 that lists the routes the path
  really has. And it answers its own method only on a path that no other route has: with
  `POST /api/things` beside it, `GET /api/things` is a 405 with `Allow: POST, OPTIONS`,
  and not the page. A directory of static files is mounted this way.

A pattern that is wrong is not registered, and the server will not start: `⚠️ app❗️`
lists it, and `🚀` logs it and returns 1. Wrong is a parameter without a name, or with a
name that has anything but letters, digits and underscores in it; a constraint other than
`int`; an optional parameter or a catch-all before the last segment; the same name twice;
a literal segment that is `.` or `..`, or that holds a `?`, a `#` or an escape such as
`%20`, none of which a path has by the time it is matched; and a route that cannot be
told from one registered before it for the same method:
`route GET /a/:id?/b: an optional parameter must be the last segment`. The name rule is
what catches a misspelling: `:id?:int` would otherwise be a parameter called `id?`, where
`:id:int?` was meant.

### Matching comes before middleware

The app finds a request's route first and runs the middleware second, so middleware knows
where a request is going: `🛤 r❗️` is the pattern of the route it matched, and
`🏷🔸🛤 r key❗️` one of that route's notes. The end of the pipeline calls the route's
handler, or gives the 404, 405 or 204 above. Middleware therefore still sees those
answers, and can still answer in their place.

A layer usually hands `next` the request it was given. It may hand on one of its own
making, to have one path answered as another:

```
🧱 app 🍇🎍🥡 r 📨 next 🍇📨➡️📬🍉 ➡️ 📬 🚧🚧
  ↪️ 🎼 🥩 r❗️ 🔤/v1/🔤❗️ 🍇
    🆕📨 🚦 r❗️ 🦶🐇🧰 🥩 r❗️ 3❗️❗️ ➡️ moved
    💾 moved 📇 r❗️❗️
    🔖 moved 🔤Content-Type🔤 🏷 r 🔤Content-Type🔤 🔤🔤❗️❗️
    ↩️ ⁉️ next moved❗️
  🍉
  ↩️ ⁉️ next r❗️
🍉❗️
```

A request the app has not seen is treated as new where it is handed on: a target that
cannot be decoded is a 400, the app's limits on JSON and on forms apply to it, and its
route is looked for. The layers after that one, and the handler, see the new request and
its route. What the new request has is what the layer gave it: the headers, the body,
the ID and the items of the old one are not copied for it. A body goes with the header
that says what it is, as above, or it will not be read as JSON or as a form.

### Notes on routes

A note is text under a name, on a route, for middleware to act on. The framework's guard
reads the note `auth` ([Who may call](#who-may-call)), and nothing in it reads any other:
those are for layers of your own. Here `stats` and `health` are handlers:

```
🗂 app 🔤/admin🔤❗️ ➡️ admin
🔖 admin 🔤policy🔤 🔤admin🔤❗️
📥 admin 🔤/stats🔤 stats❗️
🔖 📥 app 🔤/health🔤 health❗️ 🔤policy🔤 🔤open🔤❗️

🧱 app 🍇🎍🥡 r 📨 next 🍇📨➡️📬🍉 ➡️ 📬 🚧🚧
  ↪️ 🏷🔸🛤 r 🔤policy🔤❗️ ➡️ policy 🍇
    ↪️ policy 🙌 🔤admin🔤 🍇
      ↪️ 🏷 r 🔤x-api-key🔤❗️ ➡️ key 🍇
        ↪️ key 🙌 🔤vineyard🔤 🍇
          ↩️ ⁉️ next r❗️
        🍉
      🍉
      🚨 🆕🚧🔸🌐 401 🔤Missing or invalid x-api-key🔤❗️
    🍉
  🍉
  ↩️ ⁉️ next r❗️
🍉❗️
```

`🔖 route key value❗️` returns the route, so notes chain, and `🏷 route key❗️` reads one
back. `🚦 route❗️` and `🛣 route❗️` are the route's method and pattern.

**A group's note is a note of every route of the group, and of the groups under it,
whenever each was registered**: before the note was set or after. Where a note stands for
something a route must not go without, such as who may call it, a route that was
registered one line too early would otherwise be the one without its guard. A route's
own note wins over its group's, and the note of a nearer group over that of an outer
one. Set notes before `🚀`: they are read once the server runs.

## The request: 📨

| Call | Meaning |
|---|---|
| `🚦 r❗️` | The method, exactly as sent. Methods are case-sensitive. |
| `🛣 r❗️` | The decoded path, without the query. |
| `🛣🔸📁 r❗️` | Whether the path was written as a directory: with a slash at its end, or a `.` or `..` segment there, which stand for one. The path and its segments do not show it. |
| `📌 r name❗️` | A route parameter, or no value. It is the decoded segment, which can hold a slash: see [Route patterns](#route-patterns). `📍` gives it as an integer, and no value when it is not one that 64 bits hold. |
| `🛤 r❗️`, `🏷🔸🛤 r key❗️` | The pattern of the route the request matched, and a note of that route. Both are known before middleware runs. The pattern is empty when no route matched, and also for a route that was registered with an empty pattern; `🛤🔸🎯 r❗️` is the route itself, or no value, and is the way to ask whether there is one. |
| `🔎 r name❗️` | The first query value for a name, or no value. |
| `🍪 r name❗️`, `🍪🔸🗝 r❗️` | A cookie's value, decoded, or no value; and the names of the cookies. See [Cookies](#cookies). |
| `📌 r name fallback❗️`, `📍 r name fallback❗️`, `🔎 r name fallback❗️`, `🏷 r name fallback❗️`, `🎒 r key fallback❗️`, `🍪 r name fallback❗️`, `📋 r name fallback❗️` | The same seven with one more argument give a plain value in place of an optional: what the request has, or *fallback* when it has nothing under the name. For `📍` the fallback is an integer, and is also what a parameter that is no integer gives: on a route that does not ask for `:int`, choose a fallback that is no id. A query value that is empty is a value. |
| `🔭 r name❗️` | Every query value for a name, in order. |
| `🗝 r❗️` | The distinct query names, in the order first seen. |
| `🏷 r name❗️` | A header by case-insensitive name. Repeats are joined with `, ` (`; ` for `cookie`). |
| `📚 r name❗️` | Every value of a header, in the order received. |
| `🐙 r❗️` | The distinct header names, lower-cased. |
| `📇 r❗️` | The body as bytes. |
| `📄 r❗️` | The body as text. Empty when the body is not valid UTF-8. |
| `🎭 r❗️`, `🎭 r name❗️` | The media type of the body, from `Content-Type`: in lower case and without its parameters, as in `application/json`; and one of those parameters, such as `charset`, by its name in any case. See [The type of a body](#the-type-of-a-body). |
| `🌸 r❗️` | The body read as JSON: a `💠`, or no value when the body is not JSON, by what it says it is or by what is in it. See [JSON](#json). |
| `🌸🔸🚩 r❗️` | What was wrong with the body the last time `🌸` read it, and where: `repeated key at byte 7`, or `not JSON by its type`. Empty when `🌸` gave a value, and before it was asked. |
| `🌸🔸🆘 r❗️` | The problem for a body that `🌸` gave no value for: a 400 that says the body is not valid JSON, and why, or a 415 that says what its `Content-Type` is when that is what kept it from being read. For a handler to raise: `🚨 🧨 🌸🔸🆘 r❗️❗️`. |
| `📋 r name❗️`, `📋🔸📚 r name❗️`, `📋🔸🗝 r❗️` | A field of the form in the body, or no value; every value of a field; and the names of the fields. See [Forms and files](#forms-and-files). |
| `📁 r name❗️`, `📁🔸📚 r name❗️`, `📁🔸🗝 r❗️` | A file that came in a form, a `📎`, or no value; every file of a field; and the names of the fields that files came under. |
| `📋🔸🚩 r❗️`, `📋🔸🆘 r❗️` | What kept the form from being read, empty when it was read; and the problem to raise for it, a 400 or a 415. |
| `🎯 r offers❗️` | The one of a list of media types that the client would rather have, by its `Accept` header, or no value. See [What the client accepts](#what-the-client-accepts). |
| `🎒 r key❗️`, `🎁 r key value❗️` | A bag of text items that lives as long as the request, for middleware to pass things to handlers. |
| `🆔 r❗️` | The request's ID. See [Request IDs](#request-ids). |
| `🥩 r❗️`, `🥩🔸🛣 r❗️` | The target exactly as it was sent, and the part of it before the question mark. These are the forms to write to a log: the decoded path can hold line breaks that were sent as escapes. |
| `🧬 r❗️` | The HTTP version, `1.1` or `1.0`. |
| `🌐 r❗️`, `🌐🔸🔌 r❗️` | The client's address, and the address of whoever opened the connection. They are the same unless the app trusts proxies: see [Behind a proxy](#behind-a-proxy). |
| `🌐🔸🏙 r❗️` | What to count the client by: its address on IPv4, and on IPv6 the network its address is in, as in `2001:db8:0:1::/64`. See [Rate limits](#rate-limits). |
| `🏠 r❗️`, `🏠🔸🛡 r❗️`, `🛣🔸🧱 r❗️` | The origin the client used, as in `https://shop.example`; whether that was HTTPS; and the prefix a proxy took off the path. Without proxies that are trusted: `http` and the `Host`, no, and nothing. |

To build a request for a test: `🆕📨 🔤POST🔤 🔤/todos?x=1🔤❗️`, then `🔖 r name value❗️`
or `📎 r name value❗️` for headers and `📃 r text❗️` or `💾 r data❗️` for the body.
`🌸 r text❗️` sets a body of JSON together with the `Content-Type` that says so, without
which it would not be read as JSON.

Paths are decoded one segment at a time, after `.` and `..` have been resolved, so an
encoded slash or dot can never change which route matches. In a query `+` is a space; in a
path it is a plus sign.

### The type of a body

`🎭 r❗️` is what the request says its body is: the media type from `Content-Type`, in lower
case and without its parameters. It is the empty text when the request says nothing of
it, when what it says is no type, and when it says it twice, in two headers or as a list
in one: nobody can say which is meant, and something in front of the server may have
gone by the other. `🎭 r 🔤charset🔤❗️` is one of the parameters, or no value, which it
also is for a parameter that is there twice.

**A body is read as JSON only when its type says that it is JSON**: `application/json`,
or a type that ends in `+json`. For anything else `🌸 r❗️` gives no value, whatever is in
the body, `🌸🔸🆘 r❗️` is a 415, and a binder says the same:

```json
{"type":"about:blank","title":"Unsupported Media Type","status":415,"detail":"The body must be JSON, and its Content-Type is text/plain"}
```

That is not tidiness. A page on any site can have a browser post bytes of its choosing
to your server, with the visitor's cookies and without asking first, as long as the type
is one a form could send: `text/plain`, `application/x-www-form-urlencoded` or
`multipart/form-data`. JSON is not such a type. A server that reads JSON only from a
request that says it is JSON makes the browser ask first, and the answer to that is the
CORS policy's to give (see [Calls from another origin](#calls-from-another-origin)). A
server that reads JSON out of whatever it is sent can be told what to do by a form on
someone else's page.

A request with no body at all has nothing whose type could be wrong, and is told that
the body is not valid JSON, with a 400.

### Forms and files

A body is a form when it says so: `application/x-www-form-urlencoded`, which is what a
browser sends for a form that says nothing else, or `multipart/form-data`, which it
sends for a form with files. Both are read with the same calls:

```
📮 app 🔤/profile🔤 🍇🎍🥡 r 📨 ➡️ 📬 🚧🚧
  ↪️ 📐 📋🔸🚩 r❗️❗️ ▶️ 0 🍇
    🚨 🧨 📋🔸🆘 r❗️❗️
  🍉
  📋 r 🔤name🔤 🔤🔤❗️ ➡️ name                💭 a field, or the fallback
  📋🔸📚 r 🔤interest🔤❗️ ➡️ interests        💭 every value of a field that came more than once
  ↪️ 📁 r 🔤avatar🔤❗️ ➡️ file 🍇
    📛 file❗️      💭 photo.png
    🎭 file❗️      💭 image/png
    📏 file❗️      💭 48213
    📇 file❗️      💭 the bytes
  🍉
  …
🍉❗️
```

| Call | Meaning |
|---|---|
| `📋 r name❗️` | The first value of a field, or no value when the form has no such field. With a fallback as one more argument, a plain value. |
| `📋🔸📚 r name❗️` | Every value of a field, in the order they came: a group of checkboxes, or a list that allows several. |
| `📋🔸🗝 r❗️` | The names of the fields, once each, in the order they first came. Files are not among them. |
| `📁 r name❗️` | The first file that came under a field, a `📎`, or no value. |
| `📁🔸📚 r name❗️` | Every file of a field: a file input that takes several. |
| `📁🔸🗝 r❗️` | The names of the fields that files came under. |
| `📋🔸🚩 r❗️` | What kept the form from being read. Empty when it was read. |
| `📋🔸🆘 r❗️` | The problem to raise for a form that was not read: a 400 with the reason, or a 415 for a body of another type. |
| `📛 file❗️`, `🎭 file❗️`, `📏 file❗️`, `📇 file❗️` | A file's name, its media type (`application/octet-stream` when the client gave none that can be read), how many bytes it has, and the bytes. |

- Fields keep the order they came in, a name may come more than once, and names are
  told apart by case. A field that was left blank is the empty text, and one that is not
  there is no value. A pair without `=` in a plain form is a name with an empty value. A
  pair or a part whose name is empty is passed over.
- The form is read once, the first time anything of it is asked for. A handler that
  never asks never reads it.
- **A form that cannot be read gives nothing of itself**, neither a field nor a file, so
  that no handler acts on the half of one. `📋🔸🚩 r❗️` says why, and the client is told
  the same: `The form cannot be read: a field cannot be decoded`. A body of another type
  is a 415: `The body must be a form, and its Content-Type is application/json`. A
  request without a body is a form of no fields.
- What cannot be read, in a plain form: an escape that is not `%` and two hex digits,
  one that makes a zero byte, and bytes that are not UTF-8. In a form in parts: a
  `Content-Type` without a boundary, with two, or with one that RFC 2046 does not allow;
  a body with no closing boundary line; a part whose headers do not end, are longer than
  16,384 bytes, have a control character in a line (a line feed or a carriage return by
  itself among them), have no `Content-Disposition` or one that is not `form-data`, name
  no field, or name the field or the file twice; and a value, or a name, that is not
  UTF-8 or holds a zero byte. A file's bytes are kept whatever they are.
- A form may have `limits.formFields` fields, 1024 unless you say otherwise, files
  counted among them. One with more is not read.
- A part is a file when it names one. A part that names a file with the empty text and
  has no bytes is what a browser sends for a file field that was left empty: it is
  passed over, and `📁 r name❗️` gives no value for it. A file of no bytes that has a
  name is a file.
- A file's name is read from `filename*` when the client gives one in UTF-8, which is
  where a client writes a name that is not ASCII, and from `filename` otherwise. The
  *field's* name has no such second spelling. A client that writes one that is not ASCII
  as an encoded word, as .NET's does (`=?utf-8?B?…?=`), is read as it wrote it: keep the
  names of fields in ASCII.
- A line in a file that begins like the boundary is part of the file unless it is a
  boundary line to its end. What stands before the first boundary line and after the
  closing one is passed over.

**A file's name and its type are the client's word, and nothing more.** The name is cut
down to what stands after its last slash or backslash, so it is never a path, and it
has no control character in it. That is all that is done to it. It can still begin with
a dot, be the name of a file you already have, or be empty. Keep what is uploaded under a name of your own making, and
the client's name beside it as text if it is to be shown. The type says nothing certain
about the bytes. And a directory of uploads is not one to mount as static files: see
[A directory of static files](#a-directory-of-static-files).

A form is held in memory like any body, so it is as large as `limits.bodyBytes` allows
at most, its files included, and a file's bytes are held a second time once the form is
read.

### What the client accepts

A handler that can answer in more than one form asks which of them the client would
rather have:

```
📥 app 🔤/report🔤 🍇🎍🥡 r 📨 ➡️ 📬 🚧🚧
  ↪️ 🎯 r 🍿 🔤application/json🔤 🔤text/csv🔤 🍆❗️ ➡️ kind 🍇
    ↪️ kind 🙌 🔤text/csv🔤 🍇
      ↩️ 🦎 🔖 ✅🐇📬 🔤day,sold❌nMon,12❌n🔤❗️ 🔤Content-Type🔤 🔤text/csv; charset=utf-8🔤❗️ 🔤Accept🔤❗️
    🍉
    ↩️ 🦎 🌸🐇📬 🔤[{"day":"Mon","sold":12}]🔤❗️ 🔤Accept🔤❗️
  🍉
  ↩️ 📛🐇📬 406 🔤The report comes as JSON or as CSV🔤❗️
🍉❗️
```

`🎯 r offers❗️` goes by the request's `Accept` header and gives one of the offers, as it
was written, or no value when the client takes none of them, which is when a handler
answers 406. An offer is a media type, with parameters or without.

- An offer has the quality of the most specific range that matches it: the type itself
  before `text/*`, and that before `*/*`. So `application/json;q=0, */*` never picks
  JSON, whatever else it accepts.
- The highest quality wins. Among equals, the offer that a more specific range named;
  among those, the earlier offer. The order in which the client wrote its ranges does
  not count.
- A client that sends no `Accept`, or an empty one, takes the first offer.
- Types are compared without regard to case. A range's parameters other than `q` are
  not looked at, and neither are an offer's.
- A range that is no type is passed over. A quality that is no number counts as 1, and
  one outside 0 to 1 is held to that range.

An answer that depends on `Accept` should say so with `🦎 response 🔤Accept🔤❗️`, or a
cache will hand one client what another asked for.

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
| `🌊🐇📬 contentType length producer❗️` | 200 | written in pieces, of a length known beforehand: see below |
| `🔀🐇📬 location❗️`, `🔀🐇📬 location status❗️` | 302, or 301, 303, 307 or 308 | none; see [Redirects](#redirects) |
| `🔀🔸🏠🐇📬 location fallback❗️` | 302 | none; to *location* only when it is a path on this site |
| `🆕📬 code body contentType❗️` | any | text |

On a response, `🔖 response name value❗️` sets a header and `📎 response name value❗️`
adds a value to one. Both return the response, so they chain:
`↩️ 🔖 ✅🐇📬 🔤ok🔤❗️ 🔤Cache-Control🔤 🔤no-store🔤❗️`. So do these:

| Call | Meaning |
|---|---|
| `🍪 response cookie❗️` | Sets a cookie, in a `Set-Cookie` header of its own. See [Cookies](#cookies). |
| `♻️ response r❗️`, `🔏 response r❗️` | Make the response a 304 when the client that sent *r* has it already. See [Letting the client keep its copy](#letting-the-client-keep-its-copy). |
| `🦎 response name❗️` | Says that the answer depends on the request header *name*, by adding it to `Vary`. A name that is there already, in any case, is not added twice, and a `Vary` of `*` stays as it is. Whatever answers differently by a request header has to say so, or a cache hands one client the answer made for another. |
| `💾 response filename❗️` | Makes it a download: `Content-Disposition: attachment` with the name to save it under. A directory in front of the name is dropped. The name is sent twice, as browsers want it: in ASCII, with `_` for every character that is not and for `"` and `\`, and whole, percent-encoded, as `filename*=UTF-8''…`. |

`🚥`, `🏷`, `📚`, `📄` and `📇` read a response back, which is what tests use.

**A response is made for one request.** The app writes the request's ID onto it, and `♻️`
and `🔏` change it. A handler that keeps one response to return every time is returning
something that the last request changed.

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

When the length is known beforehand, give it, and the body goes out with `Content-Length`
and without chunks, to either kind of client, on a connection that is kept:

```
↩️ 🌊🐇📬 🔤application/octet-stream🔤 size 🍇🎍🥡 writer 🚿
  …
🍉❗️
```

The length is a promise. The sink takes that many bytes and no more: the write that
would go past it is cut there and returns 👎. When the producer has written fewer, or
tried to write more, the connection is closed behind the response, because the client
was told a length that did not come and would read the next response as part of this
one. A HEAD is answered with the length and the producer is not called.
`📏🔸🌊 response❗️` is the length a response promised, or no value.

### Redirects

`🔀🐇📬 location❗️` is a 302 with `Location` and no body; a second argument makes it a
301, 303, 307 or 308, and any other status is taken as 302. A line break in the location
cannot start a header: it is removed, like in any header value.

**Never redirect to where a query parameter says.** A link to your site that sends people
on to someone else's is what phishing mail is made of. For a location that came from the
client, such as the page to go back to after signing in, there is
`🔀🔸🏠🐇📬 location fallback❗️`: it goes to *location* when that is a path on this site,
which means it begins with one `/`, does not go on with `/` or `\`, and holds no control
character, and to *fallback* in every other case.

### Cookies

A request's cookies are read by name:

| Call | Meaning |
|---|---|
| `🍪 r name❗️` | The value of the first cookie called *name*, or no value. Names are told apart by case. |
| `🍪 r name fallback❗️` | The same as a plain value. |
| `🍪🔸🗝 r❗️` | The distinct names, in the order first seen. |

Every `Cookie` header is read. A pair without `=` or without a name is ignored, the
spaces around a name and a value are dropped, a value in double quotes loses them, and
percent-escapes are decoded. A value whose escapes are wrong, or decode to something that
is not text, is given as it was sent.

A cookie to set is a `🍪`. Every setter returns the cookie, so they chain:

```
↩️ 🍪 🕳🐇📬❗️ 🔒 ⏳ 🆕🍪 🔤sid🔤 token❗️ 3600❗️ 👍❗️❗️
```

| Call | Meaning |
|---|---|
| `🆕🍪 name value❗️` | A cookie with `Path=/`, `HttpOnly` and `SameSite=Lax`, that lasts until the browser closes. |
| `⏳ c seconds❗️` | `Max-Age`. Zero or less asks the browser to drop the cookie now. |
| `🛣 c path❗️`, `🌐 c domain❗️` | `Path` and `Domain`. An empty text leaves the attribute out. |
| `🔒 c flag❗️` | `Secure`: sent over HTTPS only. Off unless it is turned on, since the server cannot see whether the proxy in front of it speaks HTTPS. Turn it on in production. |
| `🙈 c flag❗️` | `HttpOnly`: kept from the page's scripts. On unless it is turned off. |
| `👫 c mode❗️` | `SameSite`: `Strict`, `Lax` or `None`, in any case; anything else leaves the attribute out. `None` turns `Secure` on, which browsers demand. |
| `🗑 c❗️` | Makes it the cookie that removes itself: no value and `Max-Age=0`. Its path and domain have to be the ones the cookie was set with. |
| `📤 c❗️` | The header's value: `sid=abc; Path=/; Max-Age=3600; Secure; HttpOnly; SameSite=Lax`. Empty when the name is not a token. |

A value can be any text. What a cookie's value may not hold (a space, `;`, `,`, `"`, `\`,
anything outside ASCII) is percent-encoded, and so is `%`, so that `🍪 r name❗️` gives
back exactly what was set. The one value that does not come back is a zero byte, which
no text read from a request may hold: it goes out as `%00` and comes back as those three
characters. A path and a domain lose `;` and control characters. **A
cookie whose name is not a token** (it is empty, or holds a space, `=`, `;` or a
character outside ASCII) **cannot be sent, and `🍪 response c❗️` leaves it out without a
word**, as a header with such a name is left out.

A cookie is not a secret and not proof of anything: the browser's owner can read and
change it. What must not be forged goes in a signed token, which Phase 7 brings.

### Letting the client keep its copy

A response can say what version it is, with an `ETag`, a `Last-Modified`, or both. A
client that has a copy sends those back with its next request, and when the copy is
still good the answer is a 304 with no body.

| Call | Meaning |
|---|---|
| `♻️ response r❗️` | Makes the response a 304 when *r* is a GET or a HEAD, the response is a 200, and the request shows that the client has it. Returns the response. |
| `🔏 response r❗️` | First gives a 200 that has no `ETag` and is not streamed a weak one, made from its body. Then does what `♻️` does. |

```
📥 app 🔤/report🔤 🍇🎍🥡 r 📨 ➡️ 📬 🚧🚧
  ↩️ 🔏 🌸🐇📬 📤 report❗️❗️ r❗️
🍉❗️
```

The client has it when the response has an `ETag` and the request's `If-None-Match`
names it, among several or as `*`. Tags are compared weakly, so `W/` in front of either
does not count. Only when the request has no `If-None-Match`: when the response has a
`Last-Modified` and the request's `If-Modified-Since` is not before it. A date is read in
each of the three forms HTTP allows, and one that cannot be read is ignored.

The 304 keeps every header the response had but `Content-Type`, `Content-Encoding`,
`Content-Language` and `Content-Range`, which describe a body it does not have. So a
`Cache-Control`, a `Vary` and a cookie set on the 200 are on the 304 too.

The tag `🔏` makes is `W/"`, the body's length in hexadecimal, a dash, sixteen digits of
a hash of its bytes, and `"`. It tells two bodies apart for caching. It is not a secret
and not a signature. The handler still does all its work to build the body; what is
saved is sending it. To tag everything an app sends:

```
🧱 app 🍇🎍🥡 r 📨 next 🍇📨➡️📬🍉 ➡️ 📬 🚧🚧
  ↩️ 🔏 ⁉️ next r❗️ r❗️
🍉❗️
```

`If-Match` and `If-Unmodified-Since`, which guard a change against one made in between,
are not read: a handler that wants that compares the tag itself and answers 412.

## Files

`📁` answers with files from disk, and `🗃` serves a directory of them. Nothing here
raises: what is not there is a response with the status 404.

| Call | Meaning |
|---|---|
| `📬🐇📁 r path❗️` | The file at *path* as the answer to *r*. The path is the handler's own, and nothing about it is checked. |
| `📬🐇📁 r directory name❗️` | The file *name* under *directory*, for a name that came from the client. See [A name from a client](#a-name-from-a-client). |
| `🎭🐇📁 name❗️` | The media type a file name stands for, by what follows its last dot, in any case: `text/html; charset=utf-8` for `index.HTML`. Types that are text say that they are UTF-8. A name without an extension, or with one the table does not have, is `application/octet-stream`. The table has what a site is made of: HTML, CSS, JavaScript, JSON, source maps, text, CSV, XML, Markdown, SVG, PNG, JPEG, GIF, WebP, AVIF, ICO, BMP, WOFF, WOFF2, TTF, OTF, PDF, ZIP, gzip, WebAssembly, MP3, MP4, WebM, Ogg, WAV and web manifests. |
| `🚰🐇📁 path offset length❗️` | The source of *length* bytes of a file, from *offset* on, for a body of known length of the handler's own making: `🌊🐇📬 type length 🚰🐇📁 path 0 length❗️❗️`. |

What a request for a file is answered with:

- **404**, a problem, when there is no file at the path. A directory is not a file, and
  a file that the server's user may not read is not there.
- **200** with the file as the body, sent in pieces of 64 KB, so that a file of any size
  is served without being held in memory. It has the media type of its name,
  `Content-Length`, `Last-Modified`, an `ETag` made of its size and the time it was
  changed (`"1a-b690b434e8"`), and `Accept-Ranges: bytes`. A handler that wants another
  type sets `Content-Type` on what comes back.
- **304** when the request shows that the client has the file, by `If-None-Match` or
  `If-Modified-Since`, as [`♻️`](#letting-the-client-keep-its-copy) decides.
- **206** for a GET with one `Range` of bytes that the file can satisfy, with
  `Content-Range` and that part as the body. The forms are `bytes=0-99`, `bytes=100-`
  and `bytes=-50`; a last position beyond the end of the file means the end. With
  `If-Range` the part is sent only when that is the file's `ETag` or its `Last-Modified`
  to the letter, and the whole file otherwise.
- **416**, a problem, with `Content-Range: bytes */size`, when no byte of the file is in
  the range.
- A `Range` that asks for several parts, is not in bytes or cannot be read is ignored,
  and the whole file is sent, which HTTP allows. So is any `Range` on a HEAD.

A file is opened when its body is sent, and closed before that is over. A response that
middleware replaces, a HEAD and a 304 open nothing. When a file has become shorter, or
has gone, between being looked at and being sent, what can still be read is sent and
the connection is closed: the length had been promised.

### A name from a client

**Never join what a client sent to a directory.** A route parameter is the decoded
segment, so `/downloads/..%2F..%2Fetc%2Fpasswd` reaches a handler for
`/downloads/:name` with the name `../../etc/passwd`. A field of a form or of a JSON body
can hold the same. For such a name there is the form with a directory:

```
📥 app 🔤/downloads/:name🔤 🍇🎍🥡 r 📨 ➡️ 📬 🚧🚧
  ↩️ 📬🐇📁 r 🔤downloads🔤 📌 r 🔤name🔤 🔤🔤❗️❗️
🍉❗️
```

The name is cut at its slashes, and empty parts do not count, so a slash in front does
not make it absolute. The answer is a 404 that names the last part of what was asked
for, and nothing else, when:

- a part is `.` or `..`, holds a backslash or a zero byte, or begins with a dot (`.env`,
  `.git`);
- the name ends in a slash: `a.txt/` is the name of a directory, and not of the file;
- the name leads to nothing, or to a directory;
- the real path of what it leads to, with every link followed, is not under the real
  path of the directory. A link inside the directory that points out of it leads
  nowhere.

`🧭🐇📁 directory name hide❗️` is the check by itself: the real path of what the name
leads to, a file or a directory, or the empty text. With *hide* 👍, which is what the
call above passes, a name that begins with a dot leads nowhere. With 👎 it is a name
like any other.

This holds against whatever a client sends. It does not hold against someone who can
write to the directory while it is served: a link put in between the check and the read
is followed.

### A directory of static files

```
🗃 app 🔤/assets🔤 ⏳ 🆕🗃 🔤public🔤❗️ 31536000❗️❗️
🗃 app 🔤🔤 🆕🗃 🔤site🔤❗️❗️
```

`🗃` is a directory to serve, and every setter returns it:

| Call | Meaning |
|---|---|
| `🆕🗃 directory❗️` | The files under *directory*. |
| `⏳ files seconds❗️` | `Cache-Control: public, max-age=seconds` on what is served. It starts at 0: the browser keeps a file, asks each time, and is told 304 when nothing changed. For files whose names change when they do, a year is usual. |
| `📇 files name❗️` | The file served for a directory. `index.html` unless this says otherwise; an empty name serves nothing for a directory. |
| `🎭 files extension type❗️` | A media type for an extension, in any case and with or without its dot, in place of or on top of the table's. |
| `🙈 files flag❗️` | Whether names that begin with a dot are hidden. They are unless this says 👎. |
| `🗃 app prefix files❗️` | Serves them under *prefix*, to GET and HEAD, and returns the route, which takes notes like any other. A group has the same call. |

A path under the prefix is answered with the file it names, found the way
[a name from a client](#a-name-from-a-client) is, so nothing that is hidden or outside
the directory is served. A directory is answered with its index file. When it was asked
for without a slash at its end, the answer is first a 301 to the same path with the
slash, query included, so that the page's relative links are read from the right place.
The path in that redirect is the one the server understood, written again from its
segments, and never the text the client sent: a request for `/\evil.example/../site/docs`
is sent to `/site/docs/`, and not to another site. A directory without an index file is a
404, and there are no listings. A file's name with a slash after it is a 404 too.

The route is `prefix/*static_path`, a catch-all that stands aside for the app's routes:
a file is only looked for where the app has no route for the path, of any method. An
empty prefix serves the directory at the root of the site, beside the app's routes.

The mount answers GET and HEAD. To any other method it is not there: a POST to a path
under it is answered as it would be without the mount, with a 404, and so is an
OPTIONS, even for a file that is there. A path the app has a route for is the app's:
with `POST /echo` and a mount at the root, `GET /echo` is a 405 with
`Allow: POST, OPTIONS`, whether or not the directory has a file of that name. And a path
that names no file is told what any path without a route is told,
`No route for GET /assets/nothing.css`. So an API and its page can share the root of a
site, and the API's clients see nothing of the page.

A directory that holds what users uploaded is not one to mount as it is. An HTML or
SVG file in it would be a page of the site, with the site's cookies. Send such files
with `💾 response filename❗️`, as downloads, or serve them from a host of their own.

Names that begin with a dot are hidden wherever they are under the directory, so
`/.well-known/security.txt` is a 404 while the rest of a site is served. A directory
like that, which is meant to be seen, gets a mount of its own. The more specific route
wins, and nothing else that is hidden comes into view:

```
🗃 app 🔤🔤 🆕🗃 🔤site🔤❗️❗️
🗃 app 🔤/.well-known🔤 🆕🗃 🔤site/.well-known🔤❗️❗️
```

A directory that is not there when it is mounted is a startup problem, like a wrong
pattern: `static /assets: no directory at public`. `⚠️ app❗️` lists it, and `🚀` logs it
and returns 1.

## Browsers

### Calls from another origin

A page may read what comes back from its own origin (its scheme, host and port) and from
no other, unless the other says it may. That word is CORS, and a `🛂` is the policy that
gives it:

```
🆕🛂❗️ ➡️ policy
🌐 policy 🔤https://app.example.com🔤❗️
🚦 policy 🔤PUT🔤❗️
🚦 policy 🔤DELETE🔤❗️
🏷 policy 🔤content-type🔤❗️
⏳ policy 600❗️
🧱 app 🛂 app policy❗️❗️
```

A new policy allows nothing, and every setter returns it:

| Call | Meaning |
|---|---|
| `🆕🛂❗️` | A policy that allows no origin. |
| `🌐 policy origin❗️` | Allows an origin: a scheme, a host and, where it is not the scheme's own, a port, with nothing after it, as in `https://app.example.com` or `http://localhost:5173`. `*` allows every origin. `null`, which is what a page without an origin of its own sends (a file opened from disk, a sandboxed frame), is allowed only when it is named. |
| `🌐🔸📜 policy list❗️` | Allows every origin of a list with commas between them, which is how origins arrive from a setting: `🌐🔸📜 policy 🔧🔸🔡 app 🔤shop.allowedOrigins🔤❗️❗️`. Spaces around an origin are dropped and an empty item is none, so the empty text allows nothing. Each item is taken as `🌐` takes it: one that is not an origin is a startup problem that names it, and `*` allows every origin. |
| `🚦 policy method❗️` | Allows a method on top of GET, HEAD and POST, which a browser sends without asking first. |
| `🏷 policy name❗️` | Allows a request header on top of the few a browser sends without asking. A page that sends JSON needs `content-type`. `*` allows every header. |
| `📤 policy name❗️` | Lets the page read a response header on top of the few it may always read, such as `X-Request-Id`. |
| `🍪 policy flag❗️` | Whether the browser may send the user's cookies with such a request and let the page read the answer. |
| `⏳ policy seconds❗️` | How long a browser may remember the answer to a preflight before it asks again. 0 tells it not to remember; a policy that was told nothing says nothing, and the browser decides. |
| `🏠 policy origin❗️` | Names an origin of the app itself, for an app behind a proxy. See [Which requests are the app's own](#which-requests-are-the-apps-own). |
| `🧐🐇🛂 text❗️` | Whether a text is an origin: a scheme, a host and a port, nothing more. For an app that takes an origin from a setting of its own and puts it somewhere, such as a content security policy. The word `null` is not one. |
| `🛂 app policy❗️` | The middleware, for `🧱 app …❗️`. |

What the middleware does with a request:

- **No `Origin` header, or a request from the app's own pages:** not a call from
  another origin, and the rest of the pipeline runs. How the app's own pages are told
  from everyone else's is [below](#which-requests-are-the-apps-own).
- **An origin the policy does not allow:** a 403 problem, `The origin https://evil.example
  is not allowed`, and nothing behind the middleware runs.
- **A preflight** (an OPTIONS with `Access-Control-Request-Method`, which a browser
  sends by itself before a request that is not a plain one): answered here with a 204
  and `Access-Control-Allow-Origin`, `-Allow-Methods`, `-Allow-Headers`, `-Max-Age`
  when a time was set and `-Allow-Credentials` when they are allowed. When it asks about
  a method or a header that is not allowed, the answer is a 403 that names it.
- **Any other request from an allowed origin:** a method the policy does not allow is a
  403. Otherwise the rest runs, and its answer gains `Access-Control-Allow-Origin`,
  `-Allow-Credentials` and `-Expose-Headers`.

`Access-Control-Allow-Origin` is the request's own origin. When every origin is allowed
it is `*`, and then it is on every answer the middleware hands on, whether or not the
request named an origin, so that a cache in front can give one answer to everyone. Every
other answer that went through the middleware says `Vary: Origin`, refusals included,
since a request from elsewhere would have been answered otherwise. Origins and header
names are compared without regard to case; methods are not.

Three things stop the server from starting, with a line that says which: an origin that
is not one (`https://app.example.com/` has a path); credentials together with every
origin, which would let any page on the web act as the user who is looking at it; and
credentials together with the origin `null`, which comes to the same, since any page can
make its requests say `null` (from a sandboxed frame, or with a form when its referrer
policy is `no-referrer`).

#### Which requests are the app's own

A browser sends an `Origin` with the app's own page's POST as well, so the middleware
has to tell the app's pages from everyone else's. It goes by the first of these that
applies:

1. **What the browser says.** Browsers of the last years send `Sec-Fetch-Site` with
   every request to an HTTPS site, and to `localhost`: `same-origin` is the app's own
   page, and `cross-site` and `same-site` are not, whatever else the request says. A
   page cannot write this header, and a proxy passes it on.
2. **The origins the app was told are its own**, with `🏠 policy origin❗️`, compared
   whole: scheme, host and port.
3. **Where the request was sent.** With proxies that are trusted
   (`server.trustedProxies`), that is the origin the client used, `🏠 r❗️`: the scheme
   they forwarded, and the host they forwarded or passed on in `Host`. It is compared
   whole with the request's `Origin`. Without them it is the `Host` header, compared
   with the host in the `Origin`.

The third is what is left when a browser says nothing and the app has said nothing.
Without a trusted proxy it is the weakest. It leaves the scheme out, since the server
cannot see which one the client used: a page served over plain `http` from the app's host
passes for the app's own, which matters wherever someone on the network can put such a
page in front of a user. `Strict-Transport-Security` and `Secure` cookies are what close
that. And it trusts the `Host` header. **Behind a proxy that writes a `Host` of its
own** (nginx does, unless it is told `proxy_set_header Host $http_host;`), the comparison
is with a name the proxy chose, such as `127.0.0.1:8080`: the app's own pages are
refused, and a page whose origin happens to spell that name is taken for the app's own.
An app that is deployed behind a proxy either tells the server that the proxy is its
own, and has the proxy forward the scheme and the host (see
[Behind a proxy](#behind-a-proxy)), or names its origin, and then neither the `Host` nor
anything forwarded is looked at:

```
🏠 policy 🔤https://shop.example.com🔤❗️
```

#### What this protects, and what it does not

- By itself CORS only tells a browser whether a page may *read* an answer. A request
  from an origin that is not allowed would still run, and have whatever effect it has.
  Here it does not run: the 403 comes before the handler. That is more than the standard
  asks for, and it is what keeps a page on another site from changing things with the
  user's cookies.
- That includes a form which another site posts to the app on purpose: a payment
  provider's return, a sign-on. Such a site has to be allowed by its origin, and may
  then do everything the policy allows.
- It protects nothing against a client that is not a browser. `curl` sends no `Origin`,
  or any it likes. Who may do what is decided by authentication, never by this.
- A request without an `Origin` is let through, and a browser sends none with a link,
  or with an ordinary GET for a page, an image or a script. A GET must not change
  anything. An image, a font or a script that a page asks for with CORS brings an
  `Origin`, and from an origin that is not allowed it gets the 403 where a browser would
  have kept the answer from the page anyway.
- What the server answers by itself before any middleware runs (a 400 for a request it
  cannot read, a 408, 413 or 431, a 503 when it is full) has none of these headers.
- Credentials with `*` or with `null` are refused at the start for a reason. Name the
  origins.

### Headers that make a browser careful

```
🧱 app 🛡 app 🆕🛡❗️❗️❗️
```

A `🛡` is a set of response headers, and its middleware puts each of them on every answer
that does not have that header already, so a handler that sets one of its own keeps it,
and a handler that sets one to the empty text sends its answer without. Add it before
any other middleware, so that it sees every answer, the refusals of the ones after it
included. What the server answers by itself before any middleware runs (a 400 for a
request it cannot read, a 408, 413 or 431, a 503 when it is full) does not have them.

| Call | Meaning |
|---|---|
| `🆕🛡❗️` | `X-Content-Type-Options: nosniff`, so that a file is not run as something its type does not say it is; `X-Frame-Options: DENY`, so that no site, the app itself included, can show the app in a frame and have its buttons clicked there; `Referrer-Policy: same-origin`, so that the addresses of the app's pages are not handed to the sites they link to, while the app's own pages go on saying where they are. (Under `no-referrer` a browser sends `Origin: null` with every form it posts, the app's own included.) |
| `🔖 shield name value❗️` | Sets a header of the set, in place of the one of that name: `🔖 shield 🔤Content-Security-Policy🔤 🔤default-src 'self'🔤❗️`. An empty value takes the header out. |
| `⏳ shield seconds❗️` | `Strict-Transport-Security: max-age=seconds; includeSubDomains`. Zero or less takes it out. To make browsers forget, send `max-age=0` for a while, with `🔖`. |
| `🛡 app shield❗️` | The middleware. |

`Strict-Transport-Security` is not there unless it is asked for. A browser that is told
it will not go back to plain HTTP for the host, or for any host below it, until the time
is up, so every one of them has to speak HTTPS first, and there is no taking it back
sooner. (A browser ignores the header when it arrives over plain HTTP: there it does
nothing.) A `Content-Security-Policy` is not there either: what a page may load is the
app's to say.

## Behind a proxy

A server behind a proxy sees the proxy: its address as the client's, plain HTTP whatever
the client used, and often a `Host` the proxy chose. What the client really was is in
headers the proxy writes, and those are only worth believing when the proxy is your own.
So the server is told how many proxies in front of it are, and which headers they write:

```
GRAPEVINE_SERVER_TRUSTEDPROXIES=1
GRAPEVINE_SERVER_FORWARDEDHEADERS="for, proto"      # what it is unless you say otherwise
```

| Name in `server.forwardedHeaders` | The header | What a request knows from it |
|---|---|---|
| `for` | `X-Forwarded-For` | The client's address: `🌐 r❗️`. |
| `proto` | `X-Forwarded-Proto` | The scheme the client used: `🏠 r❗️` and `🏠🔸🛡 r❗️`. |
| `host` | `X-Forwarded-Host` | The host the client asked: `🏠 r❗️`. |
| `prefix` | `X-Forwarded-Prefix` | The prefix a proxy took off the path: `🛣🔸🧱 r❗️`. |

**Name a header only when your proxy writes it.** A proxy passes on what it does not
write itself, so a header that your proxy leaves alone arrives as the client sent it. A
server that read it would let any client say which host it asked, or which prefix
belongs in front of a redirect. So a header that the list does not name is not read at
all, and the list names two unless you ask for more: the two that a proxy set up as
below writes. A header you add has to be written by the proxy on every request, or
taken off by it where it has nothing to say.

With proxies trusted, a request knows what they forwarded:

| Call | Without trusted proxies | With them |
|---|---|---|
| `🌐 r❗️` | The address of whoever opened the connection. | The client's address, out of `X-Forwarded-For`. |
| `🌐🔸🔌 r❗️` | The same. | The address of whoever opened the connection: the last proxy. |
| `🌐🔸🏙 r❗️` | What that address is counted by. | What the client's address is counted by: see [Rate limits](#rate-limits). |
| `🏠 r❗️` | `http://` and the `Host` header, in lower case. Empty when the request names no host. | The scheme out of `X-Forwarded-Proto`, and the host out of `X-Forwarded-Host` when the list names `host`. Where one of them is not read, was not forwarded, or is not what it should be, the request's own stands: `http`, and the `Host`. |
| `🏠🔸🛡 r❗️` | No. | Whether the forwarded scheme is `https`. |
| `🛣🔸🧱 r❗️` | The empty text. | The prefix a proxy took off the path, out of `X-Forwarded-Prefix`, as in `/app`, when the list names `prefix`. |

Either way an origin is written as a browser writes one in `Origin`: without the
scheme's own port, 80 or 443.

**Which entry is believed.** Each proxy adds what it saw to the end of a header, so with
one proxy trusted the last entry is the one that counts, with two the one before it, and
so on. Whatever stands in front of those was written by the client, or by someone the
server knows nothing of, and is not read: a client that sends `X-Forwarded-For: 6.6.6.6`
through your proxy is still the address the proxy saw. With fewer entries than proxies
the leftmost is taken.

**What is believed.** An address has to be an address (IPv4 or IPv6, with or without a
port and brackets, which are taken off), a scheme `http` or `https`, a host a host with
or without a port, and a prefix a plain path: it begins with a slash and does not end
with one, and between its slashes there are letters, digits and `-._~`, and never `.` or
`..` alone. An entry that is not what it should be ends the walk, and what was found
before it stands. So nothing a proxy passes on by mistake reaches a `Location` header or
a comparison as something it is not.

**The number and the list are promises about your network.** Set the number to the
number of proxies every request really comes through. Too high, and a client writes its
own address and scheme. Too low, or left at zero behind a proxy, and every client has
the proxy's address, which is harmless until something counts by it: see
[Rate limits](#rate-limits). A list that names a header which the proxy does not write
hands that header to the client. The standard `Forwarded` header is not read. nginx,
Caddy and the cloud load balancers write the `X-Forwarded-` ones.

What the framework does with it:

- The CORS middleware tells the app's own pages by the origin the client used: see
  [Which requests are the app's own](#which-requests-are-the-apps-own). For that the
  proxy has to say which scheme the client used, and to pass on the host it asked. In
  nginx:

  ```
  proxy_set_header Host              $http_host;
  proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
  ```

  `$http_host` is the host as the browser sent it, with its port where the site is not
  on the scheme's own: a browser's `Origin` has the port, and the two are compared
  whole. Without that line nginx sends the name it calls the server by, and no page is
  the app's own.

  A proxy that keeps `Host` for itself writes the client's into `X-Forwarded-Host`. Add
  `host` to the list for such a proxy, and make sure that it writes the header:
  `proxy_set_header X-Forwarded-Host $http_host;`. (A proxy that writes the scheme's own
  port after the host all the same, as in `shop.example:443`, does no harm: the port is
  taken off.)

- A static mount's redirect to a directory's slash has the prefix in front of it, where
  the list names `prefix`. The proxy that takes the prefix off writes it:
  `proxy_set_header X-Forwarded-Prefix /app;`.
- A rate limit counts by the client's address, and not the proxy's.

An app that is served under a prefix which the proxy takes off has to put it back where
it writes a path for the browser: `🛣🔸🧱 r❗️` goes in front of the paths it redirects to
and of the links it writes. It is the empty text unless the list names `prefix`.

```
↩️ 🔀🐇📬 🆕🔡 🍿 🛣🔸🧱 r❗️ 🔤/login🔤 🍆 🔤🔤❗️❗️
```

## Rate limits

A `🚰` is a limit: so many requests in each window of so many seconds for one client. The
app makes the middleware from it.

```
🧱 app 🚰 app 🆕🚰 100 60❗️❗️❗️      💭 a hundred a minute for each client
```

A request beyond the count is answered 429, with the seconds until it may come again,
and its handler does not run:

```
HTTP/1.1 429 Too Many Requests
Retry-After: 42
Content-Type: application/problem+json

{"type":"about:blank","title":"Too Many Requests","status":429,"detail":"Too many requests: try again in 42 seconds"}
```

| Call | Meaning |
|---|---|
| `🆕🚰 count seconds❗️` | A limit of *count* requests in each window of *seconds* seconds, 1 to 86400, for each client. |
| `🙋 limit closure❗️` | Counts by what the closure gives for a request, in place of the client: a header, a user, a note of the route. A request for which it gives the empty text is not counted. Returns the limit. |
| `📏 limit most❗️` | How many keys the limit remembers within one window, 100,000 unless this says otherwise. Returns the limit. |
| `🚰 app limit❗️` | The middleware, for `🧱 app …❗️`. |
| `🎟 limit key now❗️` | The decision by itself, for a test: 0 when a request of *key* at *now* (milliseconds) is let through, and otherwise the seconds until it may come again. |

- **Windows are fixed.** The first begins with the first request the limit sees, and
  each next one where the last ended. A key's count starts again with every window, so a
  client that uses its share at the end of one window and again at the start of the next
  is let through twice the count in a short time. Choose the count with that in mind.
- **A client is its address on IPv4, and its network on IPv6.** The key is
  `🌐🔸🏙 r❗️` unless you say otherwise: `203.0.113.7` for a client on IPv4, and
  `2001:db8:0:1::/64` for one on IPv6, which is the first 64 bits of its address. A host
  on IPv6 has every address of such a network to choose from, so a limit for each address
  would be no limit for it. The other side of that: an office or a home behind one such
  network is one client, as it is behind one IPv4 address. An IPv4 address that arrives
  written as an IPv6 one (`::ffff:203.0.113.7`, on a socket that listens for both) is
  the IPv4 address.
- **Behind a proxy that the server does not trust**, the address is the proxy's for
  everyone, and all clients are counted as one: set `server.trustedProxies` (see
  [Behind a proxy](#behind-a-proxy)).
- **Another key**, or a limit for some routes only, is a closure. This one counts by the
  account that a layer before it found for the request's API key and put in the request's
  bag, by the client where it found none, and only on routes that carry a note:

  ```
  🙋 🆕🚰 1000 3600❗️ 🍇🎍🥡 r 📨 ➡️ 🔡
    ↪️ 🏷🔸🛤 r 🔤limit🔤❗️ ➡️ which 🍇
      ↪️ which 🙌 🔤metered🔤 🍇
        ↩️ 🎒 r 🔤account🔤 🌐🔸🏙 r❗️❗️
      🍉
    🍉
    ↩️ 🔤🔤
  🍉❗️ ➡️ metered
  🧱 app 🚰 app metered❗️❗️

  🔖 📥 app 🔤/reports🔤 reports❗️ 🔤limit🔤 🔤metered🔤❗️
  ```

- **Count by what a client cannot make up.** An address is that, and so is an account
  or a user that the app has checked. A header as the client wrote it is not: a client
  that sends a new API key with every request is a new client every time, which is never
  over its count, and each of its keys takes a place in the table. Look the key up
  first, as the layer before the limit does in the example, and count what belongs to
  no account by its address.
- **The counts live in memory, in this process.** Two servers behind one load balancer
  each count for themselves. The table is thrown away with its window, and holds
  `📏 limit most❗️` keys at most: 100,000 unless you say otherwise. A key takes about
  400 bytes of memory, so a table that is full takes 40 MB. A key longer than 64 bytes
  is kept as a number made from it, and takes no more than a short one.
- **When the table is full**, a key it does not hold is let through and is not counted
  until the window ends. The log is warned of it once in each window:

  ```
  WARN  rate limit: the table is full with 100000 keys, and a client it does not hold is let through uncounted until the window ends. Give it room for more
  ```

  The keys that the table holds are counted as before. To refuse what finds no room
  would be worse: whoever can come as that many clients would keep every other client
  out for the rest of the window, and on IPv6 two networks of the size that a provider
  gives one customer hold that many. Give the table room for the clients you expect in a
  window, and more, and act on the warning.
- **Where it goes.** After the request logger, so that what it refuses is logged, after
  whatever finds out what it counts by, and before whatever is costly. A limit that
  makes no sense (no requests, a window of no seconds or of more than a day, room for no
  key) stops the server from starting.

## Compression

`🤐` is what a layer compresses, and the app makes the layer from it:

```
🧱 app 🤐 app 🆕🤐❗️❗️❗️
```

An answer is sent as gzip when all of this holds:

- **The client takes gzip.** Its `Accept-Encoding` names `gzip` or `x-gzip` with a quality
  above nothing, or names neither and takes everything (`*`). What it says of gzip itself
  counts before what it says of `*`, so `gzip;q=0, *` is a client that does not want it.
  A client that sends no `Accept-Encoding` is sent the bytes as they are, and so is one
  whose quality cannot be read (`gzip;q=high`, or anything else that is not 0 to 1 with
  at most three decimals): every client can read the bytes as they are, and only one
  that takes gzip can read gzip.
- **The body is in memory, and has 1,024 bytes to 1 MiB.** A smaller one is not worth the
  header, and a larger one holds a worker for too long.
- **Its type is text**: `text/` anything, `application/json`, `application/xml`,
  `application/javascript`, `image/svg+xml`, whatever ends in `+json` or `+xml`, and the
  types the options were told of. Images, video and archives are compressed already.
- **Its status is not 204, 206 or 304.** A long page that says "not found" is compressed
  like any other.
- **Nobody has spoken for its bytes**: it has no `Content-Encoding` and no
  `Content-Range`, and its `Cache-Control` does not say `no-transform`.
- **The stream is smaller than the body.** Bytes without pattern grow, and are then sent
  as they are.

| Call | Meaning |
|---|---|
| `🆕🤐❗️` | The options as they are without being told anything. |
| `📏 options least most❗️` | The sizes of body that are compressed, in bytes: 1024 and 1048576 unless this says otherwise. Returns the options. |
| `🎭 options type❗️` | One more media type whose answers are compressed, as in `🔤application/x-ndjson🔤`: the type alone, with nothing after it. Returns the options. |
| `🤐 app options❗️` | The middleware, for `🧱 app …❗️`. |

- **`Vary`.** Every answer that could have been compressed says `Vary: Accept-Encoding`,
  compressed or not, beside whatever it varied by already. A cache between the server
  and two clients then keeps the two answers apart, and does not hand gzip to a client
  that cannot read it. An answer that is never compressed (too small, not text) says
  nothing: it is the same for everyone.
- **The tag.** A strong `ETag` says "these very bytes", and a compressed answer has
  others, so its tag becomes a weak one: `"v1"` goes out as `W/"v1"`. A weak tag says
  "this content", which is still true. A client that brings it back in `If-None-Match`
  is told 304 by a handler that uses `♻️`, which compares tags that way.
- **What it costs.** The compressor is written in Emojicode
  ([`packages/deflate`](../deflate/README.md)), and takes about 0.4 milliseconds for
  each kilobyte on the machine it was measured on: 13 ms for a JSON list of 26 kB, which
  becomes 3 kB. That is a worker's time for every answer, and thirty-five times what
  `gzip -1` takes. **Where a proxy in front of the server can compress, let it**, and
  leave this layer out: nginx's `gzip on;` does it in a fraction of the time. The upper
  bound is there so that one large answer does not hold a worker for longer than a third
  of a second: lower it where answers are large and clients are near. Nothing is kept,
  so a client has the server do this work as often as it asks. Where long answers can be
  asked for by anyone, a [rate limit](#rate-limits) belongs in front.
- **Files and streams are sent as they are.** A body that is written while it is sent has
  no bytes to compress until it is over, and a file is sent that way from the disk, and
  answers `Range` by its own bytes. So a directory of static files is not compressed by
  this layer. Compress at a proxy, or keep the files compressed and say so yourself.
- **When not to compress.** An answer that holds a secret (a token against forged
  requests, say) beside text that whoever asked could choose (a search term that is shown
  again) gives the secret away, bit by bit, to someone who can make a browser ask many
  times and can see how long the answers are (the attack is called BREACH). A handler
  takes such an answer out with one header, and it is then sent as it is:

  ```
  🔖 response 🔤Cache-Control🔤 🔤no-store, no-transform🔤❗️
  ```

- **Where it goes.** After the request logger, and before the layers and routes whose
  answers it is to compress: a layer sees the answers of what comes after it. A `HEAD`
  is answered as the `GET` would be, with the compressed length and no body, which costs
  the same compression. Options that make no sense (a least above the most, a most of
  nothing, a type that is no media type) stop the server from starting.

## Who may call

A route says who may call it in a note, and a guard in the pipeline holds every request
to that. Who is calling is told by the token a request brings: a JSON Web Token
(RFC 7519), signed with a key that only the server has.

```
🎖🔸🔧 app❗️ ➡️ tokens                          💭 the app's tokens, as its settings say
🧱 app 🛃 app 🆕🛃 tokens❗️❗️❗️

🔖 📥 app 🔤/admin/stats🔤 stats❗️ 🔤auth🔤 🔤role:admin🔤❗️

📮 app 🔤/login🔤 🍇🎍🥡 r 📨 ➡️ 📬 🚧🚧
  💭 Once the app has made sure who this is:
  🍯🐇💠❗️ ➡️ claims
  🔖 claims 🔤roles🔤 🔡🐇💠 🔤admin🔤❗️❗️
  ↩️ ✅🐇📬 ✍️ tokens 🔤ada🔤 claims 🕰🐇💻❗️❗️❗️
🍉❗️
```

The client sends the token back with every request, as `Authorization: Bearer` and the
token.

### What a route asks

| The route's note `auth` | Who may call |
|---|---|
| none | Anyone. With a guard that was told `🚷`: whoever brings a token that holds. |
| `anyone` | Anyone, whatever the guard was told. |
| `signed-in` | Whoever brings a token that holds. |
| `role:NAME` | A token that holds and has NAME among its `roles`. |
| `scope:NAME` | A token that holds and has NAME in its `scope`. |

`roles` and `scope` are claims of the token: a text of names with spaces between them,
or a JSON list of texts. A name in a note is letters, digits and `-._:`. The note is a
route's like any other ([Notes on routes](#notes-on-routes)), so a group's note guards
every route of the group, whenever each was registered.

A note that is none of these keeps the server from starting, and says which route it is
on:

```
route GET /typo: the note auth is "rol:admin", which no guard understands: anyone, signed-in, role:NAME or scope:NAME
```

### What a refused request is told

| The request | The answer |
|---|---|
| brings no token | 401, with `WWW-Authenticate: Bearer` |
| brings a token that does not hold | 401, with `WWW-Authenticate: Bearer error="invalid_token", error_description="the token has expired"`, or whichever reason it is |
| brings a token that holds and has not the role or the scope | 403, with `WWW-Authenticate: Bearer error="insufficient_scope"` |

Each is a problem document, as RFC 6750 and RFC 9457 write them, and says
`Cache-Control: no-store`. The handler does not run. The answer of a route that asks for
a token says `Vary: Authorization`, let through or not, so that a cache does not hand
one caller's answer to another.

- **The header.** `Bearer` may be written in any case. A request with two
  `Authorization` headers, or with something after the token, brings no token: nobody
  can say which one was meant.
- **On an open route** a token that holds still tells the handler who is calling. One
  that does not hold is passed over, and the request is answered as if it had brought
  none: a page that sends its token everywhere can still read what is open after the
  token has ended.
- **Where the layer goes.** After the CORS layer, so that a page on an origin that is
  allowed can read a refusal, and before whatever it is to guard.

### What a handler is told

A token that holds puts who is calling into the request's bag, for the layers behind the
guard and for the handler:

| In the bag | What |
|---|---|
| `🎒 r 🔤auth.subject🔤❗️` | Whom the token is for: its `sub`. Not there when the token names nobody. |
| `🎒 r 🔤auth.roles🔤❗️` | Its roles, with spaces between. |
| `🎒 r 🔤auth.scope🔤❗️` | Its scope, likewise. |
| `🎒 r 🔤auth.claims🔤❗️` | All its claims, as JSON text. |

Without a token, and with one that does not hold, none of the four is there.

### Tokens

| Call | Meaning |
|---|---|
| `🆕🎖 key❗️` | Tokens that are signed and checked with *key*, a `📇` of 32 bytes or more. |
| `🏷 tokens issuer❗️` | The issuer that is written into tokens (`iss`), and that a token has to name to hold. |
| `👥 tokens audience❗️` | The audience that is written into tokens (`aud`), and that a token has to be for. |
| `⏳ tokens seconds❗️` | How long a token lasts: 3600 seconds unless this says otherwise. |
| `⏱ tokens seconds❗️` | How far the clock that issued a token and the one that checks it may differ: 60 seconds unless this says otherwise. |
| `✍️ tokens subject claims now❗️` | A token for *subject*, issued at *now* (seconds since 1970) and ending a lifetime later, with the members of *claims*, a `💠` that is a JSON object. A member called `sub`, `iat`, `exp`, `iss` or `aud` is left out: whoever fills the claims does not get to say whom the token is for or when it ends. |
| `🔍 tokens text now❗️` | Checks *text* as a token, and gives a `🎗`: `👌 checked❗️` says whether it holds, `🚩 checked❗️` why not, `💠 checked❗️` gives its claims and `🏷 checked name❗️` one of them that is text. |
| `🎖🔸🔧 app❗️` | The app's own tokens, made as its settings say. Call it once the settings are loaded, and keep what it gives. |
| `🆕🛃 tokens❗️` | A guard that checks with those tokens. `🚷 guard❗️` has a route without a note ask for a token, and `🔖 guard name❗️` has the guard read another note than `auth`. Each returns the guard. |
| `🛃 app guard❗️` | The middleware, for `🧱 app …❗️`. `🎖 app tokens❗️` is the same for a guard that was told nothing else. |

A token is checked in this order, and refused for the first thing that is wrong with it.
The reason goes into the refusal as it stands here, and says nothing of the token
itself:

1. Its shape: three parts of base64url with dots between, 8,192 characters at most.
   "the token is longer than 8192 characters", "the token is not three parts with dots
   between", "the token's header cannot be read".
2. Its header. One way of signing is taken, HS256, and a token that says it was signed
   another way, or not at all (`none`), is refused before its signature is looked at.
   "the token is not signed with HS256", "the token's type is not JWT", "the token asks
   for something this server does not understand" (a `crit` member).
3. Its signature, over the first two parts as they came, compared in constant time.
   "the token's signature cannot be read", "the token's signature is not ours".
4. Its claims, which nothing has read until now. "the token's claims cannot be read".
5. Its times. A token has to have an end. "the token has no end", "the token has
   expired", "the token is not good yet" (its `nbf`, or the time it says it was issued,
   is ahead of the clock by more than the clocks may differ).
6. Whom it is from and for, when the tokens were told. "the token is from another
   issuer", "the token is for another audience" (an audience may be a list, of which
   this has to be one).

### The key, and the other settings

| Setting | Default | Allowed | Meaning |
|---|---|---|---|
| `auth.tokenKey` | empty | text of 32 bytes or more | The key that tokens are signed and checked with. Empty: a key made for this run. |
| `auth.issuer` | empty | text | Written into tokens, and asked of them. Empty: neither. |
| `auth.audience` | empty | text | The same for whom a token is for. |
| `auth.tokenSeconds` | 3600 | 1 to 31536000 | How long a token lasts. |
| `auth.leewaySeconds` | 60 | 0 to 600 | How far two clocks may differ. |

- **Whoever has the key can sign a token for anyone.** Give it to the server in its
  environment (`GRAPEVINE_AUTH_TOKENKEY`), and keep it out of a config file that is
  committed. It is never logged. A key shorter than 32 bytes keeps the server from
  starting. The bytes of the text are the key, and a key should be random and not a
  sentence: `openssl rand -hex 32` writes one.
- **Without a key the app makes one for the run**, from 32 random bytes of the system's,
  and says so in its log:

  ```
  WARN  auth.tokenKey is not set: tokens are signed with a key made for this run. They end with it, and no other server takes them
  ```

  That is enough to try something out. Everyone is signed out when the server starts
  again, and of two servers behind one load balancer each refuses the other's tokens.

### What this is not

- **No key pairs.** Tokens are signed with a key that the issuer and the checker share
  (HS256), so whatever can check a token can also make one. Nothing here checks a token
  of an identity provider, which signs with a private key (RS256, ES256).
- **No sign-in.** The app decides who gets a token, and how it makes sure of them. The
  `crypto` package has no function for passwords: see
  [its README](../crypto/README.md).
- **No taking back.** A token holds until it ends, whatever happens to its user
  meanwhile. Keep tokens short-lived.
- **Not secret.** A token is signed, not encrypted: whoever holds one can read its
  claims. Put nothing in them that the caller should not see.

## Errors and problems

Every error the server reports is a problem document (RFC 9457), of the media type
`application/problem+json; charset=utf-8`:

```json
{"type":"about:blank","title":"Bad Request","status":400,"detail":"The request is not valid","errors":{"title":["is required"]}}
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
📥 group 🔤/:id:int🔤 🍇🎍🥡 r 📨 ➡️ 📬 🚧🚧
  📍 r 🔤id🔤 0❗️ ➡️ id
  ↪️ 🔍 store id❗️ ➡️ todo 🍇
    ↩️ 🌸🐇📬 🌸 todo❗️❗️
  🍉
  🚨 🆕🚧🔸🌐 404 🔤No todo with that id🔤❗️
🍉❗️
```

`🆕🚧🔸🌐 status detail❗️` is the short form. `🧨 problem❗️` makes an error from any
problem, as in `🚨 🧨 🚩 🆕🆘 422❗️ 🔤due🔤 🔤is in the past🔤❗️❗️`, and `🆘 error❗️`
gives the problem back. For what a client sent wrong, a
[binder](#binding-and-validation) builds the problem field by field.

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

## Binding and validation

A binder, `🧷`, reads typed values from the body, the query, the route, a form, the
cookies and the headers, checks each one as it reads it, and collects what is wrong. The
handler raises once, and the client gets one 400 that lists everything by field:

```
📮 app 🔤/projects/:project:int/todos🔤 🍇🎍🥡 r 📨 ➡️ 📬 🚧🚧
  🆕🧷 r❗️ ➡️ input
  🔡 input 🔤title🔤 1 200❗️ ➡️ title
  🔢 input 🔤priority🔤 1 5❗️ ➡️ priority
  👌🔸🍬 input 🔤done🔤❗️ ➡️ done
  📌 input❗️
  🔢 input 🔤project🔤 1 9999❗️ ➡️ project
  🔎 input❗️
  🎚🔸🍬 input 🔤notify🔤 🍿 🔤all🔤 🔤owner🔤 🍆❗️ ➡️ notify
  ↪️ 🚩 input❗️ 🍇
    🚨 🧨 input❗️
  🍉
  …
🍉❗️
```

```json
{"type":"about:blank","title":"Bad Request","status":400,"detail":"The request is not valid","errors":{"title":["is required"],"priority":["must be between 1 and 5"],"notify":["must be one of all, owner"]}}
```

**A reader never raises, and one for a required value never gives an optional.** When the
value is missing or wrong it records a message under the field's name and returns
something that is safe to hold and wrong to use. So a handler has to ask `🚩 input❗️`
before it uses what it read, as the example does.

| Call | Reads | Wrong when | Returns when wrong |
|---|---|---|---|
| `🔡 input name least most❗️` | A text, with the spaces, tabs and line breaks around it removed. | It is missing or not text, or has fewer than *least* or more than *most* characters. | The empty text. |
| `🔢 input name low high❗️` | An integer. | It is missing or not an integer, or below *low* or above *high*. | *low* |
| `💯 input name low high❗️` | A number. An integer is one too. | It is missing or not a number, or below *low* or above *high*. | *low* |
| `👌 input name❗️` | A boolean. | It is missing or not a boolean. | 👎 |
| `🎚 input name choices❗️` | A text that is one of *choices*, a list of texts, exactly as it is written there. | It is missing or not one of them. | The first of the choices. |
| `🔡🔸🍬`, `🔢🔸🍬`, `💯🔸🍬`, `👌🔸🍬`, `🎚🔸🍬`, with the same arguments | The same, or no value when the field is absent or, in a body, null. | It is there and wrong. | No value. |

Where a field is read from is the binder's source, which a call changes for the reads that
follow it:

| Call | The fields are | A field's value |
|---|---|---|
| `🌸 input❗️`, which is what a binder starts with | The members of the JSON body. | Has to be of the JSON type asked for: `"7"` is not an integer, and neither is `1.0`. |
| `🔎 input❗️` | The query parameters. | The first value for the name, as text; a name that is sent twice is read once. An integer is digits, with a minus sign in front if it is below zero, and has to fit in 64 bits. A number is what JSON would write. A boolean is `true` or `false`. Nothing may stand around any of them, so `+7`, `7.0` as an integer and `True` are all wrong. An empty value is not there, for everything but a text: a form sends `?done=` for a field that was left blank. |
| `📌 input❗️` | The route's parameters. | As for the query. |
| `📋 input❗️` | The fields of the form in the body, plain or in parts. A file is no field: the request gives those. | As for the query. A checkbox is a boolean only when the form gives it the value `true`: the word a browser sends for a checked box without a value is `on`. |
| `🍪 input❗️` | The cookies, by the names they have. | The first cookie of the name, with its escapes decoded, read as for the query. |
| `🏷 input❗️` | The headers, by their names in any case. | The header's value, read as for the query. One that came more than once is one text, with commas between. |

The other calls:

| Call | Meaning |
|---|---|
| `🆕🧷 r❗️` | A binder for the request. |
| `🚩 input❗️` | Whether anything was wrong. |
| `🚩 input field message❗️` | Records a message of the handler's own under a field: a rule that takes two fields, or something only the store can know. |
| `🧨 input❗️` | The error to raise. It carries the problem. |
| `🆘 input❗️` | The problem itself: a 400 with every message under `errors`. |

What the client is told:

- The messages are `is required`, `must be text`, `must be a whole number`, `must be a
  number`, `must be true or false`, `must be between 1 and 5` (for a number
  `must be between 0.5 and 2.5`, with a whole bound written `1.0`), `must not be empty`
  (a blank text where at least one character is wanted), `must be at least 3 characters`,
  `must be at most 200 characters`, `must be one of low, normal, high`, and
  `is not allowed` for a choice from an empty list. Lengths are counted in characters,
  not bytes, and both bounds of a range are allowed values.
- A reader records one message at most, the first thing it finds wrong. A field that is
  read twice and is wrong twice has two. The fields come in the order they were read.
- The detail is `The request is not valid`, unless the body could not be read.
- **The body is read the first time one of its fields is asked for**, so a handler that
  binds only from the query or the route never reads it. A body that is not JSON, or is
  JSON and not an object, is reported once for the whole request, as the detail: `The body
  is not valid JSON: repeated key at byte 7`, or `The body must be a JSON object`. Its
  fields are then read as absent without a message each, and what is wrong in the query
  and the route is still listed.
- A body that does not say it is JSON is not looked into, and the problem is a **415**
  with the detail `The body must be JSON, and its Content-Type is text/plain`: see
  [The type of a body](#the-type-of-a-body). What is wrong elsewhere is listed beside it
  all the same.
- A form is treated as the body is: read when the first of its fields is asked for, and
  when it cannot be read, reported once for the whole request, with a 400 and
  `The form cannot be read: a field cannot be decoded`, or with a 415 when the body is
  no form.
- Members of the body that no reader asked for are ignored.

A binder reads flat values. A list or an object inside the body is read from `🌸 r❗️` as
before, and what is wrong with it goes in with `🚩 input field message❗️`, so that it is
reported in the same 400.

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

A whole number is held to its range by the framework. What a text of the application's
own has to be, only the application knows, and it says so before the server starts:

```
🔧🔸🔡 app 🔤shop.apiUrl🔤❗️ ➡️ api
↪️ ❎ 🧐🐇🛂 api❗️❗️ 🍇
  ⚠️ app 🆕🔡 🍿 🔤shop.apiUrl must be an origin, and is not: 🔤 api 🍆 🔤🔤❗️❗️
🍉
```

`🚀` then logs that line and returns 1, as it does for a wrong pattern. So load the
settings first and build what is made from them afterwards: declare, `📂`, then the
middleware and the routes, which is the order the Todo sample starts in.

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
| `server.shutdownDelayMs` | 0 | 0 to 600000 | How long the server goes on answering after it was asked to stop, with its health endpoint saying so. See [Health](#health) |
| `server.trustedProxies` | 0 | 0 to 16 | How many proxies in front of the server are its own, which is how far the `X-Forwarded-` headers are believed. See [Behind a proxy](#behind-a-proxy) |
| `server.forwardedHeaders` | `for, proto` | a list of `for`, `proto`, `host`, `prefix` | Which of the `X-Forwarded-` headers those proxies write. The others are not read. |
| `server.shutdownGraceMs` | 10000 | 0 to 600000 | How long a stop waits for requests in progress |
| `limits.requestLineBytes` | 8192 | 256 to 65536 | |
| `limits.headerBytes` | 32768 | 1024 to 1048576 | The request line, the headers, and any blank lines before them. Also the limit for trailers |
| `limits.headerCount` | 100 | 1 to 1000 | |
| `limits.bodyBytes` | 1048576 | 0 to 1073741824 | Bodies are held in memory |
| `limits.jsonDepth` | 64 | 1 to 1024 | How deeply the arrays and objects of a JSON body may nest |
| `limits.jsonValues` | 100000 | 1 to 100000000 | How many values a JSON body may hold. Each takes 150 to 1,500 bytes while the body is handled |
| `limits.formFields` | 1024 | 1 to 100000 | How many fields a form may have, the files of a form in parts counted among them. See [Forms and files](#forms-and-files) |
| `log.level` | `info` | `debug`, `info`, `warn`, `error` or `off` | The lowest level that is written |
| `log.format` | `text` | `text` or `json` | |
| `auth.tokenKey` | empty | text of 32 bytes or more | The key that tokens are signed with. See [Who may call](#who-may-call) |
| `auth.issuer` | empty | text | Whom tokens are from |
| `auth.audience` | empty | text | Whom tokens are for |
| `auth.tokenSeconds` | 3600 | 1 to 31536000 | How long a token lasts |
| `auth.leewaySeconds` | 60 | 0 to 600 | How far the issuer's clock and the checker's may differ |

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

## Health

```
💓 app 🔤/health🔤❗️
💓 app 🔤database🔤 🍇🎍🥡 ➡️ 👌
  💭 What a watcher found when it last asked, and not a question put now.
  ↩️ 💚 watcher❗️
🍉❗️
```

`💓 app path❗️` registers GET *path* and returns the route. What a probe is told:

| When | Status | Body |
|---|---|---|
| All is well | 200 | `{"status":"ok"}`, or with checks `{"status":"ok","checks":{"database":"ok"}}` |
| A check does not pass | 503 | `{"status":"failing","checks":{"database":"failing","queue":"ok"}}` |
| The server has been asked to stop | 503 | `{"status":"stopping"}`, and no check is asked |

Every answer says `Cache-Control: no-store`.

`💓 app name check❗️` adds a check, a `🍇➡️👌🍉` that says whether something the app needs
is well. Checks are listed in the order they were added, one that fails does not keep
the ones after it from being asked, and one that is added after the route is asked too.
**A check runs on the thread that answers the probe**, so it has to be quick and should
not wait for anything. Have something else do the slow asking, and let the check read
what it found.

One probe at a time asks the checks. A probe that arrives while another is still asking
neither waits nor asks too: for a second it is answered with what the checks last said,
and after that with a 503 that names the check that has not come back,
`{"status":"failing","checks":{"database":"slow"}}`. So a check that hangs holds one
worker and makes the server look unwell, which it is, where it would otherwise take one
more worker with every probe.

The endpoint is a route like any other: middleware runs for it, and the request logger
writes a line for each probe.

**Taking a server out of rotation.** A load balancer keeps sending requests until a probe
tells it to stop, and a server that stops at once on SIGTERM refuses a few of them. With
`server.shutdownDelayMs` set, the server goes on answering everything for that long
after it was asked to stop, while the health endpoint says `stopping`; only then does it
stop accepting and let the requests in hand finish. From the moment the stop was asked
for, every answer says `Connection: close`, so that whoever sends the requests makes its
next one on a new connection while the server still takes them, and none is left open to
be cut when the delay is over. Set the delay to a little more than the load balancer's
probe interval times the failures it waits for, and give the orchestrator that much
longer too (see [Running it](#running-it)). A second signal ends the server at once,
during the delay as after it.

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
  with 1 at once. With `server.shutdownDelayMs` above zero the graceful stop begins that
  much later, and until then the server answers as before, but for `Connection: close`
  on every answer: see [Health](#health). A second signal does not wait for the delay.
- **Give the orchestrator longer than the delay and the grace period together.**
  `docker stop` and Kubernetes send SIGKILL after their own timeout. If that is shorter
  than `server.shutdownDelayMs` plus `server.shutdownGraceMs`, requests in progress are
  cut off: use `docker stop -t`, `--stop-timeout` or `terminationGracePeriodSeconds`.
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
- A `📨` and its `📬` belong to one request and need no locking. Make a response for
  each request: the app and its middleware write into the one they are handed (the
  request's ID, `Vary`, a body that was compressed), so a response that a handler kept
  and returned again would carry what was written for the client before.

## Testing an app

`🧪` runs a request through the app without a socket:

```
🆕📨 🔤POST🔤 🔤/todos🔤❗️ ➡️ request
🌸 request 🔤{"title":"Ship it"}🔤❗️
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

### Whether a handler leaks

The compiler and the standard library leak memory in ways that are easy to trip over (the
repository's README lists them), and a handler that leaks on every request ends its
server sooner or later. `📊` lets an application's own tests find out first:

```
📈🐇📊 app 🔤GET /todos HTTP/1.1❌r❌nHost: test❌r❌n❌r❌n🔤 500 2000❗️ ➡️ grown
```

That plays the request's bytes to the app 2,000 times, each over a fresh in-memory
connection, after 500 plays that are not counted, and gives the number of bytes by which
what the program has allocated grew. The plays that are not counted let what is allocated
once reach its size. For a handler that keeps nothing the answer is 0; the Todo sample
allows a kilobyte. `🧠🐇📊❗️` is the count itself, for a test that needs more than the
same bytes over and over: read it, run what is to be measured, read it again.

The count is the allocator's, and it takes a freed block that sits in a thread's cache
for one in use. Run the test program with `GLIBC_TUNABLES=glibc.malloc.tcache_count=0`,
as `build.sh` does, and nothing wanders. Without it, allow a few kilobytes.

## Limits

- No TLS, no HTTP/2, no WebSockets.
- Request and response bodies are held in memory, except responses built with `🌊`. An
  uploaded file is part of a request's body, so `limits.bodyBytes` is the largest a form
  with all its files can be, and there is no reading a file from a form as it arrives.
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
