# Contributing

[English](CONTRIBUTING.md) | [日本語](CONTRIBUTING.ja.md)

Shomen is specified before it is extended. Read the canonical spec, then change the smallest set of files that satisfies the current phase.

## Read first

1. [AGENTS.md](AGENTS.md) for agent sessions. Human contributors can start at the spec.
2. [docs/en/00-INSTRUCTION.md](docs/en/00-INSTRUCTION.md)
3. [docs/en/01-ARCHITECTURE.md](docs/en/01-ARCHITECTURE.md)
4. The current phase at the top of [docs/en/02-PHASES.md](docs/en/02-PHASES.md)
5. [docs/en/03-CONVENTIONS.md](docs/en/03-CONVENTIONS.md)

The Japanese files next to `docs/en/` are translations. If they disagree, the English file wins and the Japanese file is updated to match.

Do not implement a later phase because it looks useful. Phase 2 and after start only when the phase document says they are current.

## Change the spec before the code

Behavior that the spec does not already allow is a documentation change first. Edit the English file under `docs/en/`, then update the Japanese translation in `docs/`. A detail that the phase leaves open is recorded as one file under `docs/decisions/`, in Japanese, with the sections 状況 / 決定 / 理由 / 破棄した案.

Decision logs and the notes under `docs/superpowers/` stay Japanese. They are not a second specification.

## Code

- Crystal 1.20 or newer. Public types live under `Shomen::`.
- Identifiers, code, and commit subjects are English.
- No Amber, Lucky, Kemal, Marten, or Rails compatibility layer.
- No new shard unless the spec names it. Phases 0–2 have no dependencies.
- Keep the sample application in `examples/`. Do not fold it into the framework.
- Run `crystal tool format` on Crystal files you edit.

## Checks

From the repository root:

```sh
shards install
crystal spec
crystal build src/shomen.cr --error-trace
cd examples/hello && shards install && crystal spec
```

`crystal build` writes `./shomen` in the root. Leave it uncommitted.

Specs call the handler directly or build a fixture. They do not bind a fixed public port. The `shomen.js` specs serve on an ephemeral port on 127.0.0.1 and drive a headless Chrome. Without Chrome they are pending; `SHOMEN_CHROME` names the binary.

## Commits

```
<type>: <description>
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`.

The body may be English or Japanese. The subject stays English.
