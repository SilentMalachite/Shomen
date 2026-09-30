# 00 Instruction — Shomen

> Canonical text. Japanese translation: [../00-INSTRUCTION.md](../00-INSTRUCTION.md).

## Conclusion

Shomen is a web framework written in Crystal. By default the server returns an HTML document. JavaScript belongs only on an island. The contract for a page and its API is one route declaration. The source of truth for the domain is an append-only event. A basic accessibility violation is a compile error. An application grows by running more identical processes on one database.

The first thing to build is typed routes, typed HTML, a development server, and specs. An ORM compatibility layer, realtime for every screen, and a plugin system are out of scope.

## Premises

- Language: Crystal `>= 1.20`
- Packages: shards
- Tests: Crystal `spec`
- HTTP: the standard library `HTTP::Server`
- An ECR template string is not the source of a view. HTML is a Crystal expression
- No dependency on Amber, Lucky, Kemal, Marten, or Spider-Gazelle
- This file and `docs/en/` are canonical. Chat history is not
- Expected use: business screens, records, and applications that need accessibility. An application starts as one process on SQLite. It grows to many identical processes behind a load balancer, on one Postgres primary and its replicas. Its routes, views, commands, and events do not change on the way
- Scale model: one deployable application, not a set of services. A process keeps no state that another process needs. The session is a signed cookie, and the facts are in the database. The database is the only backing service an application requires. A load balancer sits in front once there is more than one host (`docs/decisions/20260929-scale-target.md`)

## Scope

### In scope

- Generate the handler, path helper, and input type from a route declaration
- A typed HTML DSL
- Document responses and HTML fragment responses
- A minimum set of compile-time accessibility checks
- A development server. Recompilation may be manual or a simple watch. Advanced HMR is out of scope
- A minimal core for commands, events, and a read model
- SQLite as the first persistence, and Postgres for many processes (phase 6)
- A minimal session cookie
- Optional screen updates over SSE. A permanent WebSocket connection is out of scope
- One official island runtime file, zero dependencies, aiming at about 10KB
- Many identical processes on one database (phases 6–7): a required secret, port sharing, graceful shutdown, asynchronous event consumers, notification across processes, HTTP caching, and reads from replicas

### Out of scope

- Rails, Phoenix, or Lucky compatibility
- GraphQL, tRPC, RSC
- A SPA or a client router by default
- An admin UI, a theme engine, a plugin marketplace
- A Devise-sized authentication suite (a minimal session only)
- Treating an ActiveRecord-style general model layer as the source of truth
- Splitting the app on the assumption of microservices
- A required backing service besides the database, such as Redis, a message broker, or a separate cache
- Database sharding and writes from more than one region
- Embedding a JavaScript bundler in the framework build
- Edge execution as the default

## Specification

### 1. Package layout

The repository root is the framework.

```
shard.yml
src/shomen.cr                 # library entry
src/shomen/
  route.cr
  router.cr
  response.cr
  sse.cr                      # phase 5
  view.cr
  fragment.cr
  html.cr
  a11y.cr
  session.cr
  command.cr
  event.cr
  store.cr
  projection.cr
  consumer.cr                 # phase 7
  island.cr
  assets/shomen.js
  server.cr
spec/
examples/hello/               # minimal app. Features do not live in the framework
docs/
```

`shard.yml` names the shard `shomen`. The license is MIT.

Shards the framework may depend on at the start:

- None (phases 0–2)
- `crystal-sqlite3` (shard `sqlite3`) and `crystal-db` (shard `db`), which it builds on (phase 3 onward, added when it becomes necessary)
- `crystal-pg` (shard `pg`) (phase 6 onward, `docs/decisions/20260929-scale-postgres-shard.md`)

Any other shard requires a decision file in `docs/decisions/` first.

### 2. Route declarations

One route class is one endpoint. A macro or an annotation fixes the HTTP method and the path.

Required shape (the implementation may choose syntax details; the meaning stays):

