## What changed

## How to check

- [ ] `crystal spec`
- [ ] `crystal build src/shomen.cr --error-trace`
- [ ] `cd examples/hello && shards install && crystal spec` when the example is involved

CI runs these, with Postgres and Chrome, on every pull request.

If this changes behavior, edit `docs/en/` first and update the Japanese translation in the same pull request.

挙動を変えるときは、先に `docs/en/` を直し、同じプルリクエストで日本語訳も更新する。
