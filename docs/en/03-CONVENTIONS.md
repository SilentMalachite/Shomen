# 03 Conventions

> Canonical text. Japanese translation: [../03-CONVENTIONS.md](../03-CONVENTIONS.md).

## Code

- Public types live under `Shomen::`
- One file, one main type
- Methods stay short. Macros are limited to the DSL and route registration
- Do not hide `nil` and drop it. Missing input is `BadInput`
- Do not grow control flow with exceptions. An expected 4xx is returned as a Response

## Names

- Routes: `Resource::Verb` (`Users::Show`, `Users::Update`)
- Views: `RouteNameView` (`Users::ShowView`)
- Commands: present-tense intent, not a past-tense verb (`RenameUser`)
- Events: past tense (`UserRenamed`)

## Documents

- Change the specification before the code that depends on the change
- English under `docs/en/` is canonical for the specification, the root `README.md`, and `CONTRIBUTING.md`
- Japanese translations are `docs/00-INSTRUCTION.md` through `docs/03-CONVENTIONS.md`, `README.ja.md`, and `CONTRIBUTING.ja.md`. Update them in the same change as the English file
- A decision is one file, `docs/decisions/YYYYMMDD-short-name.md`, written in Japanese
- A decision file contains only 状況 / 決定 / 理由 / 破棄した案
- Notes under `docs/superpowers/` stay Japanese working notes

## Git

- An agent does not commit until the user asks
- A commit subject is English. The body may be Japanese

## Quality

- Pass `crystal tool format`
- Do not finish a phase with warnings left behind
- Do not synchronize tests with sleep
