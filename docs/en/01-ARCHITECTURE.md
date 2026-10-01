# 01 Architecture

> Canonical text. Japanese translation: [../01-ARCHITECTURE.md](../01-ARCHITECTURE.md).

## Where state lives

Default: the server holds the document.
Exception: only an island holds a short piece of UI state in the browser.
Persistence: the event log is the fact. The read model is what the screen shows now.
Processes: a process keeps no state that another process needs. An in-memory read model is a copy that catches up from the event log.

There is no client-wide state machine.

## Request path

```
HTTP request
  → Server (headers, session)
  → Router (method + path)
  → Build Input (a failed conversion is 400)
  → Route#call
  → Command (when something changes)
  → Append to the event store (a version conflict is 409)
  → Projection catches up to the latest id
  → View
  → Response
```

A read-only GET does not pass through a Command.

## Module boundaries

| Module | Responsibility | May depend on |
|---|---|---|
| `Shomen::HTML` | DSL, escaping, accessibility macros | nothing |
| `Shomen::Route` | Declaration, Input, path helper | HTML, Response |
| `Shomen::Server` | Bind, match, write | Route, Session |
| `Shomen::Session` | Signed cookie | nothing |
| `Shomen::Command` / `Event` | Types for intent and fact | nothing |
| `Shomen::Store` | Append and read, and wake what waits for an append, from this process at once and from others by notification and polling | Event |
| `Shomen::Projection` | Apply events after a checkpoint | Event, Store |
| `Shomen::Consumer` | Run a projection or a reaction outside the request | Projection, Command, Store |
| `Shomen::Island` | Serve the official JavaScript and island modules | Route |
| `Shomen::SSE` | Send a fragment again after each append the store learns of | Response, Store, Fragment |

A lower module does not import a higher one. Store must not know HTML. HTML must not know SQLite.

## Rendering

- A document view starts at `<!DOCTYPE html>`
- A fragment view (`Shomen::Fragment`) has one root element. Nothing checks the count. `shomen.js` replaces the element whose `id` matches `Shomen-Target`, so a fragment meant for replacement carries that `id`
- The same data type may produce both a document and a fragment. They do not have to share one class

## Persistence

Phase 3:

- File `var/shomen.sqlite3` (the application may change the path). WAL mode, so readers do not block the writer
- An append runs in `BEGIN IMMEDIATE`. Inside a process, writes to one file first take a process-wide lock that a fiber can wait on, because SQLite's busy wait blocks the whole thread. Across processes, a busy timeout makes them wait for each other instead of failing. No side effect runs inside a write transaction (`docs/decisions/20260929-scale-sqlite-writes.md`)
- An append checks the stream's current version and inserts in the same transaction
- Only the `events` table is required (specification section 7)
- A projection may live in memory. At startup it applies every event from `id` 1. Before a view reads it, it applies the events after its checkpoint
- Store reaches the database through `crystal-db`. The SQLite and Postgres adapters differ in SQL and column types, and only Postgres sends notifications. Commands, events, and projections do not know which one runs

Phase 6:

- `Shomen::Store.new(url)` picks the adapter from the URL scheme: `sqlite3` for SQLite, `postgres` or `postgresql` for Postgres. A Postgres URL without `max_pool_size` gets a pool of 10 connections (`docs/decisions/20260929-phase6-store-adapters.md`, `docs/decisions/20260929-phase6-postgres-adapter.md`)
- The Postgres adapter creates the same `events` table with `BIGINT` integer columns. `id` is an identity with `CACHE 1`
- An append takes a transaction-scoped advisory lock with one fixed key before its insert, then commits right away. So ids become visible in increasing order (`docs/decisions/20260929-scale-event-order.md`)

Phase 7:

- A projection may keep its rows and its checkpoint in tables, updated by its consumer. A change to its shape builds a new projection under a new name from `id` 1, then switches reads to it and drops the old tables. A read model has no in-place migration (`docs/decisions/20260929-scale-projection-rebuild.md`)
- A consumer stores its checkpoint in `consumers(name TEXT PRIMARY KEY, checkpoint INTEGER NOT NULL)` (`BIGINT` in Postgres). A batch locks its row on Postgres and compares it on SQLite

## Processes

Phases 6–7:

```
load balancer
  → process 1 … process N   (same build, same SHOMEN_SECRET)
      → Postgres primary     (append, notification, consumer checkpoints)
      → Postgres replicas    (reads, phase 7)
```

- Run one process per CPU core. Processes on one host share a port with `reuse_port`, or listen on separate ports behind the balancer
- A process serves requests after its in-memory projections have caught up
- A deploy replaces processes one at a time. A process that receives SIGTERM finishes the requests it accepted, then exits

## Official JavaScript

Serve `src/shomen/assets/shomen.js` as a static file. No build step. No external npm package.

An island module is a file of the application. `Shomen::Island.script` reads it at compile time and serves it at `/islands/<name>.js`. `shomen.js` loads it only for an element with `data-shomen-island` (`docs/decisions/20260929-phase5-island-script.md`).
