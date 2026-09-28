# 01 Architecture

> Canonical text. Japanese translation: [../01-ARCHITECTURE.md](../01-ARCHITECTURE.md).

## Where state lives

Default: the server holds the document.
Exception: only an island holds a short piece of UI state in the browser.
Persistence: the event log is the fact. The read model is what the screen shows now.

There is no client-wide state machine.

## Request path

```
HTTP request
  → Server (headers, session)
  → Router (method + path)
  → Build Input (a failed conversion is 400)
  → Route#call
  → Command (when something changes)
  → Append to the event store
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
| `Shomen::Store` | Append and read | Event |
| `Shomen::Island` | Serve the official JavaScript | Server |

A lower module does not import a higher one. Store must not know HTML. HTML must not know SQLite.

## Rendering

- A document view starts at `<!DOCTYPE html>`
- A fragment view has one root element. An `id` makes replacement easier, and phase 1 does not require it
- The same data type may produce both a document and a fragment. They do not have to share one class

## Persistence

Phase 3:

- File `var/shomen.sqlite3` (the application may change the path)
- Only the `events` table is required
- The first read model may be rebuilt in memory. Apply every event at startup. Add a snapshot after the count grows

## Official JavaScript

Serve `src/shomen/assets/shomen.js` as a static file. No build step. No external npm package.
