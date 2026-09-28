# 02 Phases

> Canonical text. Japanese translation: [../02-PHASES.md](../02-PHASES.md).

## Current phase

**Phase 2 — forms and sessions**

Phase 1 acceptance is met. Do not implement past this point (phase 3 and later). When phase 2 acceptance is met, stop and wait for the next instruction.

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
- An append-only SQLite store
- Rebuild the read model at startup
- Example: changing a name appends one event row

Acceptance:

- Handling the same command twice yields two event rows (not an overwrite)
- The read model is restored after a restart
- Store does not import HTML

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

- A Postgres adapter for Store
- `SHOMEN_ENV=production` hides the exception body
- A minimum CSP

Acceptance:

- SQLite and Postgres share the same Command API
- The example default remains SQLite

This phase does not start until the user asks for it.
