# 00 Instruction — Shomen

> Canonical text. Japanese translation: [../00-INSTRUCTION.md](../00-INSTRUCTION.md).

## Conclusion

Shomen is a web framework written in Crystal. By default the server returns an HTML document. JavaScript belongs only on an island. The contract for a page and its API is one route declaration. The source of truth for the domain is an append-only event. A basic accessibility violation is a compile error.

The first thing to build is typed routes, typed HTML, a development server, and specs. An ORM compatibility layer, realtime for every screen, and a plugin system are out of scope.

## Premises

- Language: Crystal `>= 1.20`
- Packages: shards
- Tests: Crystal `spec`
- HTTP: the standard library `HTTP::Server`
- An ECR template string is not the source of a view. HTML is a Crystal expression
- No dependency on Amber, Lucky, Kemal, Marten, or Spider-Gazelle
- This file and `docs/en/` are canonical. Chat history is not
- Expected users: one person or a small group, building business screens, records, and applications that need accessibility

## Scope

### In scope

- Generate the handler, path helper, and input type from a route declaration
- A typed HTML DSL
- Document responses and HTML fragment responses
- A minimum set of compile-time accessibility checks
- A development server. Recompilation may be manual or a simple watch. Advanced HMR is out of scope
- A minimal core for commands, events, and a read model
- SQLite as the first persistence (a Postgres adapter comes in a later phase)
- A minimal session cookie
- Optional screen updates over SSE. A permanent WebSocket connection is out of scope
- One official island runtime file, zero dependencies, aiming at about 10KB

### Out of scope

- Rails, Phoenix, or Lucky compatibility
- GraphQL, tRPC, RSC
- A SPA or a client router by default
- An admin UI, a theme engine, a plugin marketplace
- A Devise-sized authentication suite (a minimal session only)
- Treating an ActiveRecord-style general model layer as the source of truth
- Splitting the app on the assumption of microservices
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
  handler.cr
  html.cr
  a11y.cr
  session.cr
  command.cr
  event.cr
  store.cr
  server.cr
spec/
examples/hello/               # minimal app. Features do not live in the framework
docs/
```

`shard.yml` names the shard `shomen`. The license is MIT.

Shards the framework may depend on at the start:

- None (phases 0–2)
- `crystal-sqlite3` (phase 3 onward, added when it becomes necessary)

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
- A response is an HTML document or an HTML fragment. JSON waits until phase 4, and only when the route asks for it

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
- `redirect(path, status = 303)`

The server attaches security headers by default.

- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: no-referrer`
- `X-Frame-Options: DENY`

A stricter CSP comes later. Phase 1 may attach one, and does not have to.

### 5. Server

`Shomen::Server` wraps `HTTP::Server`.

- Default bind: `127.0.0.1:3000`
- Match the route, build `Input`, call `call`, write the `Response`
- An unmatched request is a 404 HTML document, not empty JSON
- An unhandled exception is a 500 HTML document. Development may show the message. A production-style flag hides it

### 6. Sessions (phase 2)

- Cookie name: `shomen_session`
- HttpOnly, Secure on HTTPS, SameSite=Lax
- The value is signed. The secret is the environment variable `SHOMEN_SECRET`
- The contents are a small key-value map. The first server-side store may be memory. In phase 2 the session holds only its id and values derived from it (the CSRF token); the map, with its size limit and expiry, comes with the API that lets a route write to the session (`docs/decisions/20260929-phase2-session-store.md`)
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
- A read model is built by applying events. The first store is one SQLite file
- Example table: `events(id INTEGER PK, type TEXT, payload TEXT, at TEXT)`
- Domain events in the body stay separate from framework-internal logs

### 8. Fragment updates and islands (phases 4–5)

- Besides a normal HTML document, a route can return the same view as a fragment
- The official JavaScript is one file, `shomen.js`. Attributes are only `data-shomen-*`
- The default transport is `fetch`. SSE is opt-in
- WebSocket is not built
- An island loads JavaScript only on an element with `data-shomen-island="name"`

### 9. Error model

User-facing HTML and internal exceptions stay separate.

- `Shomen::NotFound`
- `Shomen::BadInput`
- `Shomen::Forbidden` (phase 2 onward)

A JSON error format is undefined until phase 4.

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
