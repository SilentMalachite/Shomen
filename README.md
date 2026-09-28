# Shomen

[English](README.md) | [日本語](README.ja.md)

Shomen is a Crystal web framework. The server returns HTML documents. One route declaration is the contract for a page, and basic accessibility mistakes fail at compile time.

Version 0.0.0. Phases 1 and 2 are in the tree: typed routes, a typed HTML DSL, an HTTP server, form binding, a signed session cookie, and CSRF protection. Later phases are specified and not implemented. There is no release tag yet.

## Requirements

- Crystal 1.20 or newer
- shards

The framework shard has no dependencies.

## Run the example

```sh
cd examples/hello
shards install
crystal run src/hello.cr
```

Open <http://127.0.0.1:3000>. `GET /` returns a document that contains `<h1>Hello</h1>`.

## Use it from an application

`shard.yml`:

```yaml
dependencies:
  shomen:
    github: SilentMalachite/Shomen
    branch: main
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

The server listens on `127.0.0.1:3000`. A match returns 200 HTML. A bad path parameter returns 400. An unknown path, or `Shomen::NotFound`, returns 404 HTML. An unhandled exception returns 500 HTML with the message escaped. Every response sets `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, and `X-Frame-Options: DENY`.

## Phases 1 and 2 are what run

Phase 1 builds these:

- HTML elements listed in the specification, plus escaping
- Compile-time checks for `html` `lang`, one `title`, `button` `type`, and `img` `alt`
- Route declarations, registration, and path helpers
- HTTP responses 200, 400, 404, and 500
- `examples/hello`

Phase 2 adds these:

- `Input` fields from a urlencoded form POST. A missing or malformed field is 400
- `render(view, status: 422)` to redisplay a form
- A signed `shomen_session` cookie. The key is `SHOMEN_SECRET`. Without it, a random key lasts until restart. The server keeps no session state, so with a fixed key a session survives a restart
- A CSRF token in the session. `csrf_field(csrf_token)` writes it into a form. POST, PUT, PATCH, and DELETE without the matching `_csrf` return 403
- A compile-time check that every `input` has a `label` with a matching `for`, a wrapping `label`, or `"aria-label"`. `type: "hidden"` is exempt
- `GET /greeting` and `POST /greeting` in `examples/hello`

These are specified for later phases and are not in the code: SQLite, commands and events, HTML fragments, the official JavaScript file, SSE, and islands.

The phase list is in [docs/en/02-PHASES.md](docs/en/02-PHASES.md).

## Specification

English is the canonical text.

| | English | 日本語 |
|---|---|---|
| Specification | [docs/en/00-INSTRUCTION.md](docs/en/00-INSTRUCTION.md) | [docs/00-INSTRUCTION.md](docs/00-INSTRUCTION.md) |
| Architecture | [docs/en/01-ARCHITECTURE.md](docs/en/01-ARCHITECTURE.md) | [docs/01-ARCHITECTURE.md](docs/01-ARCHITECTURE.md) |
| Phases | [docs/en/02-PHASES.md](docs/en/02-PHASES.md) | [docs/02-PHASES.md](docs/02-PHASES.md) |
| Conventions | [docs/en/03-CONVENTIONS.md](docs/en/03-CONVENTIONS.md) | [docs/03-CONVENTIONS.md](docs/03-CONVENTIONS.md) |

Decision records stay in Japanese under [docs/decisions/](docs/decisions/).

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md). From the repository root:

```sh
shards install
crystal spec
crystal build src/shomen.cr --error-trace
cd examples/hello && shards install && crystal spec
```

`crystal build` writes `./shomen`. Do not commit that binary.

## License

[MIT](LICENSE). Copyright 2026 Silent Malachite.