```crystal
class Hello::Show < Shomen::Route
  method GET
  path "/"

  struct Input
  end

  def call(input : Input) : Shomen::Response
    render Hello::ShowView.new
  end
end
```

Rules:

- A concrete route class is registered at startup or at compile time. A missing registration fails startup or compilation
- A `:id` in `path` binds to the `Input` field of the same name. A failed conversion is 400
- Registering the same method and path twice fails compilation or startup
- A path helper is callable on the route class (`Hello::Show.path` returns `"/"`)
- A response is an HTML document or an HTML fragment. JSON is sent only when the route asks for it with `json` (phase 4)

### 3. Views and HTML

A view is an object that inherits `Shomen::View` and has `to_html : String`.

The DSL provides methods that correspond to HTML elements. At minimum:

- Document: `html`, `head`, `title`, `meta`, `body`
- Landmarks: `header`, `main`, `footer`, `nav`
- Structure: `h1`–`h3`, `p`, `div`, `span`, `ul`, `ol`, `li`, `a`
- Forms: `form`, `label`, `input`, `button`, `textarea`
- Other: `img`

Compile-time checks, implemented with macros:

- An `html` document requires `lang`
- A `button` requires `type` (`submit`, `button`, or `reset`)
- An `img` requires `alt`. An empty string is allowed. A decorative image writes `alt: ""` explicitly
- An `input` fails unless the same view has a matching `label` (`for` or a wrapper) or an `aria-label`
- A document view that returns `html` has one `title`

Raw HTML is inserted only through `raw`. Ordinary text is escaped.

### 4. Responses

`Shomen::Response` has at least:

- status
- content_type
- body
- headers

Helpers:

- `render(view)` returns 200 and `text/html; charset=utf-8`
- `render_fragment(view)` returns 200 and a fragment, without a document `<html>`
- `json(value, status = 200)` returns `application/json` with `value.to_json`. The server never chooses JSON on its own
- `sse(store, heartbeat = 15.seconds) { fragment }` returns an event stream (`text/event-stream`). It renders the fragment now and again after each append to `store` in this process, and sends its HTML whenever it changed. Appends in other processes reach it in phase 7 (`docs/decisions/20260929-phase5-sse-response.md`)
- `redirect(path, status = 303)`

The server attaches security headers by default.

- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: no-referrer`
- `X-Frame-Options: DENY`

From phase 6 the server also attaches `Content-Security-Policy: default-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'`. When the route's response already has a `Content-Security-Policy`, the server keeps it (`docs/decisions/20260929-phase6-csp.md`).

### 5. Server

`Shomen::Server` wraps `HTTP::Server`.

- Default bind: `127.0.0.1:3000`
- Match the route, build `Input`, call `call`, write the `Response`
- An unmatched request is a 404 HTML document, not empty JSON
- An unhandled exception is a 500 HTML document. Development may show the message. With `SHOMEN_ENV=production` the document hides it. The exception goes to the log in every environment (phase 6, `docs/decisions/20260929-phase6-production.md`)
- Several identical processes on one host share a port through `reuse_port: true` (phase 6, `docs/decisions/20260929-scale-reuse-port.md`)
- On SIGTERM or SIGINT the server stops accepting connections, closes idle keep-alive connections, finishes the requests in progress with `Connection: close` within a time limit, and exits (phase 6, `docs/decisions/20260929-scale-graceful-shutdown.md`)

### 6. Sessions (phase 2)

