# The Todo sample

A small application on [Grapevine](../../packages/grapevine/README.md): a JSON API for a
to-do list, and a page of plain HTML, CSS and JavaScript that uses it. The server serves
both, so one command and a browser are all it takes:

```
docker build -t grapevine .
docker run --rm -p 8080:8080 grapevine
```

Then open <http://localhost:8080/>.

## What is in it

| File | What it is |
|---|---|
| `main.🍇` | The entry point: the settings, then the pipeline, then `🚀`. |
| `startup.🍇` | Builds the app. Shared by `main.🍇` and the tests, like `Program.cs`. |
| `todos.🍇` | The todo, the store that holds them, and the controller for `/todos`. |
| `tests.🍇` | Tests that run the app in memory, and play requests of many kinds until a leak would show. |
| `web/` | The page: `index.html`, `style.css`, `app.js` and an icon. No framework and no build step. |

The sample's `.🍇` files are enough to run it. The page is looked for in
`samples/todo/web`, from the directory the server is started in. Where that is not
there, the server says so in its log, serves the API alone, and answers `/` with a line
of plain text.

## The API

| Route | Answer |
|---|---|
| `GET /todos`, `GET /todos?done=true` | The list, or the part of it that is done or not. |
| `POST /todos` | `{"title":"..."}` makes a todo: 201, with its `Location`. A full list is a 409. |
| `GET /todos/:id` | One todo, or a 404. |
| `PUT /todos/:id` | `{"title":"...","done":true}`, either or both. |
| `DELETE /todos/:id` | 204, or a 404. |
| `GET /hello/:name`, `POST /echo` | A greeting as JSON, and the body sent back. |
| `GET /admin/stats` | The list's numbers, for a request that brings `x-api-key: vineyard`. |
| `GET /health` | `{"status":"ok"}`, and 503 once the server was asked to stop. |
| `GET /config.json` | Where the page finds the API: `{"api":""}` means where the page came from. |

Whatever is wrong with a request comes back as a problem document (RFC 9457), with what
is wrong with each field under `errors`. The page shows it as it is.

A body has to say that it is JSON, or it is not read and the answer is a 415:

```
curl -X POST localhost:8080/todos -H 'Content-Type: application/json' -d '{"title":"Ship it"}'
```

## Settings

Each can be set in `grapevine.json` or with its variable, like the framework's own.

| Key | Variable | Default | Meaning |
|---|---|---|---|
| `todo.capacity` | `GRAPEVINE_TODO_CAPACITY` | 1000 | How many todos the list holds. |
| `todo.webRoot` | `GRAPEVINE_TODO_WEBROOT` | `samples/todo/web` | The directory the page is served from. A directory that is named here and is not there stops the server from starting. Only the default may be missing, and then there is no page. |
| `todo.apiUrl` | `GRAPEVINE_TODO_APIURL` | empty | The origin where the page finds the API. Empty means the page's own. Anything that is not an origin stops the server from starting. |
| `todo.allowedOrigins` | `GRAPEVINE_TODO_ALLOWEDORIGINS` | empty | The origins whose pages may call the API, with commas between them. An item that is not an origin stops the server from starting. `*` opens the API to the pages of every site, and `null` to pages that have no origin, such as a file opened from a disk. |

## What the pipeline is made of

In the order a request meets them:

1. **The request logger**, first, so that it sees every answer.
2. **Compression** (`🤐`): an answer of a kilobyte or more that is text goes out as gzip
   to a client that takes it, which a list of twenty todos or so is. The page's own
   files do not: a file is sent from the disk as it is. The framework's README says
   what that costs, and that a proxy in front does it far faster.
3. **Security headers** (`🛡`): the defaults, and a content security policy made for this
   page. Everything comes from the page's own origin, calls go to the API, and nothing
   else is allowed. The page has no script or style written into it, so the policy need
   not allow any.
4. **CORS** (`🛂`): a page on an origin that `todo.allowedOrigins` names may use the
   whole API. A request from any other origin is refused with a 403 before it reaches a
   handler. A request from the sample's own page, or from no page at all, goes through.
5. The sample's own two layers: a header on every answer that comes from behind them,
   which the refusals of the CORS layer do not, and the API key for the routes that are
   noted as `admin`.

Then the routes, and last the page: the directory is mounted at the root of the site,
and the mount stands aside for the routes. A file is looked for only where the API has no
route for the path, so `GET /echo`, which the API takes a POST on, is a 405 and not a
file that is not there.

## The page on another origin

The same program can be the page's server on one origin and the API on another. The
page's server tells the page where the API is, and the API is told whose pages may call:

```
docker run --rm -p 8081:8080 -e GRAPEVINE_TODO_ALLOWEDORIGINS=http://localhost:8080 grapevine
docker run --rm -p 8080:8080 -e GRAPEVINE_TODO_APIURL=http://localhost:8081 grapevine
```

Open <http://localhost:8080/>. The footer names the API at port 8081, and the API's log
shows the preflights the browser sends before it adds, changes or deletes. It does not
ask every time: the API lets it remember an answer for ten minutes, so a second change
to the same todo goes without one. Start the first one without its variable, and the
page says that it cannot reach the API: the API refuses it, and nothing the page sends
changes the list.

The page asks its own server where the API is before it sends anything else, and what a
person does in the meantime waits for the answer. A page that cannot find out says so
and sends nothing.

## Behind a proxy

A server behind a proxy sees the proxy. It believes what the proxy says of the client
once it is told that the proxy is its own:

```
docker run --rm -p 8080:8080 -e GRAPEVINE_SERVER_TRUSTEDPROXIES=1 grapevine
```

And the proxy has to say it. In nginx:

```
location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $http_host;
}
```

What the sample needs it for is its own page. The page adds, changes and deletes with
requests that carry its `Origin`, and the CORS layer lets them through because they come
from the sample's own page. Over HTTPS, and on `localhost`, the browser says so itself.
Over plain HTTP under a name of your own it does not, and the server compares the
`Origin` with where the request was sent. Without the forwarded headers that is the
`Host` that nginx wrote, `127.0.0.1:8080`, and adding a todo is answered 403. With them
it is the name in the address bar.

Leave the variable out when nothing stands in front of the server: with it set, a client
that reaches the server directly writes those headers itself. The framework's README
says what is believed, and how far.

## Its tests

- `./build.sh test` runs `tests.🍇`: the routes through `🧪`, with no socket; the page's
  files, the headers and the CORS policy; and every kind of request played two thousand
  times with the allocator's count read before and after, since a handler that leaks
  ends its server sooner or later. It also runs `tests/smoke.sh`, which drives the built
  server with `curl`.
- `./test-e2e.sh` opens the page in a headless Chromium against containers of the image,
  on the API's own origin, on another origin that is allowed, and on one that is not. It
  also holds answers back to see what the page does when a person is quicker than the
  network, uses the page from the keyboard, and has the browser read a long list that
  the server sent compressed.

## What it is compared with

[`comparison/aspnet`](../../comparison/aspnet) is the same API in ASP.NET, and the token
table in the repository's README compares the two. Both describe the sample as it was
before it had a page, settings and a pipeline for browsers. They are brought up to date
in the last phase of the build-out.
