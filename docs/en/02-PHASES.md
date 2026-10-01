# 02 Phases

> Canonical text. Japanese translation: [../02-PHASES.md](../02-PHASES.md).

## Current phase

**Phase 7 — scale out**

Phase 6 acceptance is met. When phase 7 acceptance is met, stop and wait for the next instruction.

---

## Phase 0 — repository skeleton

Build:

- `shard.yml`
- `src/shomen.cr` (a `require` is enough, and it defines an empty `Shomen` module)
- `src/shomen/version.cr` (`0.0.0`)
- `spec/spec_helper.cr`
- `spec/shomen_spec.cr` (VERSION is not empty)
- `.gitignore` (`/lib/`, `/bin/`, `.shards/`, `*.dwarf`, `var/`)

Acceptance:

- `shards install` succeeds
- `crystal spec` is green
- Framework features (server, DSL) do not exist yet

---

## Phase 1 — routes, HTML, and the server

Build:

- HTML DSL (the element set in specification section 3)
- Text escaping
- Accessibility macros for `button@type`, `img@alt`, and a document's `lang` and `title`
- Route declaration, registration, and a path helper
- Server, with 200 / 404 / 500
- `examples/hello` (`GET /` returns a document that contains `<h1>Hello</h1>`)

Acceptance:

- Items 1–6 in the TDD section of the instruction are met
- `crystal run` on `examples/hello` returns HTML locally
- The framework shard has no external dependencies

---

## Phase 2 — forms and sessions

Build:

- Bind `Input` from a `form` POST (urlencoded)
- On a validation error, re-render the same form with 422
- A signed session cookie
- CSRF: a token tied to the session. A POST with a mismatch is 403
- Compile-time label checks for `input` (a `for`, a wrapper, or `aria-label` in the same view). Phase 1 emits the `input` element and does not run this check

Acceptance:

- An example with one form redisplays the value after submission
- A POST without CSRF is 403
- A response with no session carries `Set-Cookie`

---

## Phase 3 — commands, events, and SQLite

Build:

- Command and Event types
- An append-only SQLite store with the `events` table in specification section 7 (stream, version, and an `id` across streams)
- An append at any version other than the stream's current one raises `Shomen::Conflict`. The server answers an unhandled one with 409 HTML
- An in-memory projection with a checkpoint. It catches up before a view reads it
- Rebuild the read model at startup
- Example: changing a name appends one event row

Acceptance:

- Handling the same command twice yields two event rows (not an overwrite)
- The read model is restored after a restart
- Two appends to one stream at the same expected version: one succeeds, and the other raises `Shomen::Conflict` and adds no row
- An append that expects a version ahead of the stream raises `Shomen::Conflict` and adds no row
- Two processes on one SQLite file: appends from both succeed, one waiting for the other, and a projection in one sees an event appended by the other once it catches up
- Many fibers in one process append to one SQLite file at once: every append succeeds
- Store does not import HTML
- Commands, events, and projections do not name SQLite

---

## Phase 4 — fragments and fetch

Build:

- `render_fragment`
- `data-shomen-get` and `data-shomen-post` in `shomen.js`, replacing the target `id`
- A JSON response only when the route asks for it

Acceptance:

- The phase 2 form still works with JavaScript disabled
- With JavaScript enabled, only the named element is replaced
- The official JavaScript has no npm dependency

---

## Phase 5 — SSE and islands

Build:

- Opt-in SSE
- `data-shomen-island`
- One island example (a counter is enough)

Acceptance:

- An application that does not use SSE gains no extra dependency
- The framework does not scatter event listeners outside an island

---

## Phase 6 — Postgres and production hardening

Build:

- A Postgres adapter for Store. Appends are serialized so ids become visible in order
- `SHOMEN_ENV=production` hides the exception body
- A minimum CSP
- `SHOMEN_ENV=production` requires `SHOMEN_SECRET` of 32 bytes or more
- `SHOMEN_SECRET_VERIFY` for changing the secret
- `reuse_port` on `Shomen::Server.start`
- Graceful shutdown on SIGTERM and SIGINT

Acceptance:

- SQLite and Postgres share the same Command API
- The example default remains SQLite
- With `SHOMEN_ENV=production` and no `SHOMEN_SECRET`, startup fails with a message that names the variable
- A cookie and a CSRF token signed with `SHOMEN_SECRET_VERIFY` are accepted, and the response reissues the cookie under `SHOMEN_SECRET`
- Two processes with one secret on one Postgres database: a form rendered by one is accepted when posted to the other, and a GET to either shows the change
- While one append transaction is open after its insert, an append from another process waits until the first commits
- Concurrent appends from two processes: a projection that follows its checkpoint receives every event once, in `id` order
- After SIGTERM, a request in progress (other than an SSE stream) completes with its normal response and `Connection: close`, an idle keep-alive connection is closed, a new connection is refused, and the process exits within the limit

---

## Phase 7 — scale out

Build:

- Consumers: projections and reactions that run outside the request, with a stored checkpoint, batches that commit only when no other process moved the checkpoint, and retry with a growing delay
- Projections that keep their rows and checkpoint in database tables, and a bounded wait for a request that must see a given `id`
- A notification after an append (Postgres `LISTEN/NOTIFY`), with polling as the fallback
- SSE streams that receive changes appended through any process
- A weak `ETag` built from a GET route's validator, the build id, and the session's CSRF token, and 304 for a matching `If-None-Match`
- A bounded in-process cache for rendered fragments, keyed by their inputs, the viewer when the content differs by viewer, and a value that changes with the data they show
- Reads from a Postgres replica, with read-your-writes within a session

Acceptance:

- Two processes run the same consumer: each event's database effect is applied once, in `id` order. When one process is killed during a batch, the other continues from the stored checkpoint and loses no event
- A consumer's database writes and its checkpoint commit together. A failure between them leaves neither
- An SSE client connected to process A receives an update for an event appended through process B
- A GET with a matching `If-None-Match` returns 304 and does not call the view
- After the session or the build changes, a GET with the old `ETag` gets a full 200 response
- Caching a fragment that contains the current CSRF token raises
- With a replica that lags, a POST, its redirect, and the following GET in one session show the appended change
- When a projection kept in tables does not reach the needed `id` within the limit, the response is 503, not an older state. After the session forgets that `id`, the same page returns 200
- An application on SQLite runs unchanged. No feature in this phase requires a backing service besides the database