- Cookie name: `shomen_session`
- HttpOnly, Secure on HTTPS, SameSite=Lax
- The value is signed. The secret is the environment variable `SHOMEN_SECRET`. With `SHOMEN_ENV=production`, startup fails when the secret is unset or shorter than 32 bytes (phase 6, `docs/decisions/20260929-scale-production-secret.md`). Outside production a missing secret falls back to a random one (`docs/decisions/20260929-phase2-secret-fallback.md`)
- `SHOMEN_SECRET_VERIFY`, when set, is a second secret that verifies a cookie and a CSRF token and never signs. A cookie it verifies is reissued under `SHOMEN_SECRET`. Changing the secret takes three deploys. It ends only the sessions not used between the second and the third, and the forms rendered before the second and still unsent at the third (phase 6, `docs/decisions/20260929-scale-secret-rotation.md`)
- The contents are a small key-value map. It lives in the signed cookie or in the database, not in one process's memory. In phase 2 the session holds only its id and values derived from it (the CSRF token); the map, with its size limit and expiry, comes with the API that lets a route write to the session (`docs/decisions/20260929-phase2-session-store.md`)
- A full authentication suite (registration, password reset, OAuth) is out of scope

### 7. Commands and events (phase 3)

```crystal
struct RenameUser
  include Shomen::Command
  getter user_id : String
  getter name : String
end

struct UserRenamed
  include Shomen::Event
  getter user_id : String
  getter name : String
  getter at : Time
end
```

Rules:

- A command validates and returns a sequence of events. It does not publish an API that UPDATEs a database row directly
- Events are append-only. There is no update or delete API
- An event belongs to one stream. A stream is one thing that changes over time, such as one user. Its name is a string (`"user-42"`)
- A stream's events are numbered from 1 by `version`. An append names the version it expects the stream to be at. When the stream is at any other version, the store appends nothing and raises `Shomen::Conflict`. The store does not retry (`docs/decisions/20260929-scale-event-stream.md`)
- `id` is the order across every stream. A reader that has seen `id` N never later finds a new event whose `id` is N or lower
- A stored event is never rewritten. A change to an event's shape adds a new event type, or a field with a default. The `type` column holds a name the event type declares, so renaming the Crystal type does not orphan stored rows (`docs/decisions/20260929-scale-event-evolution.md`)
- A read model is built by applying events. The first store is one SQLite file
- A projection builds a read model. It applies events in `id` order and records a checkpoint, the last `id` it applied. An in-memory projection catches up before a view reads it, by applying every event after its checkpoint, so it sees events that another process appended. A projection kept in tables (phase 7) is updated by its consumer, and a reader waits for it (section 10) (`docs/decisions/20260929-scale-projection-checkpoint.md`)
- Table (Postgres uses `BIGINT` for the integer columns, so both adapters read them as `Int64`):

  ```
  events(
    id      INTEGER PRIMARY KEY,  -- order across streams, Int64
    stream  TEXT    NOT NULL,
    version INTEGER NOT NULL,
    type    TEXT    NOT NULL,
    payload TEXT    NOT NULL,     -- JSON
    at      TEXT    NOT NULL,     -- UTC, RFC 3339
    UNIQUE (stream, version)
  )
  ```

- Domain events in the body stay separate from framework-internal logs

### 8. Fragment updates and islands (phases 4–5)

- Besides a normal HTML document, a route can return the same view as a fragment
- The official JavaScript is one file, `shomen.js`. Attributes are only `data-shomen-*`
- The default transport is `fetch`. SSE is opt-in: a GET route answers with `sse`, and an element with `data-shomen-sse="URL"` receives its fragments. Each fragment replaces the element with the same `id` inside that element (phase 5, `docs/decisions/20260929-phase5-sse-script.md`)
- WebSocket is not built
- An island loads JavaScript only on an element with `data-shomen-island="name"`. `Shomen::Island.script "name", "file.js"` serves the application's module at `/islands/name.js`, and `shomen.js` calls its default export with the element (phase 5, `docs/decisions/20260929-phase5-island-script.md`)

### 9. Error model

User-facing HTML and internal exceptions stay separate.

- `Shomen::NotFound`
- `Shomen::BadInput`
- `Shomen::Forbidden` (phase 2 onward)
- `Shomen::Conflict` (phase 3 onward). An unhandled one is a 409 HTML document
- `Shomen::Unavailable` (phase 7 onward). A read that cannot reach the `id` it must see within the limit raises it. An unhandled one is a 503 HTML document

