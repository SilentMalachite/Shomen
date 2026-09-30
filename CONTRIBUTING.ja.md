# 開発に参加する

[English](CONTRIBUTING.md) | [日本語](CONTRIBUTING.ja.md)

Shomen は、仕様を直してから実装を広げます。正本を読み、現行フェーズの受入に必要なファイルだけを変えてください。

## 先に読むもの

1. エージェントとして作業するときは [AGENTS.md](AGENTS.md)。人の貢献は仕様からで足ります。
2. [docs/en/00-INSTRUCTION.md](docs/en/00-INSTRUCTION.md)
3. [docs/en/01-ARCHITECTURE.md](docs/en/01-ARCHITECTURE.md)
4. [docs/en/02-PHASES.md](docs/en/02-PHASES.md) の先頭にある現行フェーズ
5. [docs/en/03-CONVENTIONS.md](docs/en/03-CONVENTIONS.md)

`docs/en/` の隣にある日本語ファイルは訳です。英語と食い違ったら英語に合わせ、日本語を直します。

先のフェーズが便利そうでも、現行より先は実装しません。次のフェーズは、フェーズ文書が現行だと書くまで始めません。

## コードより先に仕様

仕様が許していない挙動は、先に文書を変えます。`docs/en/` の英語を直し、続けて `docs/` の日本語訳を更新します。フェーズが空けてある細部は、`docs/decisions/` に 1 決定 1 ファイルで残します。言語は日本語、見出しは「状況 / 決定 / 理由 / 破棄した案」です。

決定ログと `docs/superpowers/` の作業メモは日本語のままです。こちらは第二の仕様ではありません。

## コード

- Crystal は 1.20 以上。公開型は `Shomen::` の下に置きます。
- 識別子、コード、コミットの題名は英語です。
- Amber、Lucky、Kemal、Marten、Rails の互換レイヤは置きません。
- 仕様が名前を挙げた shard 以外は足しません。フェーズ 0〜2 の依存はゼロで、フェーズ 3 で `sqlite3` と `db` を、フェーズ 6 で `pg` を足しました。
- サンプルは `examples/` に置き、フレームワーク本体へ埋め込みません。
- 触った Crystal ファイルは `crystal tool format` に通します。

## 確認

リポジトリ直下で実行します。

```sh
shards install
crystal spec
crystal build src/shomen.cr --error-trace
cd examples/hello && shards install && crystal spec
```

`crystal build` はルートに `./shomen` を書き出します。コミットには含めません。

spec はハンドラを直接呼ぶか、フィクスチャをビルドします。固定の公開ポートは取りません。`shomen.js` の spec と `examples/hello` のカウンターの spec は 127.0.0.1 の一時ポートで待ち受け、ヘッドレスの Chrome を動かします。Chrome が無ければ pending になります。`SHOMEN_CHROME` で実行ファイルを指定できます。SSE の spec はストリームをパイプ越しに読みます。

Postgres の spec は、`SHOMEN_SPEC_POSTGRES` に DB を作れるユーザーの Postgres の URL（例 `postgres://localhost/postgres`）を入れたときだけ走ります。無ければ pending です。例ごとに `shomen_spec_...` という DB を作り、終わったら消します。シャットダウン、`reuse_port`、2 プロセスの spec は、`spec/support/server_worker.cr` を 1 回ビルドして 127.0.0.1 の一時ポートで起動し、sleep ではなく出力の行を待ちます。フェーズを終える前に、`SHOMEN_SPEC_POSTGRES` を付けて `crystal spec` を走らせます。

GitHub Actions（[`.github/workflows/ci.yml`](.github/workflows/ci.yml)）は、すべてのプルリクエストと `main` への push で、`crystal tool format --check`、ビルド、Postgres 17 のサービスとヘッドレスの Chrome を使った `crystal spec`（pending になる spec はありません）、`examples/hello` の spec を走らせます。このチェックが通ってから、プルリクエストをレビューに出します。

## コミット

```
<type>: <description>
```

type は `feat`、`fix`、`refactor`、`docs`、`test`、`chore`、`perf`、`ci` です。

本文は英語でも日本語でも書けます。題名は英語のままにします。
