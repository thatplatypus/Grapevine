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
| `POST /login` | `{"user":"...","password":"..."}` gives `{"token":"...","expiresIn":3600}`, or a 401. See [Signing in](#signing-in). |
| `GET /admin/stats` | The list's numbers, for a request that brings the token of someone who signed in: `Authorization: Bearer` and the token. |
| `GET /health` | `{"status":"ok"}`, and 503 once the server was asked to stop. |
| `GET /config.json` | Where the page finds the API: `{"api":""}` means where the page came from. |

Whatever is wrong with a request comes back as a problem document (RFC 9457), with what
is wrong with each field under `errors`. The page shows it as it is.

A body has to say that it is JSON, or it is not read and the answer is a 415:

```
curl -X POST localhost:8080/todos -H 'Content-Type: application/json' -d '{"title":"Ship it"}'
```

## Signing in

The list is anyone's. Its numbers, how many todos there are and how many of them are
open, are for whoever has signed in:

```
curl -X POST localhost:8080/login -H 'Content-Type: application/json' -d '{"user":"admin","password":"vineyard"}'
```

```json
{"token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...","expiresIn":3600}
```

```
curl localhost:8080/admin/stats -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'
```

```json
{"total":3,"open":2,"role":"admin"}
```

The token is a JSON Web Token that says the caller is the admin, signed by the server.
The framework's guard reads it: the routes under `/admin` carry the note `auth` with
`role:admin`, and that is all the sample does to close them. The framework's README says
what is checked in a token, and what a request without one is told
([Who may call](../../packages/grapevine/README.md#who-may-call)).

- **The password in this README is for trying the sample out.** A server that still has
  it says so in its log when it starts. Before anyone else can reach the server, give it
  another, and a name if you like: `GRAPEVINE_TODO_ADMINPASSWORD`, `GRAPEVINE_TODO_ADMINUSER`.
  A sample has one user and keeps the password as it was given. An application with
  users of its own keeps a slow hash of each password, and nothing in this repository
  makes one.
- **A wrong name and a wrong password are told the same thing**, a 401 that says "The
  name or the password is not right", and take the same work: each is compared by its
  SHA-256, in constant time. Both are read without the spaces around them.
- **Five tries a minute for each client**, right or wrong. The sixth is a 429 that says
  when to come again. A client is an address, so behind a proxy the server has to be told
  that the proxy is its own ([Behind a proxy](#behind-a-proxy)), or every visitor shares
  the five.
- **Give the server a key**, `GRAPEVINE_AUTH_TOKENKEY`, of 32 bytes or more:
  `openssl rand -hex 32` writes one. Without it the server makes a key when it starts and
  says so in its log. That is enough for a try, and it means that everyone is signed out
  when the server starts again, and that of two servers behind one balancer each refuses
  the other's tokens.
- **A token lasts an hour**, or as many minutes as `todo.tokenMinutes` says, and cannot
  be taken back before it ends.

On the page the sign-in is at the foot. Signed in, the page says who is, shows the
numbers, which follow every change to the list, and offers to sign out.

- **The page keeps the token in its memory and nowhere else**: not in `localStorage`, not
  in a cookie, not in its address. A reload signs out. A script that got into the page
  some other day would find nothing put by for it, and a token that is in no cookie is
  not sent by the browser on its own, so a page on another site cannot use it.
- **The password leaves its field when it has been sent**, right or wrong.
- **A token that the server no longer takes signs the page out**, and the page says so:
  the token has ended, or the server has been started again with another key. The list
  is open to anyone, so a todo that was being added is added all the same.
- **A sign-in waits its turn** with the changes to the list. A todo that is added while a
  sign-in is on its way is sent when it is known who is signed in.

## Settings

Each can be set in `grapevine.json` or with its variable, like the framework's own.

| Key | Variable | Default | Meaning |
|---|---|---|---|
| `todo.capacity` | `GRAPEVINE_TODO_CAPACITY` | 1000 | How many todos the list holds. |
| `todo.webRoot` | `GRAPEVINE_TODO_WEBROOT` | `samples/todo/web` | The directory the page is served from. A directory that is named here and is not there stops the server from starting. Only the default may be missing, and then there is no page. |
| `todo.apiUrl` | `GRAPEVINE_TODO_APIURL` | empty | The origin where the page finds the API. Empty means the page's own. Anything that is not an origin stops the server from starting. |
| `todo.allowedOrigins` | `GRAPEVINE_TODO_ALLOWEDORIGINS` | empty | The origins whose pages may call the API, with commas between them. An item that is not an origin stops the server from starting. `*` opens the API to the pages of every site, and `null` to pages that have no origin, such as a file opened from a disk. |
| `todo.adminUser` | `GRAPEVINE_TODO_ADMINUSER` | `admin` | The name that signs in. |
| `todo.adminPassword` | `GRAPEVINE_TODO_ADMINPASSWORD` | `vineyard` | Its password. A server that still has this one warns of it in its log. |
| `todo.tokenMinutes` | `GRAPEVINE_TODO_TOKENMINUTES` | 60 | How long a sign-in lasts: 1 to 1440 minutes. |

The key that tokens are signed with is the framework's setting, `auth.tokenKey`
(`GRAPEVINE_AUTH_TOKENKEY`): see [Signing in](#signing-in).

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
5. A layer of the sample's own: a header on every answer that comes from behind it,
   which the refusals of the CORS layer do not.
6. **A rate limit** (`🚰`) that counts nothing but sign-ins: five a minute for each
   client. It stands behind the CORS layer, so that a page on another origin can read
   its refusal.
7. **The guard** (`🛃`), which holds every request to what its route's note says: the
   routes under `/admin` ask for the admin's token, and every other route is open.

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
shows the preflights the browser sends before it adds, changes or deletes, and before it
sends a token: signing in works from the other origin too. It does not
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
    proxy_set_header Host              $http_host;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

What the sample needs it for is its own page. The page adds, changes and deletes with
requests that carry its `Origin`, and the CORS layer lets them through because they come
from the sample's own page. Over HTTPS, and on `localhost`, the browser says so itself.
Over plain HTTP under a name of your own it does not, and the server compares the
`Origin` with where the request was sent. Without the first of those lines that is the
`Host` that nginx wrote, `127.0.0.1:8080`, and adding a todo is answered 403. With it,
it is the name in the address bar.

The server reads the two `X-Forwarded-` headers that these lines write, and no other. A
proxy that writes more (the host in `X-Forwarded-Host`, a prefix it took off the path)
is named in `GRAPEVINE_SERVER_FORWARDEDHEADERS`: the framework's README says what each
is for, and why a header that the proxy does not write must not be in that list.

Leave the first variable out when nothing stands in front of the server: with it set, a
client that reaches the server directly writes those headers itself.

## Its tests

- `./build.sh test` runs `tests.🍇`: the routes through `🧪`, with no socket; the page's
  files, the headers and the CORS policy; signing in, what a wrong name and a wrong
  password are told, the limit on tries and what a server with the README's password
  logs; and every kind of request played two thousand times with the allocator's count
  read before and after, since a handler that leaks ends its server sooner or later. It
  also runs `tests/smoke.sh`, which drives the built server with `curl`, signs in with
  it and runs into the limit.
- `./test-e2e.sh` opens the page in a headless Chromium against containers of the image,
  on the API's own origin, on another origin that is allowed, and on one that is not. It
  also holds answers back to see what the page does when a person is quicker than the
  network, uses the page from the keyboard, and has the browser read a long list that
  the server sent compressed. It signs in, with the right password and a wrong one, from
  the page's own origin and from another; signs out; reloads; starts the server again
  under the page to see the page signed out; and looks for the token everywhere a page
  could have put it.

## What it is compared with

[`comparison/aspnet`](../../comparison/aspnet) is the same API in ASP.NET, and the token
table in the repository's README compares the two. Both describe the sample as it was
before it had a page, settings, a pipeline for browsers and a sign-in: the twin still
asks for a key in a header where the sample asks for a token. They are brought up to
date in the last phase of the build-out.