Errors are HTML documents, also for a route that returns JSON. There is no JSON error format (`docs/decisions/20260929-phase4-json-response.md`).

### 10. Scale out (phases 6–7)

- Identical processes run behind a load balancer. Any process can serve any request
- Each process holds a bounded pool of database connections. The database URL sets its size
- A consumer is a projection or a reaction that runs outside the request. It reads the events after its checkpoint in batches. A batch commits its database writes and the new checkpoint in one transaction, and only when no other process moved the checkpoint first, so two processes never apply the same event to the database. Postgres locks the checkpoint row for the batch. SQLite runs side effects before a short write transaction that compares the checkpoint. A side effect outside the database, such as mail or an HTTP call, runs at least once, so a reaction tolerates a repeat (`docs/decisions/20260929-scale-consumers.md`)
- When a process dies during a batch, its transaction rolls back, and another process continues from the stored checkpoint
- A consumer that fails on an event retries it with a growing delay and does not skip it. Other consumers keep going
- After an append commits, the Postgres adapter sends a notification that carries the new highest `id`. Consumers and SSE streams in every process wake on it. Each also polls at an interval, so a lost notification only adds delay. SQLite has no notification and uses polling alone (`docs/decisions/20260929-scale-notify.md`)
- A projection kept in tables is updated only by its consumer. A request that must see a given `id` waits, with a limit, until that projection's checkpoint reaches it. When the limit passes, it raises `Shomen::Unavailable` rather than show an older state. The session forgets that `id` after a time limit, so one stuck event does not make every later page unavailable
- Reads may go to a replica. After a request appends events, a later request in the same session, while the session remembers that append's `id`, never shows a state older than that append, whichever process serves it. The wait above applies, and the primary serves the read when a replica stays behind (`docs/decisions/20260929-scale-read-your-writes.md`)
- A GET route may supply a validator, a string computed from its `Input` and the read model. The server combines it with the build id and the session's CSRF token, sends the result as a weak `ETag`, and answers a matching `If-None-Match` with 304 without calling the view (`docs/decisions/20260929-scale-etag.md`)
- A rendered fragment may be kept in a bounded in-process cache. Its key includes everything the fragment depends on: its inputs, the viewer when the content differs by viewer, and a value that changes with the data it shows, such as a stream's version or a projection's checkpoint. Nothing is invalidated by hand. Every session in the process shares the cache, so caching a fragment that contains the current CSRF token raises (`docs/decisions/20260929-scale-fragment-cache.md`)
- Sharding, writes from more than one region, and scheduled or delayed jobs are not part of this section

## TDD

Tests come first, or together with the implementation. A phase is not done when the implementation landed without tests.

Required specs (phases 0–1):

1. `GET /` returns 200 and HTML
2. An unknown path returns 404 HTML
3. HTML special characters are escaped
4. A view whose `button` has no `type` fails to compile (assert a failed `crystal build`, or a macro spec)
5. A path helper returns the string declared by the route
6. Registering a route twice fails

Tests for later phases are the acceptance criteria in [02-PHASES.md](02-PHASES.md).

A test does not occupy a real network port. Use an ephemeral port for `HTTP::Server`, or call the handler directly.

## Constraints

- Meet the acceptance criteria by the shortest path, ahead of extra design improvements
- The public API stays under `Shomen::`
- A filename matches the feature name
- No color codes or design-token system in phases 0–3
- No internationalization system in phases 0–3. The view sets the document `lang`
- No Windows-only API
- A dependency version writes its lower bound in `shard.yml`

## Acceptance

This list is the point at which the repository can start. It is not the definition of a finished framework.

The instruction document is complete when:

- [ ] `AGENTS.md` and `CLAUDE.md` point at the same canonical spec
- [ ] An agent can start phase 0 without guessing
- [ ] Exclusions are written down
- [ ] Language, tests, and directories are fixed

The framework implementation is complete when every phase in [02-PHASES.md](02-PHASES.md) is met.
