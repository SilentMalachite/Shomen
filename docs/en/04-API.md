# 04 API

> Canonical text. Japanese translation: [../04-API.md](../04-API.md).

The public types under `Shomen::` and where each is specified. A spec compares the `###` headings below with the public types the compiler finds, so every public type has one heading ([../decisions/20261001-phase8-api-list.md](../decisions/20261001-phase8-api-list.md)). Methods are not compared.

While the version is `0.x`, a minor version may change the Application API ([../decisions/20261001-phase8-version.md](../decisions/20261001-phase8-version.md)).

## Application API

### `Shomen`

- `Shomen::VERSION`: the version `shard.yml` declares ([../decisions/20261001-phase8-version.md](../decisions/20261001-phase8-version.md))
- `Shomen::BUILD_ID`: 32 hex digits that change with every compile ([../decisions/20261001-phase7-etag.md](../decisions/20261001-phase7-etag.md))

### `Shomen::HTML`

- `Shomen::HTML.escape(text)`: escapes HTML special characters ([00-INSTRUCTION.md](00-INSTRUCTION.md#3-views-and-html))

### `Shomen::View`

- `def to_html : String` with `html lang: "en" do … end`: a document. The DSL has a method for each HTML element the specification lists ([00-INSTRUCTION.md](00-INSTRUCTION.md#3-views-and-html))
- `html` `lang`, one `title`, `button` `type`, and `img` `alt` are checked at compile time ([../decisions/20260928-phase1-html.md](../decisions/20260928-phase1-html.md))
- `input`: an `input` needs a label in the same view, a non-empty `"aria-label"` or `"aria-labelledby"`, or `type: "hidden"`; otherwise it fails to compile ([../decisions/20260929-phase2-input-label-check.md](../decisions/20260929-phase2-input-label-check.md))
- `text(value)`, `raw(html)`: escaped text, and HTML written as is ([00-INSTRUCTION.md](00-INSTRUCTION.md#3-views-and-html))
- `embed(fragment)`: puts a `Shomen::Fragment` in the document ([../decisions/20260929-phase4-fragment-view.md](../decisions/20260929-phase4-fragment-view.md))
- `csrf_field(token)`: the hidden `_csrf` field of a form ([../decisions/20260929-phase2-route-csrf-token.md](../decisions/20260929-phase2-route-csrf-token.md))
- `shomen_script`: the `script` element of `shomen.js` ([../decisions/20260929-phase4-script-serving.md](../decisions/20260929-phase4-script-serving.md))

### `Shomen::Fragment`

- `def content : Nil`: the elements of one fragment. Writing `html` in a fragment fails to compile ([../decisions/20260929-phase4-fragment-view.md](../decisions/20260929-phase4-fragment-view.md))
- `to_html`: the fragment's HTML ([../decisions/20260929-phase4-fragment-view.md](../decisions/20260929-phase4-fragment-view.md))

### `Shomen::FragmentCache`

- `Shomen::FragmentCache.new(max_bytes: Shomen::FragmentCache::MAX_BYTES)`: a cache shared by every session in the process. A route uses it through `cached` ([../decisions/20261001-phase7-fragment-cache.md](../decisions/20261001-phase7-fragment-cache.md))

### `Shomen::Route`

- `method GET`, `path "/users/:id"`, `struct Input`, `def call(input : Input) : Shomen::Response`: a route declaration. Registering a route twice fails ([../decisions/20260928-phase1-routing.md](../decisions/20260928-phase1-routing.md))
- `Route.path(id: 1)`: the path helper ([../decisions/20260928-phase1-routing.md](../decisions/20260928-phase1-routing.md))
- `Input` fields from path parameters and a urlencoded form ([../decisions/20260929-phase2-form-input.md](../decisions/20260929-phase2-form-input.md))
- `csrf_token`: the session's CSRF token ([../decisions/20260929-phase2-route-csrf-token.md](../decisions/20260929-phase2-route-csrf-token.md))
- `render(view, status: 200)`: a document. `render(view, status: 422)` redisplays a form ([../decisions/20260929-phase2-validation-status.md](../decisions/20260929-phase2-validation-status.md))
- `render_fragment(fragment, status: 200)`, `target`: a fragment alone, and the id from `Shomen-Target` ([../decisions/20260929-phase4-fragment-request.md](../decisions/20260929-phase4-fragment-request.md))
- `json(value, status: 200)` ([../decisions/20260929-phase4-json-response.md](../decisions/20260929-phase4-json-response.md))
- `redirect(location, status: 303)` ([00-INSTRUCTION.md](00-INSTRUCTION.md#4-responses))
- `sse(store, heartbeat: Shomen::SSE::HEARTBEAT) { fragment }`: an event stream ([../decisions/20260929-phase5-sse-response.md](../decisions/20260929-phase5-sse-response.md))
- `remember(id)`, `must_see`: the id the session remembers after an append, and the id this request must not show a state older than ([../decisions/20261001-phase7-remember-append.md](../decisions/20261001-phase7-remember-append.md))
- `def validator(input : Input) : String`, `def cache_control : String`: a weak `ETag` and 304 on a GET route ([../decisions/20261001-phase7-etag.md](../decisions/20261001-phase7-etag.md))
- `cached(cache, name, *key) { fragment }`: a fragment from a `Shomen::FragmentCache` ([../decisions/20261001-phase7-fragment-cache.md](../decisions/20261001-phase7-fragment-cache.md))

### `Shomen::Response`

- `status`, `content_type`, `body`, `headers` ([00-INSTRUCTION.md](00-INSTRUCTION.md#4-responses))

### `Shomen::SSE`

- The response `sse` returns. An application does not build one. `Shomen::SSE::HEARTBEAT` is the default interval of its comment lines ([../decisions/20260929-phase5-sse-response.md](../decisions/20260929-phase5-sse-response.md))

### `Shomen::Island`

- `Shomen::Island.script "name", "file.js"`: serves an ES module of the application at `/islands/name.js` ([../decisions/20260929-phase5-island-script.md](../decisions/20260929-phase5-island-script.md))

### `Shomen::Server`

- `Shomen::Server.start(host: "127.0.0.1", port: 3000, https: false, reuse_port: false, shutdown_timeout: 25.seconds)`: runs until SIGTERM or SIGINT ([00-INSTRUCTION.md](00-INSTRUCTION.md#5-server), [../decisions/20260929-phase6-shutdown.md](../decisions/20260929-phase6-shutdown.md))
- `https: true` makes the session cookie `Secure` ([../decisions/20260929-phase2-secure-cookie.md](../decisions/20260929-phase2-secure-cookie.md)). `reuse_port: true` lets processes on one host share a port ([../decisions/20260929-scale-reuse-port.md](../decisions/20260929-scale-reuse-port.md))
- `SHOMEN_SECRET`, `SHOMEN_SECRET_VERIFY`, `SHOMEN_ENV=production` ([../decisions/20260929-phase6-production.md](../decisions/20260929-phase6-production.md), [../decisions/20260929-phase6-secret-verify.md](../decisions/20260929-phase6-secret-verify.md))
- `Shomen::Server.new(secret, verify_secret, https)` and `call(context)`: the handler without a port, for specs ([00-INSTRUCTION.md](00-INSTRUCTION.md#tdd))

### `Shomen::Store`

- `Shomen::Store.new(url, poll_interval: 5.seconds, replica: nil)`: SQLite (`sqlite3://`) or Postgres (`postgres://`, `postgresql://`) ([../decisions/20260929-phase3-store-api.md](../decisions/20260929-phase3-store-api.md), [../decisions/20260929-phase6-store-adapters.md](../decisions/20260929-phase6-store-adapters.md), [../decisions/20261001-phase7-replica.md](../decisions/20261001-phase7-replica.md))
- `append(stream, expected_version, events)`: returns the id of the last event appended. A version other than the stream's raises `Shomen::Conflict` ([../decisions/20260929-phase3-store-api.md](../decisions/20260929-phase3-store-api.md), [../decisions/20261001-phase7-remember-append.md](../decisions/20261001-phase7-remember-append.md))
- `read(after, limit: 500)`: the recorded events after an id ([../decisions/20260929-phase3-store-api.md](../decisions/20260929-phase3-store-api.md))
- `last_appended`, `wait_for_append(after, within)`: the highest id appended, and a wait for an append after an id ([../decisions/20260929-phase6-store-adapters.md](../decisions/20260929-phase6-store-adapters.md), [../decisions/20261001-phase7-append-watcher.md](../decisions/20261001-phase7-append-watcher.md))
- `close`: after the consumers stopped ([../decisions/20261001-phase7-consumer-api.md](../decisions/20261001-phase7-consumer-api.md))

### `Shomen::Event`

- `include Shomen::Event` in a struct with `event_type "name"` and `getter at : Time`. A missing or duplicate name fails to compile ([../decisions/20260929-phase3-event-type.md](../decisions/20260929-phase3-event-type.md), [../decisions/20260929-scale-event-evolution.md](../decisions/20260929-scale-event-evolution.md))

### `Shomen::Command`

- `include Shomen::Command` with `def call : Array(Shomen::Event) | Shomen::Rejected` ([../decisions/20260929-phase3-command-result.md](../decisions/20260929-phase3-command-result.md))

### `Shomen::Recorded`

- `id`, `stream`, `version`, `event`: an event as the store keeps it ([../decisions/20260929-scale-event-stream.md](../decisions/20260929-scale-event-stream.md))

### `Shomen::Rejected`

- `Shomen::Rejected.new(messages)`, `messages`: what a command returns for invalid input ([../decisions/20260929-phase3-command-result.md](../decisions/20260929-phase3-command-result.md))

### `Shomen::Projection`

- `Shomen::Projection.new(store)`, `def apply(recorded : Shomen::Recorded) : Nil`, `catch_up(must_see)`, `checkpoint`: a read model in memory ([../decisions/20260929-phase3-projection-api.md](../decisions/20260929-phase3-projection-api.md), [../decisions/20261001-phase7-replica.md](../decisions/20261001-phase7-replica.md))

### `Shomen::Consumer`

- `Shomen::Consumer.new(store)`, `def name : String`, `create_tables(connection)`, `write(recorded, connection)`, `react(recorded)`, `run_once`, `start`, `stop`, `checkpoint`: a projection kept in tables, or a reaction ([../decisions/20261001-phase7-consumer-api.md](../decisions/20261001-phase7-consumer-api.md), [../decisions/20261001-phase7-consumer-batch.md](../decisions/20261001-phase7-consumer-batch.md))
- `read(must_see, within: 2.seconds) { |connection| … }`: waits for the checkpoint, then lends a connection for the read ([../decisions/20261001-phase7-consumer-read.md](../decisions/20261001-phase7-consumer-read.md))

### `Shomen::NotFound`

- Raise it for a 404 HTML document ([../decisions/20260928-phase1-errors.md](../decisions/20260928-phase1-errors.md))

### `Shomen::BadInput`

- Raised for a missing or malformed input; a 400 HTML document ([../decisions/20260929-phase2-form-input.md](../decisions/20260929-phase2-form-input.md))

### `Shomen::Forbidden`

- Raise it to refuse a request; a 403 HTML document ([../decisions/20260929-phase2-csrf.md](../decisions/20260929-phase2-csrf.md))

### `Shomen::Conflict`

- Raised by `append` at a stale version; a 409 HTML document when the route does not handle it ([../decisions/20260929-phase3-conflict-response.md](../decisions/20260929-phase3-conflict-response.md))

### `Shomen::Unavailable`

- Raised when a read cannot reach `must_see` within its limit; a 503 HTML document ([../decisions/20261001-phase7-consumer-read.md](../decisions/20261001-phase7-consumer-read.md))

## Internal

An application does not call these types. They are public only because other files of the framework use them, and they may change in any release.

### `Shomen::CachedFragment`

A fragment rendered before, handed out by `Shomen::FragmentCache`.

### `Shomen::ETag`

Builds and matches the weak `ETag` of a validator.

### `Shomen::AppendSignal`

Wakes the fibers of this process that wait for an append to one database.

### `Shomen::AppendWatcher`

Listens for notifications and polls one database for the highest id.

### `Shomen::StoreAdapter`

The part of `Shomen::Store` that differs by database.

### `Shomen::StoreAdapter::Row`

The type, payload, and time of one event to append.

### `Shomen::StoreAdapter::Stored`

The id, stream, version, type, and payload of one stored event.

### `Shomen::LibSQLite`

The SQLite C functions that `crystal-sqlite3` does not bind.

### `Shomen::SQLiteAdapter`

The store adapter for one SQLite file.

### `Shomen::PostgresAdapter`

The store adapter for one Postgres database.

### `Shomen::ErrorView`

The HTML document of an error response.

### `Shomen::Session`

The session one request carries: its id, CSRF token, and remembered append.

### `Shomen::SessionStore`

Signs and verifies the session cookies.

### `Shomen::Router`

Registers routes and finds the one for a request.

### `Shomen::Router::Entry`

One registered route.

### `Shomen::Route::Hooks`

Generates a route's `handle` from its declaration.

### `Shomen::Island::Script`

The route that serves `shomen.js`.

### `Shomen::Island::Script::Input`

The empty input of that route.

### `Shomen::Connections`

The connections of one server, so a shutdown can close the idle ones.

### `Shomen::Connections::State`

Whether a connection is idle, serving a request, or streaming.

### `Shomen::Listener`

The `HTTP::Server` that tells `Shomen::Connections` which fiber serves which connection.
