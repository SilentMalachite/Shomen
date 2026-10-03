# Shomen

[![CI](https://github.com/SilentMalachite/Shomen/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/SilentMalachite/Shomen/actions/workflows/ci.yml)
[![Crystal](https://img.shields.io/badge/Crystal-%3E%3D%201.20-000000?logo=crystal&logoColor=white)](https://crystal-lang.org/)

[English](README.md) | [日本語](README.ja.md)

Shomen is a Crystal web framework. The server returns HTML documents. One route declaration is the contract for a page, and basic accessibility mistakes fail at compile time.

Version 0.1.2. Phases 1 to 8 are in the tree: typed routes, a typed HTML DSL, an HTTP server, form binding, a signed session cookie, CSRF protection, commands and events, an append-only event store on SQLite or Postgres, in-memory projections, HTML fragments, the official `shomen.js`, JSON responses, SSE, islands, and what production needs (a required secret, a Content-Security-Policy, port sharing, and graceful shutdown), and scaling out: an append wakes SSE streams in every process, consumers run projections and reactions outside the request, a session sees its own appends while reads go to a Postgres replica, a GET route's validator answers with 304, and rendered fragments are cached in the process, plus an API list, a records example, and the steps to scale it out. This version is tagged `v0.1.2`.

## Requirements

- Crystal 1.20 or newer
- shards
- The SQLite 3 library (`libsqlite3`)
- Postgres, only for an application that uses it, and to run the Postgres specs
- Google Chrome or Chromium, only to run the browser specs (`shomen.js` and the counter of `examples/hello`). Without it they are pending. `SHOMEN_CHROME` names the binary

The framework shard depends on `sqlite3`, `pg`, and `db` from crystal-lang and will/crystal-pg. `pg` is written in Crystal and needs no C library.

## Run the example

```sh
cd examples/hello
shards install
crystal run src/hello.cr
```

Open <http://127.0.0.1:3000>. `GET /` returns a document that contains `<h1>Hello</h1>`.

The records example is in [`examples/records`](examples/records). [docs/en/05-SCALE-OUT.md](docs/en/05-SCALE-OUT.md) runs it as one process on SQLite and as two processes on Postgres.

## Use it from an application

`shard.yml`:

```yaml
dependencies:
  shomen:
    github: SilentMalachite/Shomen
    version: ~> 0.1.0
```

`examples/hello` depends on the local checkout with `path: ../..` instead.

```crystal
require "shomen"

module Hello
  class ShowView < Shomen::View
    def to_html : String
      html lang: "en" do
        head do
          title "Hello"
        end
        body do
          h1 "Hello"
        end
      end
    end
  end

  class Show < Shomen::Route
    method GET
    path "/"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render ShowView.new
    end
  end
end

Shomen::Server.start
```

`Hello::Show.path` returns `"/"`. Text is escaped. `html` requires a `lang` literal such as `"en"`, and the document needs exactly one `title`. `button` requires `type: "submit" | "button" | "reset"`. `img` requires an `alt` literal, and `alt: ""` is allowed.

The server listens on `127.0.0.1:3000`. A match returns 200 HTML. A bad path parameter returns 400. An unknown path, or `Shomen::NotFound`, returns 404 HTML. An unhandled exception returns 500 HTML with the message escaped; with `SHOMEN_ENV=production` the message is hidden. The exception goes to `Log` under `shomen` in every environment. Every response sets `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`, and a `Content-Security-Policy` (phase 6 below).

## Phases 1 to 8 are what run

Phase 1 builds these:

- HTML elements listed in the specification, plus escaping
- Compile-time checks for `html` `lang`, one `title`, `button` `type`, and `img` `alt`
- Route declarations, registration, and path helpers
- HTTP responses 200, 400, 404, and 500
- `examples/hello`

Phase 2 adds these:

- `Input` fields from a urlencoded form POST. A missing or malformed field is 400
- `render(view, status: 422)` to redisplay a form
- A signed `shomen_session` cookie. The key is `SHOMEN_SECRET`. Without it, a random key lasts until restart. The server keeps no session state, so with a fixed key a session survives a restart. Behind HTTPS, start the server with `Shomen::Server.start(https: true)` so the cookie is also `Secure`
- A CSRF token in the session. `csrf_field(csrf_token)` writes it into a form. POST, PUT, PATCH, and DELETE without the matching `_csrf` return 403
- A form body over 1 MiB returns 413
- A compile-time check that every `input` has a label in the same view: a `label` whose `for:` matches the input's `id:` (both string literals), a wrapping `label`, or a non-empty `"aria-label"` or `"aria-labelledby"`. The view's other methods, its parent views, and included modules count. `type: "hidden"` is exempt. For a submit control, use `button`
- `GET /greeting`, `POST /greeting`, and `GET /greeting/:name` in `examples/hello`

Phase 3 adds these:

- `Shomen::Event`: a struct that declares `event_type "name"`. The name goes into the `type` column, so renaming the Crystal type keeps old rows readable. A missing or duplicate name fails at compile time
- `Shomen::Command`: `call` returns `Array(Shomen::Event)` or `Shomen::Rejected` with messages for a 422 form
- `Shomen::Store.new("sqlite3://./var/shomen.sqlite3")`: `append(stream, expected_version, events)` and `read(after:, limit:)`. The file uses WAL. An append at any version other than the stream's current one raises `Shomen::Conflict` and writes nothing. An unhandled conflict is a 409 HTML document
- `Shomen::Projection`: `apply` each event; `catch_up` applies the events after the checkpoint, including events another process appended. Call it before a view reads, and once before `Shomen::Server.start` to rebuild at startup
- `GET /users/:id/edit`, `POST /users/:id`, and `GET /users/:id` in `examples/hello`

Phase 4 adds these:

- `Shomen::Fragment`: a view of one element. It implements `content`, and writing `html` in it fails at compile time. A document view puts it in with `embed`
- `render_fragment(fragment)`: sends the fragment alone. `render` with a fragment fails at compile time
- `shomen.js`, served at `/shomen.js`. `shomen_script` writes its `script` element. `<a href="..." data-shomen-get="ID">` and `<form method="post" action="..." data-shomen-post="ID">` fetch with the `Shomen-Target: ID` header and replace the element with that id. A redirect loads the new page. Without JavaScript the same link and form load pages as before
- `target`: the id from `Shomen-Target`, or `nil`. A route answers `target ? render_fragment(...) : render(...)`. Every response has `Vary: Shomen-Target`
- `json(value, status = 200)`: `application/json`. The server never chooses JSON on its own, and errors stay HTML documents
- In `examples/hello`, the greeting form is a fragment: "Change" opens it in place, and a 422 replaces only the form

Phase 5 adds these:

- `sse(store) { fragment }`: an event stream. The fragment renders now and again after each append to `store` in this process, and the stream sends its HTML when it changed. With `<div data-shomen-sse="URL">`, `shomen.js` opens the stream, and each fragment replaces the element with the same id inside that element. Appends through other processes reach it too (phase 7 below)
- `Shomen::Island.script "name", "file.js"`: reads an ES module of the application at compile time and serves it at `/islands/name.js`. For each element with `data-shomen-island="name"`, `shomen.js` calls the module's default export with the element. The framework adds no event listener to an element outside an island
- In `examples/hello`, `GET /counter` has a counter island

Phase 6 adds these:

- `Shomen::Store.new("postgres://localhost/app")`: the same store on Postgres. The URL's scheme picks SQLite (`sqlite3`) or Postgres (`postgres`, `postgresql`); commands, events, and projections do not change. An append takes one advisory lock, so ids become visible in order. Without `max_pool_size` in the URL, a process keeps at most 10 connections
- `SHOMEN_ENV=production`: startup fails unless `SHOMEN_SECRET` has at least 32 bytes, and a 500 hides the exception message
- `SHOMEN_SECRET_VERIFY`: a second secret that only verifies. A cookie it verifies is sent again under `SHOMEN_SECRET`, and a form rendered under either secret still posts. Change the secret in three deploys: put the new secret in `SHOMEN_SECRET_VERIFY`; swap the two; remove `SHOMEN_SECRET_VERIFY`
- `Content-Security-Policy: default-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'` on every response. A route that sets its own `Content-Security-Policy` keeps it
- `Shomen::Server.start(reuse_port: true)`: processes on one host share a port. On Linux, set `net.ipv4.tcp_migrate_req=1` so the connections waiting on a process that stops move to the others
- On SIGTERM or SIGINT the server stops accepting, closes idle connections and SSE streams, finishes the requests in progress with `Connection: close`, and `start` returns within `shutdown_timeout` (25 seconds by default). A second signal ends the process at once
- `examples/hello` stays on SQLite. `HELLO_DATABASE_URL=postgres://localhost/hello crystal run src/hello.cr` runs it on an existing Postgres database

Phase 7 builds these:

- An append through any process wakes `sse` streams and `wait_for_append` in every process. On Postgres an append sends a notification, and a process that waits listens for it on one connection of its own, outside the pool. The process also polls each database for the highest id, every 5 seconds unless the store whose wait started it was made with `Shomen::Store.new(url, poll_interval:)`, so a lost notification only adds delay. SQLite uses polling alone. A process listens and polls only after something waited on the store
- `Shomen::Consumer`: a projection kept in tables, or a reaction, run outside the request. Give it a `name`, and override `create_tables(connection)` and `write(recorded, connection)` for the rows it keeps, and `react(recorded)` for a side effect such as mail. Call `start` before `Shomen::Server.start`, and `stop` after it returns, before you close the store. Every process may run the same consumer: a batch commits its writes and the checkpoint together, Postgres locks the checkpoint row and SQLite compares it, so each event's writes apply once, in id order. A side effect runs at least once. A failing event is retried after 1 second, then twice as long each time up to 1 minute, and never skipped. SQL numbered `$1`, `$2`, … in the order the parameters first appear runs on SQLite and Postgres
- `consumer.read(id, within: 2.seconds) { |connection| … }` waits until the consumer's checkpoint reaches `id`, then lends a connection for the read. Past the limit it raises `Shomen::Unavailable`, which the server answers with a 503 HTML document
- `remember store.append(...)`: `append` returns the id of the last event it appended, and `remember` makes the session remember it for 60 seconds in a second signed cookie, `shomen_append`. In the session's later requests, through any process, `must_see` is that id. Pass it on with `projection.catch_up(must_see)` and `consumer.read(must_see) { … }`, and the page never shows a state older than the append. Inside `sse`, `must_see` is the append the stream woke for
- `Shomen::Store.new(url, replica: "postgres://replica/app")`: reads of a Postgres store go to a replica. `catch_up` reads the replica, and when it has not reached `must_see` within 2 seconds, the primary. `consumer.read` reads the replica once its checkpoint reached the id, the primary when only the primary's did, and raises `Shomen::Unavailable` when neither did. Appends, consumer batches, and notifications stay on the primary, and Shomen creates nothing on the replica. The replica URL must name one standby: behind a URL that spreads connections over several, `consumer.read` may read a standby that lags
- `def validator(input : Input) : String` on a GET route: the server calls it before `call`, and sends a weak `ETag` made from it, the build id, the session's CSRF token, and the `Shomen-Target` header, with `Cache-Control: private, no-cache`, or the value of the route's `def cache_control : String`. The 304 sends the same `Cache-Control` as the 200, and a different one set in `call` raises. A matching `If-None-Match` gets a 304 without calling `call`. The build id changes with every compile. Only a GET route may define `validator`, and it must return a `String`; anything else fails to compile
- `cached(CACHE, "notes", notes.checkpoint) { NotesFragment.new(notes) }` in a route, with `CACHE = Shomen::FragmentCache.new(max_bytes: 16 * 1024 * 1024)`: the fragment is rendered once per key and shared by every session in the process, and the one used least recently is dropped past `max_bytes`. Put in the key what the fragment depends on: its inputs, the viewer when the content differs by viewer, and a value that changes with its data. Key values are `String`, `Int32`, or `Int64`. A fragment that contains the request's CSRF token raises

Phase 8 adds these:

- [docs/en/04-API.md](docs/en/04-API.md): the public types and methods an application calls, each with the section or decision that defines it. A spec fails when the list and the code disagree
- [`examples/records`](examples/records): an equipment ledger (register, lend, return) on the parts above: typed routes, forms with CSRF, commands and events, a consumer's tables, `remember`, fragments, SSE, an island, a validator, and a cached fragment
- [docs/en/05-SCALE-OUT.md](docs/en/05-SCALE-OUT.md): the steps from one process on SQLite to two processes on Postgres, with and without a replica. CI runs its commands
- Version 0.1.0 in `shard.yml`

The phase list is in [docs/en/02-PHASES.md](docs/en/02-PHASES.md).

## Specification

English is the canonical text.

| | English | 日本語 |
|---|---|---|
| Specification | [docs/en/00-INSTRUCTION.md](docs/en/00-INSTRUCTION.md) | [docs/00-INSTRUCTION.md](docs/00-INSTRUCTION.md) |
| Architecture | [docs/en/01-ARCHITECTURE.md](docs/en/01-ARCHITECTURE.md) | [docs/01-ARCHITECTURE.md](docs/01-ARCHITECTURE.md) |
| Phases | [docs/en/02-PHASES.md](docs/en/02-PHASES.md) | [docs/02-PHASES.md](docs/02-PHASES.md) |
| Conventions | [docs/en/03-CONVENTIONS.md](docs/en/03-CONVENTIONS.md) | [docs/03-CONVENTIONS.md](docs/03-CONVENTIONS.md) |
| API | [docs/en/04-API.md](docs/en/04-API.md) | [docs/04-API.md](docs/04-API.md) |
| Scale out | [docs/en/05-SCALE-OUT.md](docs/en/05-SCALE-OUT.md) | [docs/05-SCALE-OUT.md](docs/05-SCALE-OUT.md) |

Decision records stay in Japanese under [docs/decisions/](docs/decisions/).

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md). From the repository root:

```sh
shards install
crystal spec
crystal build src/shomen.cr --error-trace
cd examples/hello && shards install && crystal spec
```

Without `SHOMEN_SPEC_POSTGRES` the Postgres specs are pending. To run them, set it to a Postgres URL whose user may create databases, such as `SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec`. Each example creates a database and drops it.

The records example has its own specs: `cd examples/records && shards install && crystal spec`. With `RECORDS_SPEC_POSTGRES` set to a URL like the one for `SHOMEN_SPEC_POSTGRES`, they run on a new Postgres database, which they drop at the end.

On every pull request and push to `main`, GitHub Actions ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs `crystal tool format --check`, the build, `crystal spec` with a Postgres 17 service and headless Chrome (so no spec is pending there), the `examples/hello` specs, the `examples/records` specs on SQLite and on Postgres, and the two-process commands of [docs/en/05-SCALE-OUT.md](docs/en/05-SCALE-OUT.md), without and with a replica URL.

`crystal build` writes `./shomen`. Do not commit that binary.

## License

[MIT](LICENSE). Copyright 2026 Silent Malachite.
