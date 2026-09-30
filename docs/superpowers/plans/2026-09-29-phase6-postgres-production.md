# Phase 6 Postgres and Production Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** フェーズ 6 の受入まで届ける。Store の Postgres アダプタ（追記を直列にして `id` を順に見せる）、`SHOMEN_ENV=production`（鍵の必須化と 500 の本文を隠す）、最小限の CSP、`SHOMEN_SECRET_VERIFY` による鍵の入れ替え、`Shomen::Server.start` の `reuse_port`、SIGTERM / SIGINT でのグレースフルシャットダウン。

**Architecture:** `Shomen::Store` は公開 API を変えず、URL のスキームで `Shomen::SQLiteAdapter` か `Shomen::PostgresAdapter`（どちらも抽象クラス `Shomen::StoreAdapter` を継ぐ）を選ぶ。検査、JSON の変換、`AppendSignal` は Store に残し、アダプタは SQL と待ち方だけを持つ（D1）。Postgres の追記と表の作成は、固定キーの `pg_advisory_xact_lock` を取ったトランザクションで行う（D2）。`Shomen::Server` は生成時に `SHOMEN_ENV` を読み、本番では鍵の長さを確かめ、500 のメッセージを隠す。未処理例外は環境によらず `Log.for("shomen")` に書く（D4）。`Shomen::SessionStore` は署名用と検証用の 2 つの鍵を持つ（D5）。CSP はサーバが全応答に付け、ルートが付けた値は残す（D6）。シャットダウンは、`Shomen::Listener < HTTP::Server` が `dispatch` で接続を `Shomen::Connections` に登録し、ハンドラが要求の間を busy、SSE を streaming にする。合図で drain（idle と streaming を閉じ、以後の応答に `Connection: close`）、`close`、busy が 0 か上限で `start` が戻る（D7）。シグナルと複数プロセスの受入は、spec からビルドした `server_worker` を一時ポートで起動して確かめる（D8）。Postgres の spec は `SHOMEN_SPEC_POSTGRES` があるときだけ走り、例ごとに使い捨ての DB を作る（D3）。

**Tech Stack:** Crystal `>= 1.20.0`（開発機は 1.21.1）、標準ライブラリの `spec`、`log`、`http/server`、`socket`。shard は `pg` を足す（`will/crystal-pg` 0.30.0、`db ~> 0.14.0`、純 Crystal で C ライブラリ不要）。開発機の Postgres は Homebrew の 18.6（`postgres://localhost/postgres`、ユーザー `hiro`）。ブラウザ spec は開発機の Google Chrome。

**Spec:** `docs/en/00-INSTRUCTION.md` の「1. Package layout」（`pg` の依存）、「4. Responses」（CSP）、「5. Server」（`reuse_port`、シャットダウン、本番の 500）、「6. Sessions」（`SHOMEN_SECRET`、`SHOMEN_SECRET_VERIFY`）、「7. Commands and events」（`BIGINT`）、「10. Scale out」（プールの上限）、`docs/en/01-ARCHITECTURE.md` の「Persistence」「Processes」、`docs/en/02-PHASES.md` のフェーズ 6、`docs/en/03-CONVENTIONS.md`。既存の決定 `docs/decisions/20260929-scale-postgres-shard.md`、`20260929-scale-event-order.md`、`20260929-scale-production-secret.md`、`20260929-scale-secret-rotation.md`、`20260929-scale-reuse-port.md`、`20260929-scale-graceful-shutdown.md`、`20260929-scale-sqlite-writes.md`、`20260929-phase2-session-store.md`。細部は次の決定ファイルに従う。この計画の Task 1 で足すもの:

- `docs/decisions/20260929-phase6-store-adapters.md`（D1）
- `docs/decisions/20260929-phase6-postgres-adapter.md`（D2）
- `docs/decisions/20260929-phase6-postgres-spec.md`（D3）
- `docs/decisions/20260929-phase6-production.md`（D4）
- `docs/decisions/20260929-phase6-secret-verify.md`（D5）
- `docs/decisions/20260929-phase6-csp.md`（D6）
- `docs/decisions/20260929-phase6-shutdown.md`（D7）
- `docs/decisions/20260929-phase6-process-spec.md`（D8）

D3 と D6 はユーザーが選んだ案（2026-09-29 の計画時の質問: Postgres の spec は「未設定なら pending」、CSP は「`default-src 'self'` 系・ルートの上書き可」）。

計画前に確かめたこと（スクラッチでの試作、2026-09-29）: `pg` 0.30.0 で `SELECT pg_advisory_xact_lock($1)` を `exec` できる、`INSERT ... RETURNING id` と `COALESCE(MAX(version), 0)` は `scalar` で `Int64` になる、一意制約違反は `PQ::PQError`、別セッションのアドバイザリロック待ちは `pg_locks` の `NOT granted` に 1 行出る、`BIGINT GENERATED ALWAYS AS IDENTITY (CACHE 1)` の `pg_sequence.seqcache` は 1、`DB::Database#pool.@max_pool_size` で上限を読める、`postgres` と `postgresql` の両方のスキームが登録済み。`HTTP::Server` を継いで `protected def dispatch(io)` を上書きし、`handle_client(io)` を呼べる。別ファイバーから接続のソケットを閉じると、要求を待つ接続は EOF で終わる。`close` の後の新しい接続は `Socket::ConnectError`。処理中の要求は `Connection: close` 付きで返り、プロセスは終了コード 0 で終わる。パイプの STDIN を読むファイバーは、ほかのファイバー（シグナルの処理）を止めない。`Log.setup(:none)` の下でも `Log.capture("shomen")` は記録を受け取る（`require "log/spec"` の前に `log` が要る）。

## Global Constraints

- 言語は Crystal 1.20 以上。`shard.yml` の `crystal: ">= 1.20.0"` は変えない。足す shard は `pg`（`github: will/crystal-pg`、`version: ">= 0.30.0"`）だけ（仕様 1、`20260929-scale-postgres-shard.md`）。
- `Shomen::Store` の公開 API は変えない: `Shomen::Store.new(url)`、`append(stream, expected_version, events)`、`read(after:, limit: 500)`、`last_appended`、`wait_for_append(after:, within:)`、`close`。
- モジュール境界: Store とアダプタは HTML を知らない。Command、Event、Projection、SSE、AppendSignal は SQLite も Postgres も名指ししない（`spec/shomen/boundary_spec.cr` が検査する）。
- 公開 API は `Shomen::` 配下だけ。1 ファイル 1 主要型。ファイル名は機能名。
- `LISTEN/NOTIFY`、コンシューマ、表に置くプロジェクション、`ETag`、断片キャッシュ、replica からの読み出しを作らない（フェーズ 7）。SSE を起こすのは、このプロセスの追記だけのまま。
- `examples/hello` の既定の Store は `sqlite3://./var/shomen.sqlite3` のまま。
- 色コード、デザイントークン、国際化の仕組みを作らない。
- コードと識別子は英語。この計画と決定ログは日本語。
- ユーザーが指示するまで commit しない。この計画に commit 手順は無い。
- `crystal tool format` を通し、警告を残して完了にしない。
- テストは固定ポートを bind しない。ブラウザ spec と `server_worker` だけが `127.0.0.1` の一時ポート（ポート 0）を使う。sleep で同期しない。待ちは Channel、子プロセスの出力の行、DevTools のイベントで行う。別プロセスが変える Postgres の状態だけは `wait_until`（上限つきの繰り返し、sleep なし）で待つ。上限（5 秒、10 秒、20 秒、60 秒）は失敗の検出だけに使う。ポート 3000 を使うのは Task 11 の手動確認だけ。
- Postgres の spec は `SHOMEN_SPEC_POSTGRES` が無ければ pending。受入の確認は `SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres` を付けて行う。
- 検証でリポジトリルートにできる実行ファイル `shomen` と `shomen.dwarf` は `docs/decisions/20260928-build-artifact.md` のとおり削除する。

実行はリポジトリルートで行う。`Shomen::VERSION` は `"0.0.0"` のまま変えない。以下、`PG=postgres://localhost/postgres` と書いたら `SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres` を付けて実行する意味とする。

## Review Focus

- 空の Postgres DB に、2 つのプロセスが同時に起動する。どちらも失敗せず、`events` 表は 1 つだけできる（`CREATE TABLE IF NOT EXISTS` どうしはカタログの一意制約でぶつかることがある）。DB から見れば別々の接続が同時に表を作ることなので、spec は 1 プロセスの 4 つのファイバーから別々の Store を同時に開いて確かめる。Task 3 の "opens one events table when stores start at once on an empty database" で固定する。
- 鍵の入れ替えの途中で、新しい鍵で出し直したクッキーと、古い鍵で描いたフォームのトークンが 1 つの要求にそろう。手順 2 の間、古い鍵で署名するプロセスに新しい鍵のクッキーが届く。どちらも 403 にならない。Task 6 の "accepts a form rendered under the old secret after the cookie was reissued" と "lets a process that still signs with the old secret accept the new one while they swap" で固定する。
- 鍵の長さの境界。本番で 31 バイトの `SHOMEN_SECRET` は起動に失敗し、32 バイトは通る。`SHOMEN_SECRET_VERIFY` だけが短いときも、その変数名を出して失敗する。Task 5 の "refuses a SHOMEN_SECRET shorter than 32 bytes and takes one of 32" と Task 6 の "refuses a SHOMEN_SECRET_VERIFY shorter than 32 bytes and names it" で固定する。
- シャットダウン中の 2 回目のシグナル。開発中に Ctrl-C を 2 回押すと、上限を待たずにすぐ終わる。Task 9 の "stops at once on a second signal" で固定する。
- CSP の下での `shomen.js`。島のモジュール（`import()`）、SSE（`EventSource`）、fetch の差し替えが、違反を 1 つも出さずに動く。Task 7 の "lets shomen.js run islands, a stream, and a fetch with no violation" で固定する。

## File Map

| ファイル | 役割 | Task |
|---|---|---|
| `docs/en/02-PHASES.md`、`docs/02-PHASES.md` | 現行フェーズをフェーズ 6 にする（Task 1）、受入済みにする（Task 11） | 1, 11 |
| `docs/en/00-INSTRUCTION.md`、`docs/00-INSTRUCTION.md` | 仕様 4 の CSP、仕様 5 の本番の 500 | 1 |
| `docs/en/01-ARCHITECTURE.md`、`docs/01-ARCHITECTURE.md` | Persistence のフェーズ 6 にアダプタの選び方とプール | 1 |
| `docs/decisions/20260929-phase6-*.md` | D1〜D8 | 1 |
| `shard.yml`、`shard.lock`、`examples/hello/shard.lock` | `pg` を足す | 3 |
| `src/shomen/store_adapter.cr` | `Shomen::StoreAdapter` | 2 |
| `src/shomen/sqlite_adapter.cr` | `Shomen::SQLiteAdapter`（`store.cr` から移す） | 2 |
| `src/shomen/postgres_adapter.cr` | `Shomen::PostgresAdapter` | 3 |
| `src/shomen/store.cr` | アダプタを選ぶ Store | 2, 3 |
| `src/shomen/session.cr` | `reissue?` | 6 |
| `src/shomen/session_store.cr` | 検証用の鍵、`csrf_valid?` | 6 |
| `src/shomen/connections.cr` | `Shomen::Connections` | 8 |
| `src/shomen/listener.cr` | `Shomen::Listener` | 9 |
| `src/shomen/server.cr` | 本番（5）、検証用の鍵（6）、CSP（7）、接続の状態（8）、`start`（9） | 5, 6, 7, 8, 9 |
| `src/shomen.cr` | `connections` と `listener` の require（アダプタは `store.cr` が require する） | 8, 9 |
| `spec/spec_helper.cr` | 新しい support の require、`Log.setup(:none)`、`Spec.after_suite` | 3, 4, 5, 7, 9 |
| `spec/support/workers.cr` | `Workers.binary`、`Workers.remove` | 3 |
| `spec/support/postgres.cr` | `PostgresSpec`、`postgres_database_it` | 3 |
| `spec/support/store.cr` | `with_store_url`、`store_it`、`postgres_it` | 3 |
| `spec/support/store_worker.cr` | `wait` の引数 | 4 |
| `spec/support/wait.cr` | `wait_until` | 4 |
| `spec/support/env.cr` | `with_env`、`LONG_SECRET` | 5 |
| `spec/support/csp_routes.cr` | CSP のルート | 7 |
| `spec/support/server_worker.cr` | spec が起動するサーバ（Task 9）、メモのルート（Task 10） | 9, 10 |
| `spec/support/server_process.cr` | `ServerProcess`、`with_server_process`、`send_get`、`read_until` | 9 |
| `spec/shomen/store_spec.cr`、`spec/shomen/projection_spec.cr`、`spec/shomen/store_concurrency_spec.cr`、`spec/shomen/boundary_spec.cr` | アダプタへの分割（2）、両方の DB で同じ振る舞い（3） | 2, 3 |
| `spec/shomen/postgres_adapter_spec.cr` | Postgres だけの振る舞い（3）、順序の受入（4） | 3, 4 |
| `spec/shomen/production_spec.cr` | Task 5、6 | 5, 6 |
| `spec/shomen/server_spec.cr` | 例外のログ（5）、CSP（7）、`Connection: close`（8） | 5, 7, 8 |
| `spec/shomen/session_store_spec.cr`、`spec/shomen/secret_rotation_spec.cr` | Task 6 | 6 |
| `spec/shomen/csp_browser_spec.cr` | Task 7 | 7 |
| `spec/shomen/connections_spec.cr` | Task 8 | 8 |
| `spec/shomen/shutdown_spec.cr`、`spec/shomen/start_spec.cr` | Task 9 | 9 |
| `spec/shomen/two_processes_spec.cr` | Task 10 | 10 |
| `README.md`、`README.ja.md`、`CONTRIBUTING.md`、`CONTRIBUTING.ja.md` | フェーズ 6 の反映 | 11 |

---

### Task 1: 現行フェーズ、仕様、決定ファイル

**Files:**
- Modify: `docs/en/02-PHASES.md:5-9`、`:147`
- Modify: `docs/02-PHASES.md:5-9`、`:147`
- Modify: `docs/en/00-INSTRUCTION.md:168`、`:177`
- Modify: `docs/00-INSTRUCTION.md:168`、`:177`
- Modify: `docs/en/01-ARCHITECTURE.md:65-68`
- Modify: `docs/01-ARCHITECTURE.md:65-68`
- Create: `docs/decisions/20260929-phase6-store-adapters.md`
- Create: `docs/decisions/20260929-phase6-postgres-adapter.md`
- Create: `docs/decisions/20260929-phase6-postgres-spec.md`
- Create: `docs/decisions/20260929-phase6-production.md`
- Create: `docs/decisions/20260929-phase6-secret-verify.md`
- Create: `docs/decisions/20260929-phase6-csp.md`
- Create: `docs/decisions/20260929-phase6-shutdown.md`
- Create: `docs/decisions/20260929-phase6-process-spec.md`

**Interfaces:**
- Consumes: なし
- Produces: 後続タスクが従う決定 D1〜D8。ここで決めた名前（`Shomen::StoreAdapter`、`Row`、`Stored`、`key`、`check_version`、`Shomen::SQLiteAdapter`、`Shomen::PostgresAdapter`、`LOCK_KEY`、`LOCK`、`INSERT`、`POOL_SIZE`、`Shomen::Server.production?`、`MIN_SECRET_BYTES`、`Shomen::Server.verify_secret_from_env`、`verify_secret:`、`Shomen::Session#reissue?`、`Shomen::SessionStore#csrf_valid?`、`Shomen::Server::CSP`、`Shomen::Connections`（`open`、`leave`、`request`、`stream`、`drain`、`draining?`、`busy`、`wait`）、`Shomen::Listener`、`Shomen::Server#connections`、`Shomen::Server::SHUTDOWN_TIMEOUT`、`reuse_port:`、`shutdown_timeout:`、`SHOMEN_SPEC_POSTGRES`、`WORKER_DATABASE_URL`）は Task 2〜10 のコードと一致させる。

- [ ] **Step 1: 現行フェーズを書き換える（英語）**

`docs/en/02-PHASES.md` の「## Current phase」の本文を次にする。

```markdown
## Current phase

**Phase 6 — Postgres and production hardening**

Phase 5 acceptance is met. Do not implement past this point (phase 7 and later). When phase 6 acceptance is met, stop and wait for the next instruction.
```

同じファイルの「## Phase 6 — Postgres and production hardening」の最後の行 `This phase does not start until the user asks for it.` と、その前の空行を消す。フェーズ 7 の同じ行は残す。

- [ ] **Step 2: 現行フェーズを書き換える（日本語訳）**

`docs/02-PHASES.md` の「## 現行フェーズ」の本文を次にする。

```markdown
## 現行フェーズ

**フェーズ 6 — Postgres と本番寄せ**

フェーズ 5 の受入は満たした。ここより先（フェーズ 7 以降）を実装しない。6 の受入を満たしたら停止し、ユーザーの次指示を待つ。
```

同じファイルの「## フェーズ 6 — Postgres と本番寄せ」の最後の行 `このフェーズはユーザーが明示するまで開始しない。` と、その前の空行を消す。フェーズ 7 の同じ行は残す。

- [ ] **Step 3: 仕様 4 と 5 を直す（英語）**

`docs/en/00-INSTRUCTION.md` の 168 行目 `A stricter CSP comes later. Phase 1 may attach one, and does not have to.` を次にする。

```markdown
From phase 6 the server also attaches `Content-Security-Policy: default-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'`. When the route's response already has a `Content-Security-Policy`, the server keeps it (`docs/decisions/20260929-phase6-csp.md`).
```

177 行目 `- An unhandled exception is a 500 HTML document. Development may show the message. A production-style flag hides it` を次にする。

```markdown
- An unhandled exception is a 500 HTML document. Development may show the message. With `SHOMEN_ENV=production` the document hides it. The exception goes to the log in every environment (phase 6, `docs/decisions/20260929-phase6-production.md`)
```

- [ ] **Step 4: 仕様 4 と 5 を直す（日本語訳）**

`docs/00-INSTRUCTION.md` の 168 行目 `CSP の厳密化は後のフェーズ。フェーズ 1 では付けてもよいが必須ではない。` を次にする。

```markdown
フェーズ 6 からは `Content-Security-Policy: default-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'` も付ける。ルートの応答がすでに `Content-Security-Policy` を持っていれば、そちらを残す（`docs/decisions/20260929-phase6-csp.md`）。
```

177 行目 `- 未処理例外は 500 の HTML 文書。開発時はメッセージを出してよい。本番相当フラグでは出さない` を次にする。

```markdown
- 未処理例外は 500 の HTML 文書。開発時はメッセージを出してよい。`SHOMEN_ENV=production` では文書に出さない。例外は環境によらずログに書く（フェーズ 6、`docs/decisions/20260929-phase6-production.md`）
```

- [ ] **Step 5: Persistence のフェーズ 6 に足す（英語と日本語訳）**

`docs/en/01-ARCHITECTURE.md` の「Phase 6:」の箇条（67〜68 行目）の前に 1 行足す。

```markdown
- `Shomen::Store.new(url)` picks the adapter from the URL scheme: `sqlite3` for SQLite, `postgres` or `postgresql` for Postgres. A Postgres URL without `max_pool_size` gets a pool of 10 connections (`docs/decisions/20260929-phase6-store-adapters.md`, `docs/decisions/20260929-phase6-postgres-adapter.md`)
```

`docs/01-ARCHITECTURE.md` の「フェーズ 6:」の箇条（67〜68 行目）の前に 1 行足す。

```markdown
- `Shomen::Store.new(url)` は URL のスキームでアダプタを選ぶ。`sqlite3` なら SQLite、`postgres` か `postgresql` なら Postgres。`max_pool_size` を書かない Postgres の URL は、接続 10 本のプールになる（`docs/decisions/20260929-phase6-store-adapters.md`、`docs/decisions/20260929-phase6-postgres-adapter.md`）
```

- [ ] **Step 6: D1 を書く**

`docs/decisions/20260929-phase6-store-adapters.md`:

```markdown
# 状況

フェーズ 3 の `Shomen::Store` は SQLite だけを扱い、URL のスキームが `sqlite3` でなければ `ArgumentError` にしていた。フェーズ 6 は Postgres のアダプタを足し、受入に「SQLite と Postgres で同じ Command API を使う」がある。01-ARCHITECTURE は、2 つのアダプタの違いを SQL、列の型、通知の有無にとどめるとしている。

# 決定

`Shomen::Store` の公開 API（`new(url)`、`append`、`read`、`last_appended`、`wait_for_append`、`close`）は変えない。`Shomen::Store.new(url)` が URL のスキームでアダプタを選ぶ。`sqlite3` なら `Shomen::SQLiteAdapter`、`postgres` か `postgresql` なら `Shomen::PostgresAdapter`、それ以外は `ArgumentError` にする。

アダプタは抽象クラス `Shomen::StoreAdapter` を継ぎ、`key`、`append(stream, expected_version, rows) : Int64`（最後の `id` を返す）、`read(after, limit)`、`close` を持つ。版が合わないときに `Shomen::Conflict` を投げる処理は、基底クラスに 1 つだけ置く。引数の検査（空のストリーム名、負の版、UTC でない時刻）、JSON への変換と復元、`Shomen::AppendSignal` への知らせは `Shomen::Store` に残す。`AppendSignal` はアダプタの `key` ごとにプロセスで 1 つにする。SQLite の `key` は `sqlite3://` に実パスを続けたもの、Postgres の `key` は `postgres://` に URL のホスト、ポート、DB 名を続けたものである。

# 理由

アプリ、コマンド、プロジェクション、SSE は `Shomen::Store` だけを知っていればよく、DB を替えても URL 以外は変わらない。アダプタごとに違うのは SQL と待ち方だけなので、検査と変換を 2 回書かずに済む。

# 破棄した案

- `Shomen::Store` を抽象クラスにし、アプリに `Shomen::SQLiteStore` か `Shomen::PostgresStore` を直接 `new` させる（DB の種類がアプリのコードに入る）
- 1 つのクラスの中で、メソッドごとに SQLite と Postgres を分岐する
```

- [ ] **Step 7: D2 を書く**

`docs/decisions/20260929-phase6-postgres-adapter.md`:

```markdown
# 状況

`20260929-scale-event-order.md` は、Postgres への追記を固定キーの `pg_advisory_xact_lock` で直列にし、`id` の identity を `CACHE 1` にすると決めた。キーの値、表を作るときの扱い、接続プールの大きさは決めていない。仕様 10 は、プロセスごとの接続プールに上限を置き、その大きさを DB の URL で決めるとしている。`crystal-db` の `max_pool_size` の既定は 0（上限なし）、`max_idle_pool_size` の既定は 1 である。

# 決定

- 表は `id BIGINT GENERATED ALWAYS AS IDENTITY (CACHE 1) PRIMARY KEY`、`version BIGINT`、ほかの列は `TEXT`、`UNIQUE (stream, version)` にする
- ロックのキーは `BIGINT` の `0x73686f6d656e`（`"shomen"` の ASCII）1 つにする
- `CREATE TABLE IF NOT EXISTS` も、同じキーのロックを取ったトランザクションの中で行う
- 追記は `BEGIN`、ロック、現在の版の確認、イベントの数だけの `INSERT ... RETURNING id`、`COMMIT` の順に行う。版が合わなければ何も挿入せずに `ROLLBACK` し、`Shomen::Conflict` を投げる。ほかの失敗でも `ROLLBACK` し、元の例外を投げ直す。`ROLLBACK` 自体の失敗は元の例外を隠さない
- URL に `max_pool_size` が無ければ 10 にする。`max_idle_pool_size` が無ければ `max_pool_size` と同じにする
- URL の DB 名が空なら、接続する前に `ArgumentError` にする

# 理由

空の DB に複数のプロセスが同時に起動すると、`CREATE TABLE IF NOT EXISTS` どうしがカタログの一意制約でぶつかることがある。追記と同じロックで直列にすれば、後から来たプロセスは表があるのを見るだけになる。上限の無いプールは、プロセスを増やすと Postgres の `max_connections` を使い切る。10 本あれば、ロックで直列になる追記を待たせながら読み出しを並べられる。アイドルの上限を 1 のままにすると、負荷の高いときに接続を閉じては開き直す。キーを 1 つに固定すれば、アプリの他のアドバイザリロックとぶつかるのは同じ値を使ったときだけになる。

# 破棄した案

- `BIGSERIAL` を使う（identity より古い書き方で、`id` に直接値を書けてしまう）
- 表を作るときはロックを取らない
- プールの大きさを `crystal-db` の既定（上限なし）のままにする
- キーを `hashtext('shomen')` のように計算で決める
```

- [ ] **Step 8: D3 を書く**

`docs/decisions/20260929-phase6-postgres-spec.md`:

```markdown
# 状況

フェーズ 6 の受入のうち、Postgres での追記、ロックの待ち、2 プロセスでのフォームは、Postgres のサーバが無いと確かめられない。これまでの spec は、SQLite のファイルと Chrome（無ければ pending）だけで走った。

# 決定

環境変数 `SHOMEN_SPEC_POSTGRES` に、DB を作れるユーザーの Postgres の URL（例 `postgres://localhost/postgres`）を入れると、Postgres の spec が走る。未設定なら、その spec は pending にする（2026-09-29 の計画時にユーザーが選んだ）。フェーズ 6 の受入は、設定した状態で確かめる。

Postgres の例は、それぞれ `shomen_spec_` に 16 桁の 16 進を続けた名前の DB を作り、終わったら `DROP DATABASE ... WITH (FORCE)` で消す。SQLite と Postgres の両方で同じ振る舞いを確かめる例は `store_it` で書き、1 つの記述から DB ごとの例を作る。Postgres だけの例は `postgres_it`（Store を開いた DB）と `postgres_database_it`（空の DB）で書く。

# 理由

Postgres の無い環境でも `crystal spec` は緑のまま走り、Chrome が無いときと同じ扱いになる。例ごとに DB を分ければ、`id` はいつも 1 から始まり、プロセス内の `AppendSignal` も例ごとに別になる。1 つの DB を使い回すと URL が同じなので、前の例の最後の `id` が `AppendSignal` に残る。

# 破棄した案

- 未設定なら失敗にする（Postgres の無い環境で spec が赤になる）
- 1 つの DB を使い回し、例ごとに表を消す（`AppendSignal` の最後の `id` が例をまたいで残る）
- spec の中で Docker の Postgres を立てる（開発機に Docker が無く、DB 以外の道具を spec に持ち込む）
```

- [ ] **Step 9: D4 を書く**

`docs/decisions/20260929-phase6-production.md`:

```markdown
# 状況

仕様 5 は、未処理例外の 500 で、本番相当のフラグのときはメッセージを出さないとしている。フェーズ 6 はそのフラグを `SHOMEN_ENV=production` に決め、あわせて `SHOMEN_SECRET` を必須にする（`20260929-scale-production-secret.md`）。いまの 500 の文書は例外の `message` をそのまま出し、例外をどこにも記録していない。

# 決定

- `SHOMEN_ENV` の値がちょうど `production` のときを本番とする。`Shomen::Server.new` のときに 1 回読む
- 本番では、`SHOMEN_SECRET` が未設定か 32 バイト未満なら、`ArgumentError`（"SHOMEN_SECRET must be set to at least 32 bytes when SHOMEN_ENV=production"）を投げる。`secret:` を直接渡したときも、32 バイト未満なら "secret must be at least 32 bytes when SHOMEN_ENV=production" で投げる。`SHOMEN_SECRET_VERIFY` と `verify_secret:` も同じ下限で確かめる（`20260929-phase6-secret-verify.md`）
- 本番の 500 は、見出し "Error" だけの文書にし、例外のメッセージを出さない。400 の説明（"invalid id" など）は利用者への案内なので、本番でも出す
- 未処理例外は、環境によらず `Log.for("shomen")` に error で、例外ごと書く。メッセージは "unhandled exception"
- `Shomen::Server.start` は鍵を確かめてから待ち受ける。鍵が足りなければ、未処理の `ArgumentError` として終了コード 1 で終わる

# 理由

本番でメッセージを隠すなら、運用者が原因を見る場所が要る。標準の `HTTP::Server` も `Log` に書くので、同じ出口にそろえる。400 の説明は入力のどこが悪いかを伝えるもので、内部の情報を含まない。生成時に 1 回読めば、要求のたびに環境変数を読まずに済み、プロセスの途中で振る舞いが変わらない。

# 破棄した案

- 本番の判定に `CRYSTAL_ENV` や `--release` を使う
- 本番では 400 の説明も隠す
- 例外を記録しない、または本番だけ記録する
- 起動の失敗を `STDERR` への 1 行と `exit 1` にする（ライブラリの中で終了すると spec で確かめられない）
```

- [ ] **Step 10: D5 を書く**

`docs/decisions/20260929-phase6-secret-verify.md`:

```markdown
# 状況

`20260929-scale-secret-rotation.md` は、`SHOMEN_SECRET_VERIFY` を検証だけに使う 2 つ目の鍵にし、その鍵で通ったクッキーを `SHOMEN_SECRET` で出し直すと決めた。フェーズ 2 の `Shomen::SessionStore` は鍵を 1 つだけ持ち、`Shomen::Server` は送られた CSRF トークンを `session.csrf_token` と直接比べている。

# 決定

- `Shomen::SessionStore.new(secret, verify_secret = nil)`。クッキーは、まず `secret` で、次に `verify_secret` で確かめる。後者で通ったセッションは `reissue?` が真になり、サーバはその応答で `SHOMEN_SECRET` のクッキーを出し直す
- `session.csrf_token` は常に `secret` で作る。送られたトークンは `Shomen::SessionStore#csrf_valid?(session, sent)` で確かめ、2 つの鍵のどちらで作ったものでも受け付ける。どちらの鍵でクッキーが通ったかは問わない
- `Shomen::Server.new(verify_secret:)` の既定は `SHOMEN_SECRET_VERIFY`。空文字は未設定と同じにする

# 理由

手順 2 の間は、新しい鍵で出し直したクッキーと、古い鍵で描いたフォームのトークンが 1 つの要求にそろうことがある。トークンをクッキーと同じ鍵に縛ると、そのフォームが 403 になる。トークンは同じセッションの `id` から導くので、どちらの鍵で作っても他人のセッションのトークンにはならない。

# 破棄した案

- トークンを、クッキーを通した鍵でだけ確かめる
- 検証用の鍵で通ったセッションを、新しいセッションとして作り直す（利用者のセッションが切れる）
```

- [ ] **Step 11: D6 を書く**

`docs/decisions/20260929-phase6-csp.md`:

```markdown
# 状況

仕様 4 は、より厳しい CSP を後のフェーズに回していた。フェーズ 6 の作るものに「最小限の CSP」がある。値と、ルートがそれを変えられるかは決めていない。公式の JavaScript は `/shomen.js` と `/islands/<name>.js` の外部ファイルで、`fetch`、`EventSource`、動的 `import()` はすべて同じオリジンに向く。DSL が書く `script` 要素は `shomen_script` の 1 つだけである。

# 決定

すべての応答に次の値を付ける（2026-09-29 の計画時にユーザーが選んだ）。

`Content-Security-Policy: default-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'`

ルートの応答がすでに `Content-Security-Policy` を持っていれば、その値を残す。`X-Frame-Options: DENY` はこれまでどおり付ける。

# 理由

`default-src 'self'` は、インラインのスクリプトと、ほかのオリジンのスクリプトを止める。`shomen.js`、島のモジュール、`fetch`、`EventSource` は同じオリジンなので止まらない。`base-uri` と `form-action` は `default-src` から引き継がれないので明示する。`form-action 'self'` は、差し込まれたフォームが外へ送るのを止める。`object-src 'none'` はプラグインを止める。外部の画像やフォントを使うページは、そのルートが自分の CSP を返せば済む。

# 破棄した案

- 同じ値を常に上書きし、ルートからは変えられないようにする
- スクリプトだけを絞る（`script-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'`）
- nonce を使う（DSL の `script` 要素は外部ファイルだけなので要らない）
```

- [ ] **Step 12: D7 を書く**

`docs/decisions/20260929-phase6-shutdown.md`:

```markdown
# 状況

`20260929-scale-graceful-shutdown.md` は、SIGTERM と SIGINT の後の順序（受け付けの停止、`Connection: close`、アイドル接続を閉じる、SSE を閉じる、処理中が 0 になるか上限で終わる）を決めた。標準の `HTTP::Server` は接続の一覧を外に出さず、ハンドラは接続のソケットを受け取らない。

# 決定

- `Shomen::Connections` が、サーバの接続を、それを処理するファイバーごとに覚える。状態は idle、busy（要求の処理中）、streaming（SSE）の 3 つ
- `Shomen::Listener < HTTP::Server` は `dispatch` を上書きし、接続のファイバーの始めに `open(io)`、終わりに `leave` を呼ぶ
- `Shomen::Server#call` は、要求の間を busy にする。SSE の応答を書き始めるときに streaming にする。登録の無いファイバー（ハンドラを直接呼ぶ spec）では何もしない
- 合図を受けたら、`drain`（idle と streaming の接続を閉じ、以後の応答に `Connection: close` を付ける）、`HTTP::Server#close`、STDERR への `shomen: shutting down` の順に行う。drain の後で streaming になった接続は、すぐ閉じる
- 最初の合図で SIGTERM と SIGINT を既定の動作に戻す。2 回目の合図で、プロセスはすぐ終わる
- `Shomen::Server.start` は、busy が 0 になるか `shutdown_timeout` を過ぎたら戻る。アプリの main がそこで終われば、終了コードは 0 になる
- 待ち受けを始めたら、STDERR に `shomen: listening on http://<アドレス>:<ポート>` を書く。ポート 0 のときは実際のポートが入る

# 理由

`dispatch` は、標準ライブラリが上書きを想定しているメソッドで、ここで接続のソケットをつかめる。ハンドラは接続を処理するファイバーの中で呼ばれるので、ファイバーから接続を引ける。`drain` を `close` より先にすれば、その間に終わる応答にも `Connection: close` が付く。2 回目の合図ですぐ終わるのは、開発中に Ctrl-C を 2 回押したときの期待に合わせるためである。`start` の中で `exit` しないのは、戻った後にアプリが Store を閉じられるようにするためである。待ち受けのアドレスを書けば、ポート 0 で起動したプロセスのポートを spec が知れる。

アイドルの接続に要求が届いたのと同じ瞬間に drain が閉じると、その要求は応答なしで切れる。キープアライブの接続が閉じられたとき、冪等な要求を新しい接続でやり直すのはクライアントの通常の動きなので、この狭い競合は残す。

# 破棄した案

- `HTTP::Server` を使わず、接続の受け付けから自前で書く
- ソケットを包む IO を作り、要求の読み始めを検知する（仕組みが大きい）
- `start` の最後で `exit 0` する
- 2 回目の合図も無視し、上限まで待つ
```

- [ ] **Step 13: D8 を書く**

`docs/decisions/20260929-phase6-process-spec.md`:

```markdown
# 状況

グレースフルシャットダウン、`reuse_port`、本番での起動の失敗、2 プロセスでのフォーム、別プロセスからの追記の待ちは、シグナルか別のプロセスを使うので、ハンドラを直接呼ぶ spec では確かめられない。仕様は、spec が固定のポートを取らず、sleep で同期しないことを求めている。

# 決定

- `spec/support/server_worker.cr` と `spec/support/store_worker.cr` をスイートで 1 回ずつビルドし、spec から別プロセスで起動する。ビルドした実行ファイルは、スイートの終わりに消す
- `server_worker` の引数は、ポート（0 で一時ポート）、`reuse` か `single`、`shutdown_timeout` の秒数。Store の URL は環境変数 `WORKER_DATABASE_URL` で渡す
- spec は、STDERR の `shomen: listening on http://127.0.0.1:<port>` からポートを読む。子プロセスの STDOUT と STDERR は行ごとに Channel へ流し、決まった行が来るまで待つ
- 処理中の要求は `/worker/slow` で作る。このルートは STDOUT に `slow` を書き、STDIN から 1 行読むまで返らない。spec は STDIN に 1 行書いて要求を終わらせる
- `store_worker` は 4 つ目の引数 `wait` があると、Store を開いた後に STDOUT に `ready` を書き、STDIN から 1 行読んでから追記する
- 別プロセスが変える Postgres の状態（ロックの待ち、プロジェクションの追いつき）は、`wait_until` で上限つきの繰り返しにして待つ。繰り返しの間は `Fiber.yield` だけで、sleep は使わない

# 理由

子プロセスの出力とパイプは、ファイバーが待てる同期の手段になる。ルートが STDIN を待てば、処理中の要求を好きなだけ保てる。受け付けを止めた後のサーバには、新しい HTTP 要求で合図を送れない。`pg_locks` の問い合わせには待つ相手が無いので、上限つきの繰り返しにし、上限は失敗の検出だけに使う。

# 破棄した案

- 固定のポートで起動する
- 一定時間 sleep してからシグナルを送る
- 処理中の要求を、別の HTTP 要求で終わらせる（受け付けを止めた後は届かない）
```

- [ ] **Step 14: 変えたファイルを確かめる**

Run: `git status --short docs && git diff --stat docs`
Expected: `docs/en/02-PHASES.md`、`docs/02-PHASES.md`、`docs/en/00-INSTRUCTION.md`、`docs/00-INSTRUCTION.md`、`docs/en/01-ARCHITECTURE.md`、`docs/01-ARCHITECTURE.md` の変更と、`docs/decisions/20260929-phase6-*.md` の 8 ファイルが新規。

Run: `grep -n "phase 7 and later\|フェーズ 7 以降" docs/en/02-PHASES.md docs/02-PHASES.md`
Expected: 両方の現行フェーズの節に 1 行ずつ出る。

Run: `grep -c "This phase does not start until the user asks for it." docs/en/02-PHASES.md; grep -c "このフェーズはユーザーが明示するまで開始しない。" docs/02-PHASES.md`
Expected: どちらも `1`（フェーズ 7 の分だけが残る）。

---

### Task 2: Store をアダプタに分ける（SQLite）

振る舞いは変えない。`store.cr` の SQLite の部分を `Shomen::SQLiteAdapter` に移し、Store は検査、変換、知らせだけを持つ（D1）。

**Files:**
- Create: `src/shomen/store_adapter.cr`
- Create: `src/shomen/sqlite_adapter.cr`
- Modify: `src/shomen/store.cr`（全体を置き換える）
- Modify: `spec/shomen/store_spec.cr:154-160`、`:242-258`
- Modify: `spec/shomen/boundary_spec.cr:8-12`

**Interfaces:**
- Consumes: 既存の `Shomen::Conflict`、`Shomen::AppendSignal`、`Shomen::Event`、`Shomen::Recorded`
- Produces:
  - `abstract class Shomen::StoreAdapter` — `alias Row = {String, String, String}`（type、payload、at）、`alias Stored = {Int64, String, Int64, String, String}`（id、stream、version、type、payload）、`abstract def key : String`、`abstract def append(stream : String, expected_version : Int64, rows : Array(Row)) : Int64`、`abstract def read(after : Int64, limit : Int32) : Array(Stored)`、`abstract def close : Nil`、`protected def check_version(stream : String, current : Int64, expected : Int64) : Nil`
  - `class Shomen::SQLiteAdapter < Shomen::StoreAdapter` — `initialize(uri : URI)`、`BUSY_TIMEOUT_MS`、`SCHEMA`、`SELECT_VERSION`、`INSERT`、`SELECT_AFTER`、`@lock : Mutex`（spec が `.@lock` で読む）
  - `Shomen::Store` — `@adapter : Shomen::StoreAdapter`（spec が `.@adapter` で読む）。公開 API は変えない

- [ ] **Step 1: spec をアダプタの形に合わせる**

`spec/shomen/store_spec.cr` の "refuses a URL that is not a sqlite3 file"（154〜160 行目）に、知らないスキームの行を足す。

```crystal
  it "refuses a URL that is not a sqlite3 file" do
    expect_raises(ArgumentError, "store URL must use") { Shomen::Store.new("mysql://localhost/app") }
    expect_raises(ArgumentError) { Shomen::Store.new("postgres://localhost/app") }
    expect_raises(ArgumentError) { Shomen::Store.new("sqlite3::memory:") }
    expect_raises(ArgumentError) { Shomen::Store.new("sqlite3://") }
    expect_raises(ArgumentError) { Shomen::Store.new("sqlite3://:memory:") }
    expect_raises(ArgumentError) { Shomen::Store.new("sqlite3:///") }
  end
```

"waits for an append in progress before it reads or closes"（242〜258 行目）の `lock = store.@lock` を次にする。

```crystal
      lock = store.@adapter.as(Shomen::SQLiteAdapter).@lock
```

`spec/shomen/boundary_spec.cr` の最初の例の一覧にアダプタを足す。

```crystal
  it "keeps HTML out of the store and what it requires" do
    %w(store store_adapter sqlite_adapter event recorded conflict append_signal).each do |name|
      source(name).should_not match(/Shomen::(HTML|View|ErrorView)|require "\.\/(html|view|a11y|error_view)"/)
    end
  end
```

- [ ] **Step 2: spec が落ちるのを確かめる**

Run: `crystal spec spec/shomen/store_spec.cr spec/shomen/boundary_spec.cr`
Expected: コンパイルエラー `undefined constant Shomen::SQLiteAdapter`（または `src/shomen/store_adapter.cr` が無い `File::NotFoundError`）。

- [ ] **Step 3: StoreAdapter を書く**

`src/shomen/store_adapter.cr`:

```crystal
require "./conflict"

# The part of Store that differs by database: the SQL, the column types,
# and how appends wait for each other
# (docs/decisions/20260929-phase6-store-adapters.md).
abstract class Shomen::StoreAdapter
  # type, payload, and at of one event to append.
  alias Row = {String, String, String}
  # id, stream, version, type, and payload of one stored event.
  alias Stored = {Int64, String, Int64, String, String}

  # Names the database, so every store on it in this process shares one
  # AppendSignal.
  abstract def key : String

  # Appends the rows as the versions after expected_version and returns
  # the id of the last. When the stream is at any other version, appends
  # nothing and raises Shomen::Conflict.
  abstract def append(stream : String, expected_version : Int64, rows : Array(Row)) : Int64

  abstract def read(after : Int64, limit : Int32) : Array(Stored)

  abstract def close : Nil

  protected def check_version(stream : String, current : Int64, expected : Int64) : Nil
    unless current == expected
      raise Shomen::Conflict.new("stream #{stream} is at version #{current}, expected #{expected}")
    end
  end
end
```

- [ ] **Step 4: SQLiteAdapter を書く**

`src/shomen/sqlite_adapter.cr`（中身は今の `store.cr` から移す。変えたのは、URL を `URI` で受け取ること、`key` を持つこと、版の比較を `check_version` にしたこと、読み出しの SQL を定数にしたこと）:

```crystal
require "uri"
require "db"
require "sqlite3"
require "./store_adapter"

# One SQLite file. Appends, reads, and close in a process take one
# fiber-aware lock per file, and appends then BEGIN IMMEDIATE; other
# processes wait through the busy timeout.
class Shomen::SQLiteAdapter < Shomen::StoreAdapter
  BUSY_TIMEOUT_MS = 5000

  SCHEMA = <<-SQL
    CREATE TABLE IF NOT EXISTS events (
      id      INTEGER PRIMARY KEY,
      stream  TEXT    NOT NULL,
      version INTEGER NOT NULL,
      type    TEXT    NOT NULL,
      payload TEXT    NOT NULL,
      at      TEXT    NOT NULL,
      UNIQUE (stream, version)
    )
    SQL

  SELECT_VERSION = "SELECT COALESCE(MAX(version), 0) FROM events WHERE stream = ?"
  INSERT         = "INSERT INTO events (stream, version, type, payload, at) VALUES (?, ?, ?, ?, ?)"
  SELECT_AFTER   = "SELECT id, stream, version, type, payload FROM events WHERE id > ? ORDER BY id LIMIT ?"

  @@locks = {} of String => Mutex
  @@locks_lock = Mutex.new

  getter key : String
  @db : DB::Database
  @lock : Mutex

  def initialize(uri : URI)
    filename = SQLite3::Connection.filename(uri)
    if filename.empty? || filename == ":memory:" || Dir.exists?(filename)
      raise ArgumentError.new("store URL must name a file")
    end
    Dir.mkdir_p(File.dirname(filename))
    params = uri.query_params
    # Without the cache every statement is a new one that nothing finalizes,
    # so close fails and a failed statement cannot be reset.
    if params.fetch("prepared_statements_cache", "true") != "true"
      raise ArgumentError.new("store URL must not set prepared_statements_cache")
    end
    params["journal_mode"] = "wal" unless params.has_key?("journal_mode")
    params["busy_timeout"] = BUSY_TIMEOUT_MS.to_s unless params.has_key?("busy_timeout")
    uri.query_params = params
    @db = begin
      DB.open(uri.to_s)
    rescue ex : DB::ConnectionRefused
      raise DB::ConnectionRefused.new("cannot open #{filename}", cause: ex)
    end
    begin
      @db.using_connection do |connection|
        connection.exec(SCHEMA)
      rescue ex
        reset(connection, SCHEMA)
        raise ex
      end
    rescue ex
      @db.close
      raise ex
    end
    real = File.realpath(filename)
    @key = "sqlite3://#{real}"
    @lock = @@locks_lock.synchronize { @@locks[real] ||= Mutex.new }
  end

  def append(stream : String, expected_version : Int64, rows : Array(Row)) : Int64
    @lock.synchronize do
      @db.using_connection do |connection|
        begin
          connection.exec("BEGIN IMMEDIATE")
        rescue ex
          reset(connection, "BEGIN IMMEDIATE")
          raise ex
        end
        begin
          id = insert(connection, stream, expected_version, rows)
          connection.exec("COMMIT")
          id
        rescue ex
          rollback(connection)
          raise ex
        end
      end
    end
  end

  def read(after : Int64, limit : Int32) : Array(Stored)
    @lock.synchronize do
      @db.query_all(SELECT_AFTER, after, limit, as: {Int64, String, Int64, String, String})
    end
  end

  # Waits for an append or read in progress, which would otherwise use a
  # statement that close has finalized.
  def close : Nil
    @lock.synchronize { @db.close }
  end

  # SQLite may already have rolled back (a full disk, a trigger), so a
  # failed ROLLBACK must not hide the error that caused it.
  private def rollback(connection : DB::Connection) : Nil
    connection.exec("ROLLBACK")
  rescue
    reset(connection, "ROLLBACK")
  ensure
    [SELECT_VERSION, INSERT, "COMMIT"].each { |sql| reset(connection, sql) }
  end

  # A statement that failed keeps its error until it is reset, and
  # crystal-sqlite3 raises that error again when the connection closes.
  private def reset(connection : DB::Connection, sql : String) : Nil
    LibSQLite3.reset(connection.fetch_or_build_prepared_statement(sql).as(SQLite3::Statement))
  end

  private def insert(connection : DB::Connection, stream : String, expected_version : Int64, rows : Array(Row)) : Int64
    check_version(stream, connection.scalar(SELECT_VERSION, stream).as(Int64), expected_version)
    last_id = 0_i64
    rows.each_with_index(1) do |row, offset|
      type, payload, at = row
      last_id = connection.exec(INSERT, stream, expected_version + offset, type, payload, at).last_insert_id
    end
    last_id
  end
end
```

- [ ] **Step 5: Store をアダプタの上に書き直す**

`src/shomen/store.cr` の全体を次にする。

```crystal
require "uri"
require "./event"
require "./recorded"
require "./append_signal"
require "./store_adapter"
require "./sqlite_adapter"

# The append-only event log. The scheme of the URL picks the database
# (docs/decisions/20260929-phase6-store-adapters.md). After a commit an
# append wakes what waits for it in this process.
class Shomen::Store
  @@signals = {} of String => Shomen::AppendSignal
  @@signals_lock = Mutex.new

  @adapter : Shomen::StoreAdapter
  @signal : Shomen::AppendSignal

  def initialize(url : String)
    uri = begin
      URI.parse(url)
    rescue ex : URI::Error
      raise ArgumentError.new("store URL is not valid: #{ex.message}")
    end
    @adapter = case uri.scheme
               when "sqlite3"
                 Shomen::SQLiteAdapter.new(uri)
               else
                 raise ArgumentError.new("store URL must use sqlite3, got #{uri.scheme.inspect}")
               end
    key = @adapter.key
    @signal = @@signals_lock.synchronize { @@signals[key] ||= Shomen::AppendSignal.new }
  end

  def append(stream : String, expected_version : Int64, events : Array(Shomen::Event)) : Nil
    raise ArgumentError.new("stream must not be empty") if stream.empty?
    raise ArgumentError.new("expected_version must not be negative") if expected_version < 0
    return if events.empty?
    events.each do |event|
      raise ArgumentError.new("#{event.event_type} at must be UTC, got #{event.at}") unless event.at.utc?
    end
    rows = events.map { |event| {event.event_type, event.to_json, event.at.to_rfc3339} }
    @signal.announce(@adapter.append(stream, expected_version, rows))
  end

  # The highest id this process appended to the database, 0 before the first.
  def last_appended : Int64
    @signal.last
  end

  # Waits until this process appends an event with an id above after.
  # False when within passes first.
  def wait_for_append(after : Int64, within : Time::Span) : Bool
    @signal.wait(after, within)
  end

  def read(after : Int64, limit : Int32 = 500) : Array(Shomen::Recorded)
    @adapter.read(after, limit).map do |row|
      id, stream, version, type, payload = row
      Shomen::Recorded.new(id, stream, version, Shomen::Event.decode(type, payload))
    end
  end

  def close : Nil
    @adapter.close
  end
end
```

- [ ] **Step 6: spec が通るのを確かめる**

Run: `crystal spec spec/shomen/store_spec.cr spec/shomen/store_concurrency_spec.cr spec/shomen/projection_spec.cr spec/shomen/boundary_spec.cr spec/shomen/append_signal_spec.cr spec/shomen/sse_spec.cr`
Expected: PASS（0 failures）。

- [ ] **Step 7: 全体を確かめる**

Run: `crystal tool format src spec && crystal spec && crystal build src/shomen.cr --error-trace && rm -f shomen shomen.dwarf`
Expected: 0 failures、警告なし。ブラウザ spec は Chrome があれば走る。

---

### Task 3: Postgres アダプタ（同じ Command API）

`pg` を足し、`Shomen::PostgresAdapter` を書く。SQLite と Postgres で同じ振る舞いを確かめる例を `store_it` で書き直す（受入「SQLite and Postgres share the same Command API」「Two processes on one database: appends from both succeed」の Postgres 版）。

**Files:**
- Modify: `shard.yml`、`shard.lock`、`examples/hello/shard.lock`
- Create: `src/shomen/postgres_adapter.cr`
- Modify: `src/shomen/store.cr`（require とスキームの分岐）
- Create: `spec/support/workers.cr`
- Create: `spec/support/postgres.cr`
- Modify: `spec/support/store.cr`
- Modify: `spec/spec_helper.cr`
- Modify: `spec/shomen/store_spec.cr`（全体を置き換える）
- Modify: `spec/shomen/projection_spec.cr:38-63`
- Modify: `spec/shomen/store_concurrency_spec.cr`（全体を置き換える）
- Modify: `spec/shomen/boundary_spec.cr`
- Create: `spec/shomen/postgres_adapter_spec.cr`

**Interfaces:**
- Consumes: Task 2 の `Shomen::StoreAdapter`（`Row`、`Stored`、`check_version`）と `Shomen::Store`
- Produces:
  - `class Shomen::PostgresAdapter < Shomen::StoreAdapter` — `initialize(uri : URI)`、`LOCK_KEY = 0x73686f6d656e_i64`、`POOL_SIZE = "10"`、`SCHEMA`、`LOCK = "SELECT pg_advisory_xact_lock($1)"`、`SELECT_VERSION`、`INSERT`（`RETURNING id`）、`SELECT_AFTER`、`@db : DB::Database`（spec が `.@db.pool` で読む）
  - `Workers.binary(source : String) : String`、`Workers.remove : Nil`
  - `PostgresSpec.admin_url : String?`、`PostgresSpec.with_database(& : String ->) : Nil`、`postgres_database_it(description, &block : String ->)`
  - `STORE_KINDS`、`with_store_url(kind : String, & : String ->)`、`store_it(description, &block : Shomen::Store, String ->)`、`postgres_it(description, &block : Shomen::Store, String ->)`

- [ ] **Step 1: `pg` を依存に足す**

`shard.yml` の `dependencies:` の最後に足す。

```yaml
  pg:
    github: will/crystal-pg
    version: ">= 0.30.0"
```

Run: `shards install && (cd examples/hello && shards install)`
Expected: `Installing pg (0.30.0)`。`shard.lock` と `examples/hello/shard.lock` に `pg` が入る。`db` は `0.14.0` のまま。

- [ ] **Step 2: spec の道具を書く**

`spec/support/workers.cr`:

```crystal
# Builds a spec worker once per run; the suite removes the binaries at the
# end (docs/decisions/20260929-phase6-process-spec.md).
module Workers
  @@binaries = {} of String => String

  def self.binary(source : String) : String
    @@binaries[source] ||= begin
      binary = File.tempname("shomen-worker")
      output = IO::Memory.new
      status = Process.run("crystal", ["build", source, "-o", binary], output: output, error: output)
      raise "#{source} did not build: #{output}" unless status.success?
      binary
    end
  end

  def self.remove : Nil
    @@binaries.each_value do |binary|
      [binary, "#{binary}.dwarf"].each { |file| File.delete(file) if File.exists?(file) }
    end
  end
end
```

`spec/support/postgres.cr`:

```crystal
require "uri"
require "random/secure"

# Postgres specs run when SHOMEN_SPEC_POSTGRES is a server URL whose user
# may create databases. Each example gets a database of its own and drops
# it afterwards (docs/decisions/20260929-phase6-postgres-spec.md).
module PostgresSpec
  def self.admin_url : String?
    ENV["SHOMEN_SPEC_POSTGRES"]?.presence
  end

  def self.with_database(& : String ->) : Nil
    admin = admin_url || raise "SHOMEN_SPEC_POSTGRES is not set"
    name = "shomen_spec_#{Random::Secure.hex(8)}"
    DB.open(admin) { |db| db.exec("CREATE DATABASE #{name}") }
    uri = URI.parse(admin)
    uri.path = "/#{name}"
    begin
      yield uri.to_s
    ensure
      DB.open(admin) { |db| db.exec("DROP DATABASE IF EXISTS #{name} WITH (FORCE)") }
    end
  end
end

# An example on a new, empty Postgres database; pending without
# SHOMEN_SPEC_POSTGRES.
def postgres_database_it(description : String, file = __FILE__, line = __LINE__, &block : String ->) : Nil
  if PostgresSpec.admin_url
    it(description, file, line) { PostgresSpec.with_database { |url| block.call(url) } }
  else
    pending(description, file, line) { }
  end
end
```

`spec/support/store.cr` の最後に足す（既存の `remove_database`、`with_store`、`note` はそのまま）。

```crystal
STORE_KINDS = {"sqlite3", "postgres"}

# Yields the URL of a new, empty database of kind and removes it afterwards.
def with_store_url(kind : String, & : String ->) : Nil
  if kind == "postgres"
    PostgresSpec.with_database { |url| yield url }
  else
    path = File.tempname("shomen-store", ".sqlite3")
    begin
      yield "sqlite3://#{path}"
    ensure
      remove_database(path)
    end
  end
end

# One example per kind of store, each on a new database; the Postgres one
# is pending without SHOMEN_SPEC_POSTGRES
# (docs/decisions/20260929-phase6-postgres-spec.md).
def store_it(description : String, file = __FILE__, line = __LINE__, &block : Shomen::Store, String ->) : Nil
  STORE_KINDS.each { |kind| store_example(kind, "#{description} (#{kind})", file, line, block) }
end

def postgres_it(description : String, file = __FILE__, line = __LINE__, &block : Shomen::Store, String ->) : Nil
  store_example("postgres", description, file, line, block)
end

private def store_example(kind : String, description : String, file : String, line : Int32, block : Shomen::Store, String ->) : Nil
  if kind == "postgres" && PostgresSpec.admin_url.nil?
    pending(description, file, line) { }
    return
  end
  it(description, file, line) do
    with_store_url(kind) do |url|
      store = Shomen::Store.new(url)
      begin
        block.call(store, url)
      ensure
        store.close
      end
    end
  end
end
```

`spec/spec_helper.cr` の `require "./support/client"` の次に 2 行足し、ファイルの最後に 1 行足す。

```crystal
require "./support/workers"
require "./support/postgres"
```

```crystal

Spec.after_suite { Workers.remove }
```

- [ ] **Step 3: 両方の DB で同じ振る舞いを確かめる spec に書き直す**

`spec/shomen/store_spec.cr` の全体を次にする。SQLite のファイル、ロック、トリガーを使う例は `it` と `with_store` のまま残し、それ以外を `store_it` にする。

```crystal
require "../spec_helper"
require "file_utils"

private def texts(rows : Array(Shomen::Recorded)) : Array(String)
  rows.map { |row| row.event.as(SpecEvents::Noted).text }
end

describe Shomen::Store do
  store_it "numbers each stream from 1 and orders ids across streams" do |store, _|
    store.append("a", 0_i64, note("a1"))
    store.append("b", 0_i64, note("b1"))
    store.append("a", 1_i64, [SpecEvents::Noted.new("a2"), SpecEvents::Noted.new("a3")] of Shomen::Event)
    rows = store.read(after: 0_i64)
    rows.map { |row| {row.id, row.stream, row.version} }.should eq([
      {1_i64, "a", 1_i64}, {2_i64, "b", 1_i64}, {3_i64, "a", 2_i64}, {4_i64, "a", 3_i64},
    ])
    texts(rows).should eq(%w(a1 b1 a2 a3))
  end

  store_it "reads only the events after a given id, up to the limit" do |store, _|
    5.times { |index| store.append("s", index.to_i64, note("n#{index}")) }
    store.read(after: 2_i64, limit: 2).map(&.id).should eq([3_i64, 4_i64])
    store.read(after: 5_i64).should be_empty
  end

  store_it "appends two rows when the same command is handled twice" do |store, _|
    2.times do |version|
      events = SpecEvents::Note.new("same").call.as(Array(Shomen::Event))
      store.append("s", version.to_i64, events)
    end
    rows = store.read(after: 0_i64)
    rows.map(&.version).should eq([1_i64, 2_i64])
    texts(rows).should eq(%w(same same))
  end

  store_it "raises Conflict and adds no row when two appends expect the same version" do |store, _|
    store.append("s", 0_i64, note("first"))
    expect_raises(Shomen::Conflict, "stream s is at version 1, expected 0") do
      store.append("s", 0_i64, note("second"))
    end
    texts(store.read(after: 0_i64)).should eq(["first"])
  end

  store_it "raises Conflict and adds no row when the expected version is ahead" do |store, _|
    expect_raises(Shomen::Conflict, "stream s is at version 0, expected 3") do
      store.append("s", 3_i64, note("ahead"))
    end
    store.read(after: 0_i64).should be_empty
  end

  store_it "stays usable after a conflict" do |store, _|
    store.append("s", 0_i64, note("one"))
    expect_raises(Shomen::Conflict) { store.append("s", 0_i64, note("two")) }
    store.append("s", 1_i64, note("two"))
    texts(store.read(after: 0_i64)).should eq(%w(one two))
  end

  it "closes cleanly after a conflict" do
    with_store do |store|
      store.append("s", 0_i64, note("one"))
      expect_raises(Shomen::Conflict) { store.append("s", 0_i64, note("two")) }
      store.close
    end
  end

  store_it "does nothing for an empty list of events" do |store, _|
    store.append("s", 7_i64, [] of Shomen::Event)
    store.read(after: 0_i64).should be_empty
  end

  store_it "rejects an empty stream name and a negative version" do |store, _|
    expect_raises(ArgumentError) { store.append("", 0_i64, note("x")) }
    expect_raises(ArgumentError) { store.append("s", -1_i64, note("x")) }
  end

  store_it "writes the declared type, the JSON payload, and the time to the second" do |store, url|
    at = Time.utc(2026, 9, 29, 1, 2, 3, nanosecond: 500_000_000)
    store.append("s", 0_i64, [SpecEvents::Noted.new("x", at)] of Shomen::Event)
    DB.open(url) do |db|
      type, payload, stored_at = db.query_one("SELECT type, payload, at FROM events", as: {String, String, String})
      type.should eq("spec.noted")
      JSON.parse(payload)["text"].as_s.should eq("x")
      stored_at.should eq("2026-09-29T01:02:03Z")
    end
    store.read(after: 0_i64).first.event.at.should eq(Time.utc(2026, 9, 29, 1, 2, 3))
  end

  store_it "raises with the type name for a row whose type no event declares" do |store, url|
    DB.open(url) do |db|
      db.exec("INSERT INTO events (stream, version, type, payload, at) VALUES ('s', 1, 'gone', '{}', '2026-09-29T00:00:00Z')")
    end
    expect_raises(ArgumentError, %(unknown event type "gone")) { store.read(after: 0_i64) }
  end

  it "creates a missing directory for a relative path and uses WAL" do
    dir = File.tempname("shomen-store-dir")
    Dir.mkdir(dir)
    begin
      Dir.cd(dir) do
        store = Shomen::Store.new("sqlite3://./var/shomen.sqlite3")
        store.append("s", 0_i64, note("x"))
        File.exists?("var/shomen.sqlite3").should be_true
        File.exists?("var/shomen.sqlite3-wal").should be_true
        store.close
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "stays usable and closes cleanly after another writer held the lock past the busy timeout" do
    path = File.tempname("shomen-store", ".sqlite3")
    begin
      store = Shomen::Store.new("sqlite3://#{path}?busy_timeout=50")
      DB.open("sqlite3://#{path}") do |db|
        db.using_connection do |blocker|
          blocker.exec("BEGIN IMMEDIATE")
          expect_raises(SQLite3::Exception, "database is locked") { store.append("s", 0_i64, note("x")) }
          blocker.exec("ROLLBACK")
        end
      end
      store.read(after: 0_i64).should be_empty
      store.close
    ensure
      remove_database(path)
    end
  end

  it "keeps the insert error and closes cleanly when SQLite rolled the transaction back" do
    with_store do |store, path|
      DB.open("sqlite3://#{path}") do |db|
        db.exec("CREATE TRIGGER boom BEFORE INSERT ON events WHEN NEW.stream = 'boom' BEGIN SELECT RAISE(ROLLBACK, 'boom'); END")
      end
      expect_raises(SQLite3::Exception, "boom") { store.append("boom", 0_i64, note("x")) }
      store.append("s", 0_i64, note("y"))
      texts(store.read(after: 0_i64)).should eq(["y"])
      store.close
    end
  end

  it "refuses a URL that names no SQLite file and a scheme it does not know" do
    expect_raises(ArgumentError, "store URL must use sqlite3, postgres, or postgresql") { Shomen::Store.new("mysql://localhost/app") }
    expect_raises(ArgumentError) { Shomen::Store.new("sqlite3::memory:") }
    expect_raises(ArgumentError) { Shomen::Store.new("sqlite3://") }
    expect_raises(ArgumentError) { Shomen::Store.new("sqlite3://:memory:") }
    expect_raises(ArgumentError) { Shomen::Store.new("sqlite3:///") }
  end

  it "names the file it cannot open" do
    dir = File.tempname("shomen-store-dir")
    Dir.mkdir(dir)
    File.chmod(dir, 0o555)
    path = File.join(dir, "shomen.sqlite3")
    begin
      expect_raises(DB::ConnectionRefused, path) { Shomen::Store.new("sqlite3://#{path}") }
    ensure
      File.chmod(dir, 0o755)
      FileUtils.rm_rf(dir)
    end
  end

  it "closes the database when the events table cannot be created" do
    path = File.tempname("shomen-store", ".sqlite3")
    begin
      DB.open("sqlite3://#{path}") do |db|
        db.exec("CREATE TABLE other (x TEXT)")
        db.exec("CREATE INDEX events ON other (x)")
      end
      before = Dir.children("/dev/fd").size
      expect_raises(SQLite3::Exception, "already an index named events") { Shomen::Store.new("sqlite3://#{path}") }
      Dir.children("/dev/fd").size.should eq(before)
    ensure
      remove_database(path)
    end
  end

  it "closes the database when creating the events table times out" do
    path = File.tempname("shomen-store", ".sqlite3")
    begin
      DB.open("sqlite3://#{path}?journal_mode=wal") { |db| db.exec("CREATE TABLE other (x TEXT)") }
      # SQLite keeps a closed connection's descriptors open while another
      # connection in the process holds a lock, so count after the blocker.
      before = Dir.children("/dev/fd").size
      DB.open("sqlite3://#{path}") do |db|
        db.using_connection do |blocker|
          blocker.exec("BEGIN IMMEDIATE")
          expect_raises(SQLite3::Exception, "database is locked") { Shomen::Store.new("sqlite3://#{path}?busy_timeout=50") }
          blocker.exec("ROLLBACK")
        end
      end
      Dir.children("/dev/fd").size.should eq(before)
    ensure
      remove_database(path)
    end
  end

  it "refuses a URL that turns off the prepared statement cache" do
    path = File.tempname("shomen-store", ".sqlite3")
    expect_raises(ArgumentError, "prepared_statements_cache") do
      Shomen::Store.new("sqlite3://#{path}?prepared_statements_cache=false")
    end
    File.exists?(path).should be_false
  end

  store_it "refuses an event whose time is not UTC and adds no row" do |store, _|
    at = Time.local(2026, 9, 29, 0, 30, 0, location: Time::Location.fixed(9 * 3600))
    expect_raises(ArgumentError, "UTC") do
      store.append("s", 0_i64, [SpecEvents::Noted.new("x", at)] of Shomen::Event)
    end
    store.read(after: 0_i64).should be_empty
  end

  it "writes none of the events when a later one fails" do
    with_store do |store, path|
      DB.open("sqlite3://#{path}") do |db|
        db.exec(%(CREATE TRIGGER bad BEFORE INSERT ON events WHEN NEW.payload LIKE '%"bad"%' BEGIN SELECT RAISE(ABORT, 'bad'); END))
      end
      expect_raises(SQLite3::Exception, "bad") do
        store.append("s", 0_i64, [SpecEvents::Noted.new("ok"), SpecEvents::Noted.new("bad")] of Shomen::Event)
      end
      store.read(after: 0_i64).should be_empty
      store.append("s", 0_i64, note("after"))
      texts(store.read(after: 0_i64)).should eq(["after"])
    end
  end

  it "waits for an append in progress before it reads or closes" do
    with_store do |store|
      lock = store.@adapter.as(Shomen::SQLiteAdapter).@lock
      lock.lock
      done = Channel(String).new(2)
      spawn { store.read(after: 0_i64); done.send("read") }
      spawn { store.close; done.send("close") }
      Fiber.yield
      select
      when finished = done.receive
        fail "#{finished} did not wait for the lock"
      else
      end
      lock.unlock
      2.times { done.receive }
    end
  end

  store_it "tells this process the last id it appended, through any store on the database" do |store, url|
    store.last_appended.should eq(0_i64)
    store.append("a", 0_i64, [SpecEvents::Noted.new("1"), SpecEvents::Noted.new("2")] of Shomen::Event)
    store.last_appended.should eq(2_i64)
    other = Shomen::Store.new(url)
    begin
      other.last_appended.should eq(2_i64)
      other.append("b", 0_i64, note("3"))
      store.last_appended.should eq(3_i64)
    ensure
      other.close
    end
  end

  store_it "announces nothing for an append that conflicts" do |store, _|
    store.append("a", 0_i64, note("1"))
    expect_raises(Shomen::Conflict) { store.append("a", 0_i64, note("2")) }
    store.last_appended.should eq(1_i64)
  end

  store_it "wakes a fiber that waits for an append in this process" do |store, _|
    woke = Channel(Bool).new(1)
    spawn { woke.send(store.wait_for_append(after: 0_i64, within: 5.seconds)) }
    Fiber.yield
    store.append("a", 0_i64, note("1"))
    select
    when value = woke.receive
      value.should be_true
    when timeout(5.seconds)
      fail "the waiting fiber did not wake"
    end
  end
end
```

`spec/shomen/projection_spec.cr` の "rebuilds the read model after a restart" と "sees an event appended through another store on the same file"（38〜63 行目）を次にする。ほかの例は変えない。

```crystal
  store_it "rebuilds the read model after a restart" do |store, url|
    store.append("s", 0_i64, note("one"))
    store.append("s", 1_i64, note("two"))
    second = Shomen::Store.new(url)
    begin
      log = SpecEvents::Log.new(second).catch_up
      log.lines.map { |line| {line.text, line.version} }.should eq([{"one", 1_i64}, {"two", 2_i64}])
    ensure
      second.close
    end
  end

  store_it "sees an event appended through another store on the same database" do |store, url|
    other = Shomen::Store.new(url)
    begin
      log = SpecEvents::Log.new(store).catch_up
      other.append("s", 0_i64, note("elsewhere"))
      log.catch_up.lines.map(&.text).should eq(["elsewhere"])
    ensure
      other.close
    end
  end
```

`spec/shomen/store_concurrency_spec.cr` の全体を次にする。ワーカーのビルドは `Workers.binary` に移す。

```crystal
require "../spec_helper"

describe "Shomen::Store with concurrent writers" do
  store_it "lets many fibers in one process append at once" do |store, url|
    other = Shomen::Store.new(url)
    begin
      done = Channel(Exception?).new
      fibers = 50
      fibers.times do |fiber|
        target = fiber.even? ? store : other
        spawn do
          10.times { |version| target.append("fiber-#{fiber}", version.to_i64, note("#{fiber}-#{version}")) }
          done.send(nil)
        rescue ex
          done.send(ex)
        end
      end
      failures = Array(Exception?).new(fibers) { done.receive }.compact
      failures.map(&.message).should be_empty
      store.read(after: 0_i64, limit: 1000).size.should eq(500)
    ensure
      other.close
    end
  end

  store_it "lets two processes append to one database and a projection see both" do |store, url|
    errors = IO::Memory.new
    worker = Process.new(Workers.binary("spec/support/store_worker.cr"), [url, "worker", "300"], error: errors)
    300.times { |version| store.append("main", version.to_i64, note("main #{version}")) }
    status = worker.wait
    fail "worker failed: #{errors}" unless status.success?

    log = SpecEvents::Log.new(store).catch_up
    log.lines.map(&.id).should eq((1_i64..600_i64).to_a)
    %w(main worker).each do |stream|
      log.lines.select(&.stream.==(stream)).map(&.version).should eq((1_i64..300_i64).to_a)
    end
  end
end
```

`spec/shomen/boundary_spec.cr` の全体を次にする。

```crystal
require "../spec_helper"

private def source(name : String) : String
  File.read("src/shomen/#{name}.cr")
end

describe "module boundaries" do
  it "keeps HTML out of the store and what it requires" do
    %w(store store_adapter sqlite_adapter postgres_adapter event recorded conflict append_signal).each do |name|
      source(name).should_not match(/Shomen::(HTML|View|ErrorView)|require "\.\/(html|view|a11y|error_view)"/)
    end
  end

  it "keeps the database out of commands, events, projections, and SSE" do
    %w(command event rejected recorded projection append_signal sse).each do |name|
      source(name).should_not match(/sqlite|postgres|\bpg\b/i)
    end
  end
end
```

- [ ] **Step 4: Postgres だけの振る舞いの spec を書く**

`spec/shomen/postgres_adapter_spec.cr`:

```crystal
require "../spec_helper"

private def with_query(url : String, name : String, value : String) : String
  uri = URI.parse(url)
  params = uri.query_params
  params[name] = value
  uri.query_params = params
  uri.to_s
end

private def pool(store : Shomen::Store) : DB::Pool(DB::Connection)
  store.@adapter.as(Shomen::PostgresAdapter).@db.pool
end

describe Shomen::PostgresAdapter do
  it "refuses a URL without a database name before it connects" do
    expect_raises(ArgumentError, "store URL must name a database") { Shomen::Store.new("postgres://localhost") }
    expect_raises(ArgumentError, "store URL must name a database") { Shomen::Store.new("postgresql://localhost/") }
  end

  postgres_it "creates the events table with BIGINT integers and an identity cached one at a time" do |_, url|
    DB.open(url) do |db|
      columns = db.query_all(
        "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'events' ORDER BY ordinal_position",
        as: {String, String},
      )
      columns.should eq([
        {"id", "bigint"}, {"stream", "text"}, {"version", "bigint"},
        {"type", "text"}, {"payload", "text"}, {"at", "text"},
      ])
      db.scalar("SELECT seqcache FROM pg_sequence WHERE seqrelid = pg_get_serial_sequence('events', 'id')::regclass").should eq(1_i64)
    end
  end

  postgres_it "accepts the postgresql scheme for the same database" do |store, url|
    uri = URI.parse(url)
    uri.scheme = "postgresql"
    other = Shomen::Store.new(uri.to_s)
    begin
      other.append("s", 0_i64, note("x"))
      store.read(after: 0_i64).map(&.stream).should eq(["s"])
    ensure
      other.close
    end
  end

  postgres_it "bounds the pool at 10 connections unless the URL sets it" do |store, url|
    pool(store).@max_pool_size.should eq(10)
    pool(store).@max_idle_pool_size.should eq(10)
    other = Shomen::Store.new(with_query(url, "max_pool_size", "3"))
    begin
      pool(other).@max_pool_size.should eq(3)
      pool(other).@max_idle_pool_size.should eq(3)
    ensure
      other.close
    end
  end

  postgres_database_it "opens one events table when stores start at once on an empty database" do |url|
    done = Channel(Shomen::Store | Exception).new
    4.times do
      spawn do
        done.send(Shomen::Store.new(url))
      rescue ex
        done.send(ex)
      end
    end
    results = Array(Shomen::Store | Exception).new(4) { done.receive }
    results.each { |result| result.close if result.is_a?(Shomen::Store) }
    results.compact_map(&.as?(Exception)).map(&.message).should be_empty
    DB.open(url) { |db| db.scalar("SELECT count(*) FROM pg_tables WHERE tablename = 'events'").should eq(1_i64) }
  end

  postgres_it "writes none of the events when a later one fails" do |store, url|
    DB.open(url) { |db| db.exec(%(ALTER TABLE events ADD CONSTRAINT bad CHECK (payload NOT LIKE '%"bad"%'))) }
    expect_raises(PQ::PQError, "bad") do
      store.append("s", 0_i64, [SpecEvents::Noted.new("ok"), SpecEvents::Noted.new("bad")] of Shomen::Event)
    end
    store.read(after: 0_i64).should be_empty
    store.append("s", 0_i64, note("after"))
    store.read(after: 0_i64).map(&.version).should eq([1_i64])
  end
end
```

- [ ] **Step 5: spec が落ちるのを確かめる**

Run: `SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec spec/shomen/postgres_adapter_spec.cr`
Expected: コンパイルエラー `undefined constant Shomen::PostgresAdapter`。

- [ ] **Step 6: PostgresAdapter を書く**

`src/shomen/postgres_adapter.cr`:

```crystal
require "uri"
require "db"
require "pg"
require "./store_adapter"

# A Postgres database. Every append, and the creation of the events table,
# first takes one transaction-scoped advisory lock and commits right away,
# so ids become visible in increasing order
# (docs/decisions/20260929-scale-event-order.md,
# docs/decisions/20260929-phase6-postgres-adapter.md).
class Shomen::PostgresAdapter < Shomen::StoreAdapter
  # "shomen" in ASCII.
  LOCK_KEY  = 0x73686f6d656e_i64
  POOL_SIZE = "10"

  SCHEMA = <<-SQL
    CREATE TABLE IF NOT EXISTS events (
      id      BIGINT GENERATED ALWAYS AS IDENTITY (CACHE 1) PRIMARY KEY,
      stream  TEXT   NOT NULL,
      version BIGINT NOT NULL,
      type    TEXT   NOT NULL,
      payload TEXT   NOT NULL,
      at      TEXT   NOT NULL,
      UNIQUE (stream, version)
    )
    SQL

  LOCK           = "SELECT pg_advisory_xact_lock($1)"
  SELECT_VERSION = "SELECT COALESCE(MAX(version), 0) FROM events WHERE stream = $1"
  INSERT         = "INSERT INTO events (stream, version, type, payload, at) VALUES ($1, $2, $3, $4, $5) RETURNING id"
  SELECT_AFTER   = "SELECT id, stream, version, type, payload FROM events WHERE id > $1 ORDER BY id LIMIT $2"

  getter key : String
  @db : DB::Database

  def initialize(uri : URI)
    database = uri.path.lchop('/')
    raise ArgumentError.new("store URL must name a database") if database.empty?
    @key = "postgres://#{uri.host}:#{uri.port}/#{database}"
    params = uri.query_params
    params["max_pool_size"] = POOL_SIZE unless params.has_key?("max_pool_size")
    params["max_idle_pool_size"] = params["max_pool_size"] unless params.has_key?("max_idle_pool_size")
    uri.query_params = params
    @db = DB.open(uri.to_s)
    begin
      locked { |connection| connection.exec(SCHEMA) }
    rescue ex
      @db.close
      raise ex
    end
  end

  def append(stream : String, expected_version : Int64, rows : Array(Row)) : Int64
    locked do |connection|
      check_version(stream, connection.scalar(SELECT_VERSION, stream).as(Int64), expected_version)
      last_id = 0_i64
      rows.each_with_index(1) do |row, offset|
        type, payload, at = row
        last_id = connection.scalar(INSERT, stream, expected_version + offset, type, payload, at).as(Int64)
      end
      last_id
    end
  end

  def read(after : Int64, limit : Int32) : Array(Stored)
    @db.query_all(SELECT_AFTER, after, limit, as: {Int64, String, Int64, String, String})
  end

  def close : Nil
    @db.close
  end

  # Runs the block in a transaction that holds the lock, and commits as
  # soon as the block returns.
  private def locked(& : DB::Connection -> T) : T forall T
    @db.using_connection do |connection|
      connection.exec("BEGIN")
      begin
        connection.exec(LOCK, LOCK_KEY)
        result = yield connection
        connection.exec("COMMIT")
        result
      rescue ex
        rollback(connection)
        raise ex
      end
    end
  end

  # A connection that broke cannot roll back, and the error that broke it
  # matters more.
  private def rollback(connection : DB::Connection) : Nil
    connection.exec("ROLLBACK")
  rescue
  end
end
```

`src/shomen/store.cr` の require に `require "./postgres_adapter"` を `require "./sqlite_adapter"` の次に足し、`initialize` のスキームの分岐を次にする。

```crystal
    @adapter = case uri.scheme
               when "sqlite3"
                 Shomen::SQLiteAdapter.new(uri)
               when "postgres", "postgresql"
                 Shomen::PostgresAdapter.new(uri)
               else
                 raise ArgumentError.new("store URL must use sqlite3, postgres, or postgresql, got #{uri.scheme.inspect}")
               end
```

- [ ] **Step 7: Postgres ありで通るのを確かめる**

Run: `SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec spec/shomen/postgres_adapter_spec.cr spec/shomen/store_spec.cr spec/shomen/projection_spec.cr spec/shomen/store_concurrency_spec.cr spec/shomen/boundary_spec.cr`
Expected: PASS（0 failures、0 pending）。`(postgres)` の付いた例が並ぶ。

Run: `/opt/homebrew/opt/postgresql@18/bin/psql -h localhost -d postgres -Atc "SELECT count(*) FROM pg_database WHERE datname LIKE 'shomen_spec_%'"`
Expected: `0`（例ごとの DB が消えている）。

- [ ] **Step 8: Postgres なしで pending になるのを確かめる**

Run: `env -u SHOMEN_SPEC_POSTGRES crystal spec spec/shomen/postgres_adapter_spec.cr spec/shomen/store_spec.cr`
Expected: 0 failures。`(postgres)` の例と Postgres だけの例が pending。"refuses a URL without a database name before it connects" は走って通る。

- [ ] **Step 9: 全体を確かめる**

Run: `crystal tool format src spec && SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec && crystal build src/shomen.cr --error-trace && rm -f shomen shomen.dwarf && (cd examples/hello && crystal spec)`
Expected: 0 failures、警告なし。

---

### Task 4: Postgres の追記の順序（受入）

受入「While one append transaction is open after its insert, an append from another process waits until the first commits」と「Concurrent appends from two processes: a projection that follows its checkpoint receives every event once, in `id` order」を確かめる。実装は Task 3 で済んでいるので、最後にロックを外して spec が落ちることも確かめる。

**Files:**
- Modify: `spec/support/store_worker.cr`
- Create: `spec/support/wait.cr`
- Modify: `spec/spec_helper.cr`
- Modify: `spec/shomen/postgres_adapter_spec.cr`

**Interfaces:**
- Consumes: Task 3 の `Shomen::PostgresAdapter::LOCK`、`LOCK_KEY`、`INSERT`、`postgres_it`、`Workers.binary`
- Produces: `wait_until(within : Time::Span = 5.seconds, & : -> Bool) : Nil`。`store_worker` の 4 つ目の引数 `wait`（STDOUT に `ready`、STDIN の 1 行で追記を始める）

- [ ] **Step 1: ワーカーと待ちの道具を書く**

`spec/support/store_worker.cr` の全体を次にする。

```crystal
require "../../src/shomen/store"
require "../../src/shomen/command"
require "./events"

# Appends count events to stream. With a fourth argument "wait", it opens
# the store, writes "ready", and appends after a line on standard input
# (docs/decisions/20260929-phase6-process-spec.md).
url, stream, count = ARGV
store = Shomen::Store.new(url)
if ARGV[3]? == "wait"
  STDOUT.puts "ready"
  STDOUT.flush
  STDIN.gets
end
count.to_i64.times do |version|
  store.append(stream, version, [SpecEvents::Noted.new("#{stream} #{version}")] of Shomen::Event)
end
store.close
```

`spec/support/wait.cr`:

```crystal
# Checks the condition until it holds, for state another process changes
# and nothing in this one can wait on. within only detects a failure
# (docs/decisions/20260929-phase6-process-spec.md).
def wait_until(within : Time::Span = 5.seconds, & : -> Bool) : Nil
  deadline = Time.instant + within
  until yield
    fail "the condition did not hold within #{within}" if Time.instant > deadline
    Fiber.yield
  end
end
```

`spec/spec_helper.cr` の `require "./support/postgres"` の次に足す。

```crystal
require "./support/wait"
```

- [ ] **Step 2: 受入の spec を書く**

`spec/shomen/postgres_adapter_spec.cr` の `describe` の最後（`end` の前）に足す。

```crystal
  postgres_it "makes an append from another process wait while an append transaction is open after its insert" do |_, url|
    worker = Process.new(
      Workers.binary("spec/support/store_worker.cr"), [url, "worker", "1", "wait"],
      input: :pipe, output: :pipe, error: :inherit,
    )
    worker.output.gets.should eq("ready")
    DB.open(url) do |db|
      db.using_connection do |open|
        # The statements an append runs, stopped before its COMMIT.
        open.exec("BEGIN")
        open.exec(Shomen::PostgresAdapter::LOCK, Shomen::PostgresAdapter::LOCK_KEY)
        open.scalar(Shomen::PostgresAdapter::INSERT, "open", 1_i64, "spec.noted", %({"text":"open"}), "2026-09-29T00:00:00Z")
        worker.input.puts("go")
        worker.input.flush
        wait_until { db.scalar("SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND NOT granted") == 1_i64 }
        worker.terminated?.should be_false
        open.exec("COMMIT")
      end
      worker.wait.success?.should be_true
      db.query_all("SELECT id, stream FROM events ORDER BY id", as: {Int64, String}).should eq([
        {1_i64, "open"}, {2_i64, "worker"},
      ])
    end
  end

  postgres_it "gives a projection that follows its checkpoint every event once, in id order, while two processes append" do |store, url|
    binary = Workers.binary("spec/support/store_worker.cr")
    workers = %w(left right).map { |stream| Process.new(binary, [url, stream, "300"], error: :inherit) }
    log = SpecEvents::Log.new(store)
    wait_until(60.seconds) { log.catch_up.lines.size >= 600 }
    workers.each { |worker| worker.wait.success?.should be_true }
    ids = log.catch_up.lines.map(&.id)
    ids.size.should eq(600)
    ids.should eq(ids.sort.uniq)
    ids.should eq(store.read(after: 0_i64, limit: 1000).map(&.id))
  end
```

- [ ] **Step 3: spec が通るのを確かめる**

Run: `SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec spec/shomen/postgres_adapter_spec.cr spec/shomen/store_concurrency_spec.cr`
Expected: PASS（0 failures）。

- [ ] **Step 4: ロックを外すと落ちるのを確かめる**

`src/shomen/postgres_adapter.cr` の `locked` の中の `connection.exec(LOCK, LOCK_KEY)` の行を一時的にコメントにする。

Run: `SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec spec/shomen/postgres_adapter_spec.cr -e "makes an append from another process wait"`
Expected: FAIL（`the condition did not hold within 00:00:05`。ワーカーはロックを待たずに追記して終わる）。

コメントを外して元に戻し、同じコマンドが PASS に戻るのを確かめる。2 つ目の受入（順序）は競合の起きる確率に左右されるので、ロックを外しても必ず落ちるとは限らない。この確認は 1 つ目だけで行う。

- [ ] **Step 5: 全体を確かめる**

Run: `crystal tool format src spec && SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec && grep -n "connection.exec(LOCK, LOCK_KEY)" src/shomen/postgres_adapter.cr`
Expected: 0 failures。grep は 1 行を出し、その行は `#` で始まらない（Step 4 の名残が無い）。

---

### Task 5: `SHOMEN_ENV=production`（鍵の必須化、500 の本文、例外のログ）

受入「With `SHOMEN_ENV=production` and no `SHOMEN_SECRET`, startup fails with a message that names the variable」と、作るもの「`SHOMEN_ENV=production` hides the exception body」「requires `SHOMEN_SECRET` of 32 bytes or more」（D4）。起動に失敗するプロセスの確認は Task 9 で行う。

**Files:**
- Create: `spec/support/env.cr`
- Modify: `spec/spec_helper.cr`
- Create: `spec/shomen/production_spec.cr`
- Modify: `spec/shomen/server_spec.cr`（例を 1 つ足す）
- Modify: `src/shomen/server.cr`

**Interfaces:**
- Consumes: 既存の `Shomen::Server`、`Shomen::ErrorView`、`call_with`（`spec/support/client.cr`）、`ServerRoutes` の `/phase1/boom` と `/phase1/bad/:id`
- Produces:
  - `Shomen::Server::MIN_SECRET_BYTES = 32`、`Shomen::Server::Log`（source `"shomen"`）、`Shomen::Server.production? : Bool`、`@production : Bool`
  - `with_env(values : Hash(String, _), &) : Nil`（`nil` の値は変数を消す）、`LONG_SECRET`（32 バイト）

- [ ] **Step 1: spec の道具を書く**

`spec/support/env.cr`:

```crystal
# A secret long enough for SHOMEN_ENV=production.
LONG_SECRET = "0123456789abcdef0123456789abcdef"

# Sets the variables for the block, removing those whose value is nil,
# and restores them afterwards.
def with_env(values : Hash(String, _), &) : Nil
  saved = {} of String => String?
  values.each_key { |name| saved[name] = ENV[name]? }
  apply_env(values)
  begin
    yield
  ensure
    apply_env(saved)
  end
end

private def apply_env(values : Hash(String, _)) : Nil
  values.each do |name, value|
    if value
      ENV[name] = value
    else
      ENV.delete(name)
    end
  end
end
```

`spec/spec_helper.cr` を次のように直す。`require "../src/shomen"` の次に `require "log/spec"` を、`require "./support/client"` の次に `require "./support/env"` を足し、`Spec.after_suite` の前に `Log.setup(:none)` を足す。直した後のファイル全体:

```crystal
require "spec"
ENV["SHOMEN_SECRET"] = "spec-secret"
require "../src/shomen"
require "log/spec"
require "./support/process"
require "./support/client"
require "./support/env"
require "./support/workers"
require "./support/postgres"
require "./support/wait"
require "./support/routes"
require "./support/events"
require "./support/store"
require "./support/projections"
require "./support/fragment_routes"
require "./support/browser"
require "./support/browser_routes"
require "./support/sse_client"
require "./support/sse_routes"
require "./support/island_routes"
require "./support/page_spy"

# Specs read the log with Log.capture; nothing else prints it.
Log.setup(:none)

Spec.after_suite { Workers.remove }
```

- [ ] **Step 2: 失敗する spec を書く**

`spec/shomen/production_spec.cr`:

```crystal
require "../spec_helper"

describe "SHOMEN_ENV=production" do
  it "refuses to start without SHOMEN_SECRET and names the variable" do
    with_env({"SHOMEN_ENV" => "production", "SHOMEN_SECRET" => nil}) do
      expect_raises(ArgumentError, "SHOMEN_SECRET must be set to at least 32 bytes when SHOMEN_ENV=production") do
        Shomen::Server.new
      end
    end
  end

  it "refuses a SHOMEN_SECRET shorter than 32 bytes and takes one of 32" do
    with_env({"SHOMEN_ENV" => "production", "SHOMEN_SECRET" => "x" * 31}) do
      expect_raises(ArgumentError, "SHOMEN_SECRET") { Shomen::Server.new }
    end
    with_env({"SHOMEN_ENV" => "production", "SHOMEN_SECRET" => "x" * 32}) do
      Shomen::Server.new.should be_a(Shomen::Server)
    end
  end

  it "refuses a short secret passed directly" do
    with_env({"SHOMEN_ENV" => "production"}) do
      expect_raises(ArgumentError, "secret must be at least 32 bytes when SHOMEN_ENV=production") do
        Shomen::Server.new(secret: "short")
      end
    end
  end

  it "reads only the value production as production" do
    with_env({"SHOMEN_ENV" => "Production"}) do
      Shomen::Server.production?.should be_false
      Shomen::Server.new(secret: "short").should be_a(Shomen::Server)
    end
  end

  it "hides the exception message and logs the exception" do
    with_env({"SHOMEN_ENV" => "production"}) do
      Log.capture("shomen") do |logs|
        response = call_with(Shomen::Server.new(secret: LONG_SECRET), "GET", "/phase1/boom")
        response.status_code.should eq(500)
        response.body.should contain("<title>Error</title>")
        response.body.should_not contain("boom")
        logs.check(:error, "unhandled exception")
        logs.entry.exception.try(&.message).should eq("boom <script>")
      end
    end
  end

  it "still explains bad input" do
    with_env({"SHOMEN_ENV" => "production"}) do
      response = call_with(Shomen::Server.new(secret: LONG_SECRET), "GET", "/phase1/bad/abc")
      response.status_code.should eq(400)
      response.body.should contain("invalid id")
    end
  end
end
```

`spec/shomen/server_spec.cr` の "returns 500 HTML and escapes the exception message" の次に足す。

```crystal
  it "logs an unhandled exception outside production too" do
    Log.capture("shomen") do |logs|
      call_server("GET", "/phase1/boom").status_code.should eq(500)
      logs.check(:error, "unhandled exception")
      logs.entry.exception.try(&.message).should eq("boom <script>")
    end
  end
```

- [ ] **Step 3: spec が落ちるのを確かめる**

Run: `crystal spec spec/shomen/production_spec.cr spec/shomen/server_spec.cr`
Expected: コンパイルエラー `undefined method 'production?' for Shomen::Server.class`。

- [ ] **Step 4: Server を直す**

`src/shomen/server.cr` の require の最後に足す。

```crystal
require "log"
```

定数の並び（`CONFLICT_DETAIL` の次）に足す。

```crystal
  MIN_SECRET_BYTES = 32

  Log = ::Log.for("shomen")
```

`self.secret_from_env` と `initialize` を次にし、`self.production?` を足す。

```crystal
  # SHOMEN_ENV=production, read when a server is made
  # (docs/decisions/20260929-phase6-production.md).
  def self.production? : Bool
    ENV["SHOMEN_ENV"]? == "production"
  end

  def self.secret_from_env : String
    secret = ENV["SHOMEN_SECRET"]?.presence
    if production?
      unless secret && secret.bytesize >= MIN_SECRET_BYTES
        raise ArgumentError.new("SHOMEN_SECRET must be set to at least #{MIN_SECRET_BYTES} bytes when SHOMEN_ENV=production")
      end
      return secret
    end
    return secret if secret
    @@generated_secret ||= begin
      STDERR.puts "shomen: SHOMEN_SECRET is not set; using a random secret until restart"
      Random::Secure.hex(32)
    end
  end

  def initialize(secret : String = Shomen::Server.secret_from_env, @https : Bool = false)
    @sessions = Shomen::SessionStore.new(secret)
    @production = Shomen::Server.production?
    check_length(secret, "secret") if @production
  end
```

`respond` の最後の `rescue ex` を次にする。

```crystal
  rescue ex
    Log.error(exception: ex) { "unhandled exception" }
    error_response(500, "Error", @production ? nil : ex.message)
```

`error_response` の前に足す。

```crystal
  private def check_length(secret : String, name : String) : Nil
    if secret.bytesize < MIN_SECRET_BYTES
      raise ArgumentError.new("#{name} must be at least #{MIN_SECRET_BYTES} bytes when SHOMEN_ENV=production")
    end
  end
```

- [ ] **Step 5: spec が通るのを確かめる**

Run: `crystal spec spec/shomen/production_spec.cr spec/shomen/server_spec.cr spec/shomen/csrf_spec.cr`
Expected: PASS（0 failures）。500 の例を走らせても、spec の出力にログの行が出ない。

- [ ] **Step 6: 全体を確かめる**

Run: `crystal tool format src spec && crystal spec && crystal build src/shomen.cr --error-trace && rm -f shomen shomen.dwarf`
Expected: 0 failures、警告なし。

---

### Task 6: `SHOMEN_SECRET_VERIFY`（鍵の入れ替え）

受入「A cookie and a CSRF token signed with `SHOMEN_SECRET_VERIFY` are accepted, and the response reissues the cookie under `SHOMEN_SECRET`」（D5、`20260929-scale-secret-rotation.md`）。

**Files:**
- Modify: `src/shomen/session.cr`
- Modify: `src/shomen/session_store.cr`（全体を置き換える）
- Modify: `src/shomen/server.cr`
- Modify: `spec/shomen/session_store_spec.cr`（例を足す）
- Create: `spec/shomen/secret_rotation_spec.cr`
- Modify: `spec/shomen/production_spec.cr`（例を足す）

**Interfaces:**
- Consumes: Task 5 の `Shomen::Server.production?`、`MIN_SECRET_BYTES`、`check_length`、`with_env`、`LONG_SECRET`
- Produces:
  - `Shomen::Session#reissue? : Bool`、`Shomen::Session.new(id, fresh, csrf_token, reissue = false)`
  - `Shomen::SessionStore.new(secret : String, verify_secret : String? = nil)`、`Shomen::SessionStore#csrf_valid?(session : Shomen::Session, sent : String) : Bool`
  - `Shomen::Server.verify_secret_from_env : String?`、`Shomen::Server.new(secret:, verify_secret:, https:)`

- [ ] **Step 1: 失敗する spec を書く**

`spec/shomen/session_store_spec.cr` の `describe` の最後（`end` の前）に足す。

```crystal
  it "loads a cookie signed with the verify secret and marks it for reissue" do
    old = Shomen::SessionStore.new("old")
    first = old.load(nil)
    rotated = Shomen::SessionStore.new("new", "old")
    again = rotated.load(cookie_value(old, first))
    again.fresh?.should be_false
    again.reissue?.should be_true
    again.id.should eq(first.id)
    again.csrf_token.should_not eq(first.csrf_token)
  end

  it "does not reissue a cookie signed with the secret" do
    store = Shomen::SessionStore.new("new", "old")
    first = store.load(nil)
    store.load(cookie_value(store, first)).reissue?.should be_false
  end

  it "signs only with the secret" do
    store = Shomen::SessionStore.new("new", "old")
    value = cookie_value(store, store.load(nil))
    Shomen::SessionStore.new("new").load(value).fresh?.should be_false
    Shomen::SessionStore.new("old").load(value).fresh?.should be_true
  end

  it "accepts a csrf token made with either secret" do
    old = Shomen::SessionStore.new("old")
    first = old.load(nil)
    rotated = Shomen::SessionStore.new("new", "old")
    again = rotated.load(cookie_value(old, first))
    rotated.csrf_valid?(again, first.csrf_token).should be_true
    rotated.csrf_valid?(again, again.csrf_token).should be_true
    rotated.csrf_valid?(again, "wrong").should be_false
    Shomen::SessionStore.new("new").csrf_valid?(again, first.csrf_token).should be_false
  end
```

`spec/shomen/secret_rotation_spec.cr`:

```crystal
require "../spec_helper"

ROTATION_OLD = "old-secret-0123456789abcdef012345"
ROTATION_NEW = "new-secret-0123456789abcdef012345"

# The session cookie and the csrf token of a GET to /phase2/token.
private def token_page(server : Shomen::Server, cookie : String? = nil) : {String, String}
  response = call_with(server, "GET", "/phase2/token", cookie: cookie)
  {session_cookie(response), response.body}
end

private def post_echo(server : Shomen::Server, cookie : String, token : String) : HTTP::Client::Response
  call_with(server, "POST", "/phase2/echo", cookie: cookie, body: URI::Params.encode({"_csrf" => token}))
end

private def cookie_value(cookie : String) : String
  cookie.split('=', 2)[1]
end

private def session_id(cookie : String) : String
  cookie_value(cookie).rpartition('.')[0]
end

describe "SHOMEN_SECRET_VERIFY" do
  it "accepts a cookie and a CSRF token signed with it, and reissues the cookie under SHOMEN_SECRET" do
    old_server = Shomen::Server.new(secret: ROTATION_OLD)
    new_server = Shomen::Server.new(secret: ROTATION_NEW, verify_secret: ROTATION_OLD)
    cookie, token = token_page(old_server)
    response = post_echo(new_server, cookie, token)
    response.status_code.should eq(200)
    reissued = session_cookie(response)
    reissued.should_not eq(cookie)
    session = Shomen::SessionStore.new(ROTATION_NEW).load(cookie_value(reissued))
    session.fresh?.should be_false
    session.id.should eq(session_id(cookie))
  end

  it "accepts a form rendered under the old secret after the cookie was reissued" do
    old_server = Shomen::Server.new(secret: ROTATION_OLD)
    new_server = Shomen::Server.new(secret: ROTATION_NEW, verify_secret: ROTATION_OLD)
    cookie, old_token = token_page(old_server)
    reissued, _ = token_page(new_server, cookie)
    post_echo(new_server, reissued, old_token).status_code.should eq(200)
  end

  it "lets a process that still signs with the old secret accept the new one while they swap" do
    before_swap = Shomen::Server.new(secret: ROTATION_OLD, verify_secret: ROTATION_NEW)
    after_swap = Shomen::Server.new(secret: ROTATION_NEW, verify_secret: ROTATION_OLD)
    cookie, token = token_page(after_swap)
    response = post_echo(before_swap, cookie, token)
    response.status_code.should eq(200)
    Shomen::SessionStore.new(ROTATION_OLD).load(cookie_value(session_cookie(response))).id.should eq(session_id(cookie))
  end

  it "refuses the old cookie and token once the verify secret is gone" do
    cookie, token = token_page(Shomen::Server.new(secret: ROTATION_OLD))
    post_echo(Shomen::Server.new(secret: ROTATION_NEW), cookie, token).status_code.should eq(403)
  end

  it "reads SHOMEN_SECRET_VERIFY and treats an empty one as unset" do
    with_env({"SHOMEN_SECRET_VERIFY" => ROTATION_OLD}) do
      Shomen::Server.verify_secret_from_env.should eq(ROTATION_OLD)
    end
    with_env({"SHOMEN_SECRET_VERIFY" => ""}) do
      Shomen::Server.verify_secret_from_env.should be_nil
    end
  end
end
```

`spec/shomen/production_spec.cr` の `describe` の最後に足す。

```crystal
  it "refuses a SHOMEN_SECRET_VERIFY shorter than 32 bytes and names it" do
    with_env({"SHOMEN_ENV" => "production", "SHOMEN_SECRET" => LONG_SECRET, "SHOMEN_SECRET_VERIFY" => "x" * 31}) do
      expect_raises(ArgumentError, "SHOMEN_SECRET_VERIFY must be at least 32 bytes when SHOMEN_ENV=production") do
        Shomen::Server.new
      end
    end
  end

  it "refuses a short verify secret passed directly" do
    with_env({"SHOMEN_ENV" => "production"}) do
      expect_raises(ArgumentError, "verify_secret must be at least 32 bytes when SHOMEN_ENV=production") do
        Shomen::Server.new(secret: LONG_SECRET, verify_secret: "short")
      end
    end
  end
```

- [ ] **Step 2: spec が落ちるのを確かめる**

Run: `crystal spec spec/shomen/session_store_spec.cr spec/shomen/secret_rotation_spec.cr spec/shomen/production_spec.cr`
Expected: コンパイルエラー（`wrong number of arguments for 'Shomen::SessionStore.new'` か `undefined method 'reissue?'`）。

- [ ] **Step 3: Session と SessionStore を直す**

`src/shomen/session.cr` の全体を次にする。

```crystal
class Shomen::Session
  COOKIE = "shomen_session"

  getter id : String
  getter? fresh : Bool
  getter csrf_token : String
  # Only SHOMEN_SECRET_VERIFY verified the cookie, so the response sends
  # it again under SHOMEN_SECRET.
  getter? reissue : Bool

  def initialize(@id : String, @fresh : Bool, @csrf_token : String, @reissue : Bool = false)
  end
end
```

`src/shomen/session_store.cr` の全体を次にする。

```crystal
require "http"
require "openssl/hmac"
require "crypto/subtle"
require "random/secure"

# Holds no server-side state: the id is signed and the csrf token is
# derived from it, so a session survives a restart with the same secret.
# A second secret only verifies, so the secret can change without ending
# sessions (docs/decisions/20260929-phase6-secret-verify.md).
class Shomen::SessionStore
  def initialize(@secret : String, @verify_secret : String? = nil)
  end

  def load(cookie_value : String?) : Shomen::Session
    if cookie_value
      if id = verify(cookie_value, @secret)
        return Shomen::Session.new(id, false, csrf_token_for(@secret, id))
      end
      if (key = @verify_secret) && (id = verify(cookie_value, key))
        return Shomen::Session.new(id, false, csrf_token_for(@secret, id), reissue: true)
      end
    end
    id = Random::Secure.hex(32)
    Shomen::Session.new(id, true, csrf_token_for(@secret, id))
  end

  # True for the session's token under either secret, so a form rendered
  # before the secret changed still posts.
  def csrf_valid?(session : Shomen::Session, sent : String) : Bool
    keys.any? { |key| Crypto::Subtle.constant_time_compare(sent, csrf_token_for(key, session.id)) }
  end

  def cookie(session : Shomen::Session, secure : Bool) : HTTP::Cookie
    HTTP::Cookie.new(
      Shomen::Session::COOKIE,
      "#{session.id}.#{sign(@secret, session.id)}",
      path: "/",
      http_only: true,
      secure: secure,
      samesite: HTTP::Cookie::SameSite::Lax,
    )
  end

  private def keys : Array(String)
    if key = @verify_secret
      [@secret, key]
    else
      [@secret]
    end
  end

  private def sign(key : String, id : String) : String
    OpenSSL::HMAC.hexdigest(:sha256, key, id)
  end

  # The "csrf:" prefix keeps the token distinct from the cookie signature.
  private def csrf_token_for(key : String, id : String) : String
    OpenSSL::HMAC.hexdigest(:sha256, key, "csrf:" + id)
  end

  private def verify(value : String, key : String) : String?
    id, dot, signature = value.rpartition('.')
    return nil if dot.empty? || id.empty?
    Crypto::Subtle.constant_time_compare(sign(key, id), signature) ? id : nil
  end
end
```

- [ ] **Step 4: Server を直す**

`src/shomen/server.cr` の `self.secret_from_env` の次に足す。

```crystal
  def self.verify_secret_from_env : String?
    secret = ENV["SHOMEN_SECRET_VERIFY"]?.presence
    if secret && production? && secret.bytesize < MIN_SECRET_BYTES
      raise ArgumentError.new("SHOMEN_SECRET_VERIFY must be at least #{MIN_SECRET_BYTES} bytes when SHOMEN_ENV=production")
    end
    secret
  end
```

`initialize` を次にする。

```crystal
  def initialize(secret : String = Shomen::Server.secret_from_env, verify_secret : String? = Shomen::Server.verify_secret_from_env, @https : Bool = false)
    @sessions = Shomen::SessionStore.new(secret, verify_secret)
    @production = Shomen::Server.production?
    if @production
      check_length(secret, "secret")
      check_length(verify_secret, "verify_secret") if verify_secret
    end
  end
```

`csrf_valid?` を次にする。

```crystal
  private def csrf_valid?(form : URI::Params, session : Shomen::Session) : Bool
    sent = form[CSRF_FIELD]?
    return false unless sent
    @sessions.csrf_valid?(session, sent)
  end
```

`write_response` の `Set-Cookie` の条件とコメントを次にする。

```crystal
    # Behind HTTPS the cookie goes out every time, so one issued over HTTP
    # before the switch is replaced with a Secure one. A cookie that only
    # SHOMEN_SECRET_VERIFY verified goes out again under SHOMEN_SECRET.
    if session.fresh? || session.reissue? || @https
      context.response.headers.add("Set-Cookie", @sessions.cookie(session, @https).to_set_cookie_header)
    end
```

`require "crypto/subtle"` は Server から使わなくなるので消す。

- [ ] **Step 5: spec が通るのを確かめる**

Run: `crystal spec spec/shomen/session_store_spec.cr spec/shomen/secret_rotation_spec.cr spec/shomen/production_spec.cr spec/shomen/csrf_spec.cr spec/shomen/session_spec.cr spec/shomen/form_spec.cr`
Expected: PASS（0 failures）。

- [ ] **Step 6: 全体を確かめる**

Run: `crystal tool format src spec && crystal spec && crystal build src/shomen.cr --error-trace && rm -f shomen shomen.dwarf`
Expected: 0 failures、警告なし。

---

### Task 7: 最小限の CSP

作るもの「A minimum CSP」（D6）。サーバが全応答に付け、ルートが付けた値は残す。ブラウザで、インラインのスクリプトが止まること、`shomen.js` の島、SSE、fetch が違反なしで動くことを確かめる。

**Files:**
- Modify: `src/shomen/server.cr`
- Create: `spec/support/csp_routes.cr`
- Modify: `spec/spec_helper.cr`
- Modify: `spec/shomen/server_spec.cr`
- Create: `spec/shomen/csp_browser_spec.cr`

**Interfaces:**
- Consumes: 既存の `with_live_server`、`with_browser`、`Browser#before_load`、`Browser#visit`、`Browser#run`、`waitFor`（`Browser::WAIT_FOR`）、`with_store`、`SSERoutes.store`、`SSERoutes::TARGET`、`IslandRoutes::Page`
- Produces: `Shomen::Server::CSP`、`CSPRoutes::Inline`（`/phase6/csp/inline`）、`CSPRoutes::Own`（`/phase6/csp/own`）、`CSPRoutes::Own::POLICY`

- [ ] **Step 1: spec のルートを書く**

`spec/support/csp_routes.cr`:

```crystal
module CSPRoutes
  # A document with an inline script, which the default policy stops.
  class InlineView < Shomen::View
    def to_html : String
      html lang: "en" do
        head do
          title "Inline"
        end
        body do
          h1 "Inline"
          raw "<script>window.inlineRan = true;</script>"
        end
      end
    end
  end

  class Inline < Shomen::Route
    method GET
    path "/phase6/csp/inline"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render InlineView.new
    end
  end

  # The same document under a policy the route sets itself.
  class Own < Shomen::Route
    method GET
    path "/phase6/csp/own"

    POLICY = "script-src 'self' 'unsafe-inline'"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      headers = HTTP::Headers{"Content-Security-Policy" => POLICY}
      Shomen::Response.new(200, "text/html; charset=utf-8", InlineView.new.to_html, headers)
    end
  end
end
```

`spec/spec_helper.cr` の `require "./support/page_spy"` の次に足す。

```crystal
require "./support/csp_routes"
```

- [ ] **Step 2: 失敗する spec を書く**

`spec/shomen/server_spec.cr` の `assert_security_headers` に 1 行足す。これで既存の 200、404、400、500、303、HEAD の例がすべて CSP を確かめる。

```crystal
def assert_security_headers(response)
  response.headers["X-Content-Type-Options"].should eq("nosniff")
  response.headers["Referrer-Policy"].should eq("no-referrer")
  response.headers["X-Frame-Options"].should eq("DENY")
  response.headers["Content-Security-Policy"].should eq(
    "default-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'"
  )
end
```

同じファイルの `describe` の最後に足す。

```crystal
  it "keeps a Content-Security-Policy the route set" do
    response = call_server("GET", "/phase6/csp/own")
    response.headers.get("Content-Security-Policy").should eq([CSPRoutes::Own::POLICY])
    response.headers["X-Frame-Options"].should eq("DENY")
  end
```

`spec/shomen/csp_browser_spec.cr`:

```crystal
require "../spec_helper"

# Records each policy violation the page reports, before any page script
# runs. The attribute lets waitFor see a new one.
CSP_SPY = <<-JS
  window.cspViolations = [];
  document.addEventListener("securitypolicyviolation", (event) => {
    window.cspViolations.push(event.effectiveDirective);
    document.documentElement.setAttribute("data-csp-violations", String(window.cspViolations.length));
  });
  JS

describe "Content-Security-Policy in a browser" do
  if Browser.executable
    it "stops an inline script" do
      with_live_server do |origin|
        with_browser do |browser|
          browser.before_load(CSP_SPY)
          browser.visit("#{origin}#{CSPRoutes::Inline.path}")
          result = browser.run(<<-JS)
            const violations = await waitFor(() => window.cspViolations.length > 0 ? window.cspViolations : undefined);
            return { ran: window.inlineRan === true, violations };
            JS
          result["ran"].as_bool.should be_false
          result["violations"].as_a.map(&.as_s).should contain("script-src-elem")
        end
      end
    end

    it "runs an inline script under a policy the route set" do
      with_live_server do |origin|
        with_browser do |browser|
          browser.before_load(CSP_SPY)
          browser.visit("#{origin}#{CSPRoutes::Own.path}")
          result = browser.run("return { ran: window.inlineRan === true, violations: window.cspViolations };")
          result["ran"].as_bool.should be_true
          result["violations"].as_a.should be_empty
        end
      end
    end

    it "lets shomen.js run islands, a stream, and a fetch with no violation" do
      with_store do |store|
        SSERoutes.store = store
        SSERoutes::TARGET[0] = "count"
        begin
          with_live_server do |origin|
            with_browser do |browser|
              browser.before_load(CSP_SPY)
              browser.visit("#{origin}#{IslandRoutes::Page.path}")
              result = browser.run(<<-JS)
                await waitFor(() => document.getElementById("first-add")?.hidden === false ? true : undefined);
                document.getElementById("more-link").click();
                await waitFor(() => document.getElementById("second-add")?.hidden === false ? true : undefined);
                return window.cspViolations;
                JS
              result.as_a.should be_empty
            end
          end
        ensure
          SSERoutes.store = nil
        end
      end
    end
  end
end
```

- [ ] **Step 3: spec が落ちるのを確かめる**

Run: `crystal spec spec/shomen/server_spec.cr spec/shomen/csp_browser_spec.cr`
Expected: FAIL。`assert_security_headers` を使う例が `Missing hash key: "Content-Security-Policy"` で落ちる。ブラウザがあれば "stops an inline script" が `ran` 真で落ちる。

- [ ] **Step 4: Server に CSP を足す**

`src/shomen/server.cr` の定数の並びに足す。

```crystal
  # docs/decisions/20260929-phase6-csp.md
  CSP = "default-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'"
```

`write_response` の `X-Frame-Options` の行の次に足す。

```crystal
    # A route that needs more, such as images from another origin, sends its own.
    context.response.headers["Content-Security-Policy"] = CSP unless response.headers.has_key?("Content-Security-Policy")
```

- [ ] **Step 5: spec が通るのを確かめる**

Run: `crystal spec spec/shomen/server_spec.cr spec/shomen/csp_browser_spec.cr spec/shomen/script_spec.cr spec/shomen/sse_script_spec.cr spec/shomen/island_script_spec.cr`
Expected: PASS（0 failures）。Chrome があれば、既存の `shomen.js` のブラウザ spec も CSP の下で通る。

- [ ] **Step 6: 全体を確かめる**

Run: `crystal tool format src spec && crystal spec && crystal build src/shomen.cr --error-trace && rm -f shomen shomen.dwarf && (cd examples/hello && crystal spec)`
Expected: 0 failures、警告なし。`examples/hello` のカウンターのブラウザ spec も通る。

---

### Task 8: 接続の状態（`Shomen::Connections`）

シャットダウンのための部品（D7）。接続をファイバーごとに覚え、要求の間を busy、SSE を streaming にする。drain で idle と streaming を閉じ、以後の応答に `Connection: close` を付ける。シグナルとプロセスの受入は Task 9 で確かめる。

**Files:**
- Create: `src/shomen/connections.cr`
- Modify: `src/shomen.cr`
- Modify: `src/shomen/server.cr`
- Create: `spec/shomen/connections_spec.cr`
- Modify: `spec/shomen/server_spec.cr`（例を 1 つ足す）

**Interfaces:**
- Consumes: 既存の `Shomen::Server#call`、`write_response`、`Shomen::SSE`
- Produces:
  - `class Shomen::Connections` — `open(io : IO) : Nil`、`leave : Nil`、`request(& : ->) : Nil`、`stream : Nil`、`draining? : Bool`、`busy : Int32`、`drain : Nil`、`wait(within : Time::Span) : Bool`。どれも `Fiber.current` の接続に働く
  - `Shomen::Server#connections : Shomen::Connections`

- [ ] **Step 1: 失敗する spec を書く**

`spec/shomen/connections_spec.cr`:

```crystal
require "../spec_helper"

# Serves a fake connection on its own fiber, as Listener does, and runs
# body there. The returned channel receives once the fiber ends.
private def serve(connections : Shomen::Connections, io : IO, &body : ->) : Channel(Nil)
  ended = Channel(Nil).new(1)
  opened = Channel(Nil).new(1)
  spawn do
    connections.open(io)
    opened.send(nil)
    body.call
  ensure
    connections.leave
    ended.send(nil)
  end
  opened.receive
  ended
end

private def receive_within(channel : Channel(T), limit : Time::Span = 5.seconds) : T forall T
  select
  when value = channel.receive
    value
  when timeout(limit)
    raise "nothing arrived within #{limit}"
  end
end

describe Shomen::Connections do
  it "closes an idle connection when it drains" do
    connections = Shomen::Connections.new
    reader, writer = IO.pipe
    ended = serve(connections, reader) { reader.gets rescue nil }
    connections.drain
    receive_within(ended)
    reader.closed?.should be_true
    writer.close
  end

  it "leaves a request in progress open and waits until it ends" do
    connections = Shomen::Connections.new
    reader, writer = IO.pipe
    started = Channel(Nil).new(1)
    release = Channel(Nil).new
    ended = serve(connections, reader) do
      connections.request do
        started.send(nil)
        release.receive
      end
    end
    receive_within(started)
    connections.busy.should eq(1)
    connections.drain
    reader.closed?.should be_false
    waited = Channel(Bool).new(1)
    spawn { waited.send(connections.wait(5.seconds)) }
    Fiber.yield
    select
    when waited.receive
      fail "wait returned while a request was in progress"
    else
    end
    release.send(nil)
    receive_within(waited).should be_true
    receive_within(ended)
    connections.busy.should eq(0)
    reader.close
    writer.close
  end

  it "returns false when the limit passes first" do
    connections = Shomen::Connections.new
    reader, writer = IO.pipe
    started = Channel(Nil).new(1)
    release = Channel(Nil).new
    ended = serve(connections, reader) do
      connections.request do
        started.send(nil)
        release.receive
      end
    end
    receive_within(started)
    connections.drain
    connections.wait(10.milliseconds).should be_false
    release.send(nil)
    receive_within(ended)
    reader.close
    writer.close
  end

  it "does not wait for a stream and closes it" do
    connections = Shomen::Connections.new
    reader, writer = IO.pipe
    streaming = Channel(Nil).new(1)
    ended = serve(connections, reader) do
      connections.request do
        connections.stream
        streaming.send(nil)
        reader.gets rescue nil
      end
    end
    receive_within(streaming)
    connections.busy.should eq(0)
    connections.drain
    receive_within(ended)
    reader.closed?.should be_true
    connections.wait(5.seconds).should be_true
    writer.close
  end

  it "closes a stream that begins after it drains" do
    connections = Shomen::Connections.new
    reader, writer = IO.pipe
    started = Channel(Nil).new(1)
    go = Channel(Nil).new
    ended = serve(connections, reader) do
      connections.request do
        started.send(nil)
        go.receive
        connections.stream
        reader.gets rescue nil
      end
    end
    receive_within(started)
    connections.drain
    reader.closed?.should be_false
    go.send(nil)
    receive_within(ended)
    reader.closed?.should be_true
    writer.close
  end

  it "says when it drains and returns at once with nothing in progress" do
    connections = Shomen::Connections.new
    connections.draining?.should be_false
    connections.drain
    connections.draining?.should be_true
    connections.wait(5.seconds).should be_true
  end

  it "runs a request on a fiber that serves no connection" do
    connections = Shomen::Connections.new
    ran = false
    connections.request { ran = true }
    connections.stream
    ran.should be_true
    connections.busy.should eq(0)
  end
end
```

`spec/shomen/server_spec.cr` の `describe` の最後に足す。

```crystal
  it "answers with Connection: close once it drains" do
    server = Shomen::Server.new
    call_with(server, "GET", "/phase1/home").headers["Connection"]?.should be_nil
    server.connections.drain
    call_with(server, "GET", "/phase1/home").headers["Connection"].should eq("close")
  end
```

- [ ] **Step 2: spec が落ちるのを確かめる**

Run: `crystal spec spec/shomen/connections_spec.cr spec/shomen/server_spec.cr`
Expected: コンパイルエラー `undefined constant Shomen::Connections`。

- [ ] **Step 3: Connections を書く**

`src/shomen/connections.cr`:

```crystal
# The connections of one server, each known by the fiber that serves it,
# so a shutdown can close the idle ones and the streams, and wait for the
# requests in progress (docs/decisions/20260929-phase6-shutdown.md).
class Shomen::Connections
  enum State
    Idle
    Busy
    Streaming
  end

  private class Entry
    getter io : IO
    property state = State::Idle

    def initialize(@io : IO)
    end
  end

  @entries = {} of Fiber => Entry
  @lock = Mutex.new
  @draining = false
  @done = Channel(Nil).new(1)

  def open(io : IO) : Nil
    @lock.synchronize { @entries[Fiber.current] = Entry.new(io) }
  end

  def leave : Nil
    @lock.synchronize do
      @entries.delete(Fiber.current)
      announce_if_done
    end
  end

  # Marks the current connection busy while the block runs. A fiber that
  # serves no known connection, such as a spec that calls the handler,
  # just runs it.
  def request(& : ->) : Nil
    change(State::Busy)
    begin
      yield
    ensure
      change(State::Idle)
    end
  end

  # The request on the current connection became an SSE stream. A shutdown
  # does not wait for it and closes it, at once when one already began.
  def stream : Nil
    io = @lock.synchronize do
      entry = @entries[Fiber.current]?
      next nil unless entry
      entry.state = State::Streaming
      announce_if_done
      entry.io if @draining
    end
    close(io) if io
  end

  def draining? : Bool
    @lock.synchronize { @draining }
  end

  # The number of requests in progress.
  def busy : Int32
    @lock.synchronize { @entries.count { |_, entry| entry.state.busy? } }
  end

  # Closes every connection that is idle or streaming. From now on each
  # response says Connection: close.
  def drain : Nil
    ios = @lock.synchronize do
      @draining = true
      announce_if_done
      @entries.values.reject(&.state.busy?).map(&.io)
    end
    ios.each { |io| close(io) }
  end

  # True as soon as no request is in progress after drain, false when
  # within passes first.
  def wait(within : Time::Span) : Bool
    select
    when @done.receive
      true
    when timeout(within)
      false
    end
  end

  private def change(state : State) : Nil
    @lock.synchronize do
      if entry = @entries[Fiber.current]?
        entry.state = state
        announce_if_done
      end
    end
  end

  # Called with the lock held.
  private def announce_if_done : Nil
    return unless @draining
    return if @entries.any? { |_, entry| entry.state.busy? }
    select
    when @done.send(nil)
    else
    end
  end

  # The client may have closed its side already.
  private def close(io : IO) : Nil
    io.close
  rescue IO::Error
  end
end
```

`src/shomen.cr` の `require "./shomen/island"` の次に足す。

```crystal
require "./shomen/connections"
```

- [ ] **Step 4: Server に接続の状態をつなぐ**

`src/shomen/server.cr` の `@@generated_secret : String?` の次に足す。

```crystal
  getter connections = Shomen::Connections.new
```

`call` を次にする。

```crystal
  def call(context : HTTP::Server::Context) : Nil
    @connections.request do
      session = @sessions.load(context.request.cookies[Shomen::Session::COOKIE]?.try(&.value))
      write_response(context, respond(context.request, session), session)
    end
  end
```

`write_response` の `Content-Security-Policy` の行の次に足す。

```crystal
    # While the server shuts down, no connection is kept for another request.
    context.response.headers["Connection"] = "close" if @connections.draining?
```

`write_response` の SSE の分岐を次にする。

```crystal
    elsif response.is_a?(Shomen::SSE)
      @connections.stream
      stream(context.response, response)
```

- [ ] **Step 5: spec が通るのを確かめる**

Run: `crystal spec spec/shomen/connections_spec.cr spec/shomen/server_spec.cr spec/shomen/sse_spec.cr`
Expected: PASS（0 failures）。

- [ ] **Step 6: 全体を確かめる**

Run: `crystal tool format src spec && crystal spec && crystal build src/shomen.cr --error-trace && rm -f shomen shomen.dwarf`
Expected: 0 failures、警告なし。

---

### Task 9: `start` の `reuse_port`、シグナル、プロセスでの受入

作るもの「`reuse_port` on `Shomen::Server.start`」「Graceful shutdown on SIGTERM and SIGINT」と、受入「After SIGTERM, a request in progress (other than an SSE stream) completes with its normal response and `Connection: close`, an idle keep-alive connection is closed, a new connection is refused, and the process exits within the limit」、「With `SHOMEN_ENV=production` and no `SHOMEN_SECRET`, startup fails with a message that names the variable」をプロセスで確かめる（D7、D8）。

**Files:**
- Create: `src/shomen/listener.cr`
- Modify: `src/shomen.cr`
- Modify: `src/shomen/server.cr`（`start`）
- Create: `spec/support/server_worker.cr`
- Create: `spec/support/server_process.cr`
- Modify: `spec/spec_helper.cr`
- Create: `spec/shomen/shutdown_spec.cr`
- Create: `spec/shomen/start_spec.cr`

**Interfaces:**
- Consumes: Task 8 の `Shomen::Connections`、`Shomen::Server#connections`。Task 5 の `LONG_SECRET`。Task 3 の `Workers.binary`、`remove_database`
- Produces:
  - `class Shomen::Listener < HTTP::Server` — `initialize(connections : Shomen::Connections, handler : HTTP::Handler)`
  - `Shomen::Server::SHUTDOWN_TIMEOUT = 25.seconds`、`Shomen::Server.start(host = "127.0.0.1", port = 3000, https = false, reuse_port = false, shutdown_timeout = SHUTDOWN_TIMEOUT) : Nil`。STDERR に `shomen: listening on http://<host>:<port>` と `shomen: shutting down`
  - `spec/support/server_worker.cr` — `Worker::STORE`、`Worker::NOTES`、`/worker/ping`、`/worker/slow`、`/worker/stream`。引数 `<port> <reuse|single> <shutdown秒>`、環境変数 `WORKER_DATABASE_URL`
  - `ServerProcess` — `new(port = 0, mode = "single", timeout = 25.0, env = {} of String => String?)`、`port`、`expect_output(pattern)`、`expect_error(pattern)`、`signal(signal = Signal::TERM)`、`release`、`wait(within = 10.seconds) : Process::Status`、`stop`、`ServerProcess.run(arguments, env) : {Process::Status, String}`
  - `with_server_process(port = 0, mode = "single", timeout = 25.0, env = {} of String => String?, & : ServerProcess ->)`、`send_get(socket : IO, path : String)`、`read_until(io : IO, line : String)`

- [ ] **Step 1: spec のワーカーと道具を書く**

`spec/support/server_worker.cr`:

```crystal
# The server the process specs start
# (docs/decisions/20260929-phase6-process-spec.md). Arguments: the port (0
# for an ephemeral one), "reuse" or "single", and the shutdown limit in
# seconds. WORKER_DATABASE_URL names the store.
require "../../src/shomen"
require "./events"
require "./projections"

module Worker
  STORE = Shomen::Store.new(ENV["WORKER_DATABASE_URL"])
  NOTES = SpecEvents::Log.new(STORE)

  class Ping < Shomen::Route
    method GET
    path "/worker/ping"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html("pong")
    end
  end

  # Writes "slow" and answers once the spec writes a line to standard input.
  class Slow < Shomen::Route
    method GET
    path "/worker/slow"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      STDOUT.puts "slow"
      STDOUT.flush
      STDIN.gets
      Shomen::Response.html("slow done")
    end
  end

  class CountFragment < Shomen::Fragment
    def initialize(@count : Int32)
    end

    def content : Nil
      count = @count
      p count.to_s, id: "count"
    end
  end

  class Stream < Shomen::Route
    method GET
    path "/worker/stream"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      sse(STORE) { CountFragment.new(NOTES.catch_up.lines.size) }
    end
  end
end

port, mode, limit = ARGV
Shomen::Server.start(port: port.to_i, reuse_port: mode == "reuse", shutdown_timeout: limit.to_f.seconds)
Worker::STORE.close
```

`spec/support/server_process.cr`:

```crystal
require "socket"
require "http/client"

# A spec/support/server_worker.cr process on a port of its own. Its
# standard output and error go to channels line by line, so a spec waits
# for a line instead of sleeping
# (docs/decisions/20260929-phase6-process-spec.md).
class ServerProcess
  SOURCE = "spec/support/server_worker.cr"

  getter port : Int32 = 0
  @exited : Channel(Process::Status)? = nil
  @status : Process::Status? = nil

  # Runs a worker to its end and returns its status and standard error.
  def self.run(arguments : Array(String), env = {} of String => String?) : {Process::Status, String}
    database = File.tempname("shomen-worker", ".sqlite3")
    errors = IO::Memory.new
    process = Process.new(Workers.binary(SOURCE), arguments, env: worker_env(database, env), error: errors)
    done = Channel(Process::Status).new(1)
    spawn { done.send(process.wait) }
    select
    when status = done.receive
      {status, errors.to_s}
    when timeout(20.seconds)
      process.signal(Signal::KILL)
      raise "server_worker did not exit: #{errors}"
    end
  ensure
    remove_database(database) if database
  end

  # The worker's store is a new SQLite file unless env names another.
  def self.worker_env(database : String, env) : Hash(String, String?)
    result = {"WORKER_DATABASE_URL" => "sqlite3://#{database}"} of String => String?
    env.each { |name, value| result[name] = value }
    result
  end

  def initialize(port : Int32 = 0, mode : String = "single", timeout : Float64 = 25.0, env = {} of String => String?)
    @database = File.tempname("shomen-worker", ".sqlite3")
    @output = Channel(String?).new(64)
    @errors = Channel(String?).new(64)
    @process = Process.new(
      Workers.binary(SOURCE), [port.to_s, mode, timeout.to_s],
      env: ServerProcess.worker_env(@database, env), input: :pipe, output: :pipe, error: :pipe,
    )
    forward(@process.output, @output)
    forward(@process.error, @errors)
    @port = expect_error(/\Ashomen: listening on http:\/\/127\.0\.0\.1:(\d+)\z/)[1].to_i
  end

  def expect_output(pattern : Regex, within : Time::Span = 20.seconds) : Regex::MatchData
    expect(@output, pattern, within)
  end

  def expect_error(pattern : Regex, within : Time::Span = 20.seconds) : Regex::MatchData
    expect(@errors, pattern, within)
  end

  def signal(signal : Signal = Signal::TERM) : Nil
    @process.signal(signal)
  end

  # Writes the line /worker/slow waits for.
  def release : Nil
    @process.input.puts("go")
    @process.input.flush
  end

  # Waits for the worker to exit; fails after within.
  def wait(within : Time::Span = 10.seconds) : Process::Status
    if status = @status
      return status
    end
    exited = @exited ||= begin
      channel = Channel(Process::Status).new(1)
      process = @process
      spawn { channel.send(process.wait) }
      channel
    end
    select
    when status = exited.receive
      @status = status
      status
    when timeout(within)
      raise "server_worker did not exit within #{within}"
    end
  end

  # Kills the worker if it still runs and removes its database.
  def stop : Nil
    @process.signal(Signal::KILL) unless @process.terminated?
    wait
  rescue
  ensure
    remove_database(@database)
  end

  private def forward(io : IO, lines : Channel(String?)) : Nil
    spawn do
      while line = io.gets
        lines.send(line)
      end
    rescue IO::Error
    ensure
      lines.send(nil)
    end
  end

  private def expect(lines : Channel(String?), pattern : Regex, within : Time::Span) : Regex::MatchData
    deadline = Time.instant + within
    loop do
      select
      when line = lines.receive
        raise "server_worker ended before a line matched #{pattern.source}" unless line
        if match = pattern.match(line)
          return match
        end
      when timeout(deadline - Time.instant)
        raise "no line matched #{pattern.source} within #{within}"
      end
    end
  end
end

def with_server_process(port : Int32 = 0, mode : String = "single", timeout : Float64 = 25.0, env = {} of String => String?, & : ServerProcess ->) : Nil
  server = ServerProcess.new(port, mode, timeout, env)
  begin
    yield server
  ensure
    server.stop
  end
end

# Sends a GET on socket and leaves the connection open.
def send_get(socket : IO, path : String) : Nil
  socket << "GET " << path << " HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
  socket.flush
end

# Reads lines from io until one equals line; fails when io ends first.
def read_until(io : IO, line : String) : Nil
  while current = io.gets
    return if current == line
  end
  raise "the stream ended before #{line.inspect}"
end
```

`spec/spec_helper.cr` の `require "./support/csp_routes"` の次に足す。

```crystal
require "./support/server_process"
```

- [ ] **Step 2: 失敗する spec を書く**

`spec/shomen/shutdown_spec.cr`:

```crystal
require "../spec_helper"

private def connect(port : Int32) : TCPSocket
  socket = TCPSocket.new("127.0.0.1", port)
  socket.read_timeout = 20.seconds
  socket
end

describe "Shomen::Server.start on SIGTERM" do
  it "finishes a request in progress with Connection: close, closes an idle connection, refuses a new one, and exits 0" do
    with_server_process do |server|
      idle = connect(server.port)
      send_get(idle, "/worker/ping")
      first = HTTP::Client::Response.from_io(idle)
      first.body.should eq("pong")
      first.headers["Connection"].should eq("keep-alive")

      busy = connect(server.port)
      send_get(busy, "/worker/slow")
      server.expect_output(/\Aslow\z/)

      server.signal
      server.expect_error(/\Ashomen: shutting down\z/)
      idle.gets.should be_nil
      expect_raises(Socket::ConnectError) { TCPSocket.new("127.0.0.1", server.port) }

      server.release
      response = HTTP::Client::Response.from_io(busy)
      response.status_code.should eq(200)
      response.body.should eq("slow done")
      response.headers["Connection"].should eq("close")
      server.wait.exit_code.should eq(0)
    end
  end

  it "exits when the limit passes with a request still in progress" do
    with_server_process(timeout: 0.2) do |server|
      busy = connect(server.port)
      send_get(busy, "/worker/slow")
      server.expect_output(/\Aslow\z/)
      server.signal
      server.wait.exit_code.should eq(0)
    end
  end

  it "closes an SSE stream and does not wait for it" do
    with_server_process(timeout: 60.0) do |server|
      stream = connect(server.port)
      send_get(stream, "/worker/stream")
      read_until(stream, %(data: <p id="count">0</p>))
      server.signal
      server.wait.exit_code.should eq(0)
      while stream.gets
      end
    end
  end

  it "stops at once on a second signal" do
    with_server_process do |server|
      busy = connect(server.port)
      send_get(busy, "/worker/slow")
      server.expect_output(/\Aslow\z/)
      server.signal
      server.expect_error(/\Ashomen: shutting down\z/)
      server.signal
      status = server.wait
      status.signal_exit?.should be_true
      status.exit_signal.should eq(Signal::TERM)
    end
  end
end
```

`spec/shomen/start_spec.cr`:

```crystal
require "../spec_helper"

describe "Shomen::Server.start" do
  it "shares a port between two processes with reuse_port" do
    with_server_process(mode: "reuse") do |first|
      with_server_process(port: first.port, mode: "reuse") do |second|
        second.port.should eq(first.port)
        HTTP::Client.get("http://127.0.0.1:#{first.port}/worker/ping").body.should eq("pong")
      end
    end
  end

  it "does not share a port without reuse_port" do
    with_server_process(mode: "reuse") do |first|
      status, errors = ServerProcess.run([first.port.to_s, "single", "1"])
      status.success?.should be_false
      errors.should contain("Address already in use")
    end
  end

  it "fails in production without SHOMEN_SECRET and names the variable" do
    status, errors = ServerProcess.run(["0", "single", "1"], {"SHOMEN_ENV" => "production", "SHOMEN_SECRET" => nil})
    status.success?.should be_false
    errors.should contain("SHOMEN_SECRET must be set to at least 32 bytes when SHOMEN_ENV=production")
  end

  it "starts in production with a SHOMEN_SECRET of 32 bytes" do
    with_server_process(env: {"SHOMEN_ENV" => "production", "SHOMEN_SECRET" => LONG_SECRET}) do |server|
      HTTP::Client.get("http://127.0.0.1:#{server.port}/worker/ping").body.should eq("pong")
    end
  end
end
```

- [ ] **Step 3: spec が落ちるのを確かめる**

Run: `crystal spec spec/shomen/start_spec.cr spec/shomen/shutdown_spec.cr`
Expected: FAIL。`server_worker` のビルドが `no parameter named 'reuse_port'` で失敗し、`spec/support/server_worker.cr did not build` で落ちる。

- [ ] **Step 4: Listener を書く**

`src/shomen/listener.cr`:

```crystal
require "http/server"
require "./connections"

# An HTTP::Server that tells Connections which fiber serves which
# connection, so a shutdown can close the idle ones
# (docs/decisions/20260929-phase6-shutdown.md).
class Shomen::Listener < HTTP::Server
  def initialize(@connections : Shomen::Connections, handler : HTTP::Handler)
    super(handler)
  end

  protected def dispatch(io)
    connections = @connections
    spawn do
      connections.open(io)
      handle_client(io)
    ensure
      connections.leave
    end
  end
end
```

`src/shomen.cr` の `require "./shomen/connections"` の次に足す。

```crystal
require "./shomen/listener"
```

- [ ] **Step 5: `start` を書き直す**

`src/shomen/server.cr` の定数の並びに足す。

```crystal
  # Inside the 30 seconds Kubernetes waits before SIGKILL.
  SHUTDOWN_TIMEOUT = 25.seconds
```

`self.start` を次にする。

```crystal
  # Serves until SIGTERM or SIGINT. Then it stops accepting, closes idle
  # connections and SSE streams, and returns once the requests in progress
  # finish or shutdown_timeout passes. A second signal ends the process at
  # once (docs/decisions/20260929-phase6-shutdown.md).
  def self.start(host : String = "127.0.0.1", port : Int32 = 3000, https : Bool = false, reuse_port : Bool = false, shutdown_timeout : Time::Span = SHUTDOWN_TIMEOUT) : Nil
    Shomen::Router.entries
    server = new(https: https)
    listener = Shomen::Listener.new(server.connections, server)
    address = listener.bind_tcp(host, port, reuse_port: reuse_port)
    {Signal::TERM, Signal::INT}.each do |signal|
      signal.trap do
        Signal::TERM.reset
        Signal::INT.reset
        server.connections.drain
        listener.close
        STDERR.puts "shomen: shutting down"
      end
    end
    STDERR.puts "shomen: listening on http://#{address}"
    listener.listen
    server.connections.wait(shutdown_timeout)
  end
```

- [ ] **Step 6: spec が通るのを確かめる**

Run: `crystal spec spec/shomen/start_spec.cr spec/shomen/shutdown_spec.cr`
Expected: PASS（0 failures）。"does not share a port without reuse_port" の STDERR には `Socket::BindError` の `Address already in use` が出る。

- [ ] **Step 7: 全体を確かめる**

Run: `crystal tool format src spec && SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec && crystal build src/shomen.cr --error-trace && rm -f shomen shomen.dwarf && (cd examples/hello && crystal spec)`
Expected: 0 failures、警告なし。

---

### Task 10: 1 つの Postgres の上の 2 プロセス（受入）

受入「Two processes with one secret on one Postgres database: a form rendered by one is accepted when posted to the other, and a GET to either shows the change」。2 つのワーカーを `SHOMEN_ENV=production` と同じ `SHOMEN_SECRET` で起動する。

**Files:**
- Modify: `spec/support/server_worker.cr`（メモのルートを足す）
- Create: `spec/shomen/two_processes_spec.cr`

**Interfaces:**
- Consumes: Task 9 の `with_server_process`、`ServerProcess#port`。Task 3 の `postgres_database_it`。Task 5 の `LONG_SECRET`。既存の `session_cookie`（`spec/support/client.cr`）
- Produces: `server_worker` の `GET /worker/notes`（メモの一覧、`csrf_field`、`version` の hidden、`text` の入力）と `POST /worker/notes`（`notes` に 1 件追記して 303）

- [ ] **Step 1: 失敗する spec を書く**

`spec/shomen/two_processes_spec.cr`:

```crystal
require "../spec_helper"

private def get(port : Int32, path : String, cookie : String? = nil) : HTTP::Client::Response
  headers = HTTP::Headers.new
  headers["Cookie"] = cookie if cookie
  HTTP::Client.get("http://127.0.0.1:#{port}#{path}", headers: headers)
end

private def post_form(port : Int32, path : String, cookie : String, form : Hash(String, String)) : HTTP::Client::Response
  headers = HTTP::Headers{"Cookie" => cookie, "Content-Type" => "application/x-www-form-urlencoded"}
  HTTP::Client.post("http://127.0.0.1:#{port}#{path}", headers: headers, body: URI::Params.encode(form))
end

describe "two processes with one secret on one Postgres database" do
  postgres_database_it "accept a form one rendered when it is posted to the other, and both show the change" do |url|
    env = {"SHOMEN_ENV" => "production", "SHOMEN_SECRET" => LONG_SECRET, "WORKER_DATABASE_URL" => url}
    with_server_process(env: env) do |first|
      with_server_process(env: env) do |second|
        page = get(first.port, "/worker/notes")
        page.status_code.should eq(200)
        cookie = session_cookie(page)
        token = page.body[/name="_csrf" value="([0-9a-f]+)"/, 1]
        version = page.body[/name="version" value="(\d+)"/, 1]

        posted = post_form(second.port, "/worker/notes", cookie, {"_csrf" => token, "version" => version, "text" => "sent to the other"})
        posted.status_code.should eq(303)

        [first, second].each do |server|
          get(server.port, "/worker/notes", cookie).body.should contain("<li>sent to the other</li>")
        end
      end
    end
  end
end
```

- [ ] **Step 2: spec が落ちるのを確かめる**

Run: `SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec spec/shomen/two_processes_spec.cr`
Expected: FAIL（`/worker/notes` が 404 で、`page.status_code` が 404）。

- [ ] **Step 3: ワーカーにメモのルートを足す**

`spec/support/server_worker.cr` の `module Worker` の最後（`end` の前）に足す。

```crystal
  class NotesView < Shomen::View
    def initialize(@texts : Array(String), @version : Int64, @token : String)
    end

    def to_html : String
      texts = @texts
      version = @version
      token = @token
      html lang: "en" do
        head do
          title "Notes"
        end
        body do
          main do
            ul do
              texts.each { |text| li text }
            end
            form(action: Add.path, method: "post") do
              csrf_field(token)
              input(type: "hidden", name: "version", value: version.to_s)
              label("Text", for: "text")
              input(id: "text", name: "text", type: "text")
              button "Add", type: "submit"
            end
          end
        end
      end
    end
  end

  class Notes < Shomen::Route
    method GET
    path "/worker/notes"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      lines = NOTES.catch_up.lines
      render NotesView.new(lines.map(&.text), lines.size.to_i64, csrf_token)
    end
  end

  class Add < Shomen::Route
    method POST
    path "/worker/notes"

    struct Input
      getter text : String
      getter version : Int64

      def initialize(@text : String, @version : Int64)
      end
    end

    def call(input : Input) : Shomen::Response
      STORE.append("notes", input.version, [SpecEvents::Noted.new(input.text)] of Shomen::Event)
      redirect Notes.path
    end
  end
```

- [ ] **Step 4: spec が通るのを確かめる**

Run: `SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec spec/shomen/two_processes_spec.cr spec/shomen/shutdown_spec.cr spec/shomen/start_spec.cr`
Expected: PASS（0 failures）。

Run: `env -u SHOMEN_SPEC_POSTGRES crystal spec spec/shomen/two_processes_spec.cr`
Expected: 0 failures、1 pending。

- [ ] **Step 5: 全体を確かめる**

Run: `crystal tool format src spec && SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec`
Expected: 0 failures、警告なし。

---

### Task 11: README、CONTRIBUTING、現行フェーズ、最終確認

**Files:**
- Modify: `README.md`、`README.ja.md`
- Modify: `CONTRIBUTING.md`、`CONTRIBUTING.ja.md`
- Modify: `docs/en/02-PHASES.md:5-9`、`docs/02-PHASES.md:5-9`

**Interfaces:**
- Consumes: Task 1〜10 のすべて
- Produces: なし

- [ ] **Step 1: README を直す（英語）**

`README.md` の 7 行目を次にする。

```markdown
Version 0.0.0. Phases 1 to 6 are in the tree: typed routes, a typed HTML DSL, an HTTP server, form binding, a signed session cookie, CSRF protection, commands and events, an append-only event store on SQLite or Postgres, in-memory projections, HTML fragments, the official `shomen.js`, JSON responses, SSE, islands, and what production needs (a required secret, a Content-Security-Policy, port sharing, and graceful shutdown). Phase 7 is specified and not implemented. There is no release tag yet.
```

「## Requirements」の `libsqlite3` の行の次に足し、その下の段落を次にする。

```markdown
- Postgres, only for an application that uses it, and to run the Postgres specs
```

```markdown
The framework shard depends on `sqlite3`, `pg`, and `db` from crystal-lang and will/crystal-pg. `pg` is written in Crystal and needs no C library.
```

サーバの段落（`The server listens on 127.0.0.1:3000.` で始まる行）を次にする。

```markdown
The server listens on `127.0.0.1:3000`. A match returns 200 HTML. A bad path parameter returns 400. An unknown path, or `Shomen::NotFound`, returns 404 HTML. An unhandled exception returns 500 HTML with the message escaped; with `SHOMEN_ENV=production` the message is hidden. The exception goes to `Log` under `shomen` in every environment. Every response sets `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`, and a `Content-Security-Policy` (phase 6 below).
```

見出し `## Phases 1 to 5 are what run` を `## Phases 1 to 6 are what run` にする。「Phase 5 adds these:」の箇条の次に足し、その後の `These are specified for later phases ...` の行を置き換える。

```markdown
Phase 6 adds these:

- `Shomen::Store.new("postgres://localhost/app")`: the same store on Postgres. The URL's scheme picks SQLite (`sqlite3`) or Postgres (`postgres`, `postgresql`); commands, events, and projections do not change. An append takes one advisory lock, so ids become visible in order. Without `max_pool_size` in the URL, a process keeps at most 10 connections
- `SHOMEN_ENV=production`: startup fails unless `SHOMEN_SECRET` has at least 32 bytes, and a 500 hides the exception message
- `SHOMEN_SECRET_VERIFY`: a second secret that only verifies. A cookie it verifies is sent again under `SHOMEN_SECRET`, and a form rendered under either secret still posts. Change the secret in three deploys: put the new secret in `SHOMEN_SECRET_VERIFY`; swap the two; remove `SHOMEN_SECRET_VERIFY`
- `Content-Security-Policy: default-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'` on every response. A route that sets its own `Content-Security-Policy` keeps it
- `Shomen::Server.start(reuse_port: true)`: processes on one host share a port. On Linux, set `net.ipv4.tcp_migrate_req=1` so the connections waiting on a process that stops move to the others
- On SIGTERM or SIGINT the server stops accepting, closes idle connections and SSE streams, finishes the requests in progress with `Connection: close`, and `start` returns within `shutdown_timeout` (25 seconds by default). A second signal ends the process at once
- `examples/hello` stays on SQLite. `HELLO_DATABASE_URL=postgres://localhost/hello crystal run src/hello.cr` runs it on an existing Postgres database

Phase 7 is specified and not in the code: consumers that run outside the request, notifications across processes, HTTP caching, and reads from replicas.
```

「## Development」のコードブロックの次の段落 `crystal build writes ./shomen. Do not commit that binary.` の前に足す。

```markdown
Without `SHOMEN_SPEC_POSTGRES` the Postgres specs are pending. To run them, set it to a Postgres URL whose user may create databases, such as `SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec`. Each example creates a database and drops it.
```

- [ ] **Step 2: README を直す（日本語訳）**

`README.ja.md` の 7 行目を次にする。

```markdown
バージョンは 0.0.0 です。リポジトリに入っているのはフェーズ 6 までで、型付きルート、型付き HTML、HTTP サーバ、フォームの束縛、署名付きセッション Cookie、CSRF 対策、コマンドとイベント、SQLite か Postgres の上の追記のみのイベントストア、メモリ上のプロジェクション、HTML 断片、公式の `shomen.js`、JSON 応答、SSE、島、本番に要るもの（必須の鍵、Content-Security-Policy、ポートの共有、グレースフルシャットダウン）が動きます。フェーズ 7 は仕様にあり、実装はまだありません。リリースタグもまだありません。
```

「## 必要なもの」の `libsqlite3` の行の次に足し、その下の段落を次にする。

```markdown
- Postgres（使うアプリと、Postgres の spec を走らせるときだけ）
```

```markdown
フレームワーク本体の shard は、crystal-lang の `sqlite3` と `db`、will/crystal-pg の `pg` に依存します。`pg` は Crystal で書かれていて、C のライブラリは要りません。
```

サーバの段落（`サーバの待受は` で始まる行）を次にする。

```markdown
サーバの待受は `127.0.0.1:3000` です。一致したルートは 200 の HTML、パスパラメータの変換失敗は 400、未知のパスと `Shomen::NotFound` は 404 の HTML、処理されない例外はメッセージをエスケープした 500 の HTML です。`SHOMEN_ENV=production` ではメッセージを出しません。例外は環境によらず `Log` の `shomen` に書きます。すべての応答に `X-Content-Type-Options: nosniff`、`Referrer-Policy: no-referrer`、`X-Frame-Options: DENY`、`Content-Security-Policy`（下のフェーズ 6）が付きます。
```

見出し `## いま動くのはフェーズ 1 から 5` を `## いま動くのはフェーズ 1 から 6` にする。「フェーズ 5 で足したもの:」の箇条の次に足し、その後の `Postgres と、1 つの DB の上で同じプロセスを多数動かすことは、...` の行を置き換える。

```markdown
フェーズ 6 で足したもの:

- `Shomen::Store.new("postgres://localhost/app")`: 同じストアを Postgres の上で使います。URL のスキームで SQLite（`sqlite3`）か Postgres（`postgres`、`postgresql`）を選び、コマンド、イベント、プロジェクションは変わりません。追記は 1 つのアドバイザリロックを取るので、id は順に見えます。URL に `max_pool_size` が無ければ、1 プロセスの接続は 10 本までです
- `SHOMEN_ENV=production`: `SHOMEN_SECRET` が 32 バイト以上でなければ起動に失敗し、500 では例外のメッセージを出しません
- `SHOMEN_SECRET_VERIFY`: 検証だけに使う 2 つ目の鍵です。この鍵で通った Cookie は `SHOMEN_SECRET` で出し直し、どちらの鍵で描いたフォームも送れます。鍵の入れ替えは 3 回のデプロイで行います。新しい鍵を `SHOMEN_SECRET_VERIFY` に入れる、2 つを入れ替える、`SHOMEN_SECRET_VERIFY` を消す、の順です
- すべての応答に `Content-Security-Policy: default-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'` が付きます。ルートが自分で `Content-Security-Policy` を付けた応答は、その値のままです
- `Shomen::Server.start(reuse_port: true)`: 1 ホストの複数のプロセスが 1 つのポートを共有します。Linux では `net.ipv4.tcp_migrate_req=1` を設定すると、止まるプロセスで待っている接続がほかのプロセスへ移ります
- SIGTERM か SIGINT を受けると、サーバは受け付けをやめ、アイドルの接続と SSE を閉じ、処理中の要求を `Connection: close` 付きで終えます。`start` は `shutdown_timeout`（既定 25 秒）以内に戻ります。2 回目の合図でプロセスはすぐ終わります
- `examples/hello` は SQLite のままです。`HELLO_DATABASE_URL=postgres://localhost/hello crystal run src/hello.cr` で、既存の Postgres の DB の上で動きます

フェーズ 7 は仕様にあり、コードにはありません。要求の外で動くコンシューマ、プロセスをまたぐ通知、HTTP キャッシュ、replica からの読み出しです。
```

「## 開発」のコードブロックの次の段落 `crystal build は ./shomen を書き出します。` の前に足す。

```markdown
`SHOMEN_SPEC_POSTGRES` が無いと、Postgres の spec は pending になります。走らせるときは、DB を作れるユーザーの Postgres の URL を入れます（例 `SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec`）。例ごとに DB を作り、終わったら消します。
```

- [ ] **Step 3: CONTRIBUTING を直す（英語と日本語訳）**

`CONTRIBUTING.md` の「## Code」の shard の行を次にする。

```markdown
- No new shard unless the spec names it. Phases 0–2 had none. Phase 3 added `sqlite3` and `db`. Phase 6 added `pg`.
```

「## Checks」の最後の段落の次に足す。

```markdown
The Postgres specs run only when `SHOMEN_SPEC_POSTGRES` names a Postgres URL whose user may create databases (for example `postgres://localhost/postgres`); without it they are pending. Each example creates a database named `shomen_spec_...` and drops it. The shutdown, `reuse_port`, and two-process specs build `spec/support/server_worker.cr` once, start it on an ephemeral port on 127.0.0.1, and wait for lines on its output instead of sleeping. Before calling a phase done, run `crystal spec` with `SHOMEN_SPEC_POSTGRES` set.
```

`CONTRIBUTING.ja.md` の「## コード」の shard の行を次にする。

```markdown
- 仕様が名前を挙げた shard 以外は足しません。フェーズ 0〜2 の依存はゼロで、フェーズ 3 で `sqlite3` と `db` を、フェーズ 6 で `pg` を足しました。
```

「## 確認」の最後の段落の次に足す。

```markdown
Postgres の spec は、`SHOMEN_SPEC_POSTGRES` に DB を作れるユーザーの Postgres の URL（例 `postgres://localhost/postgres`）を入れたときだけ走ります。無ければ pending です。例ごとに `shomen_spec_...` という DB を作り、終わったら消します。シャットダウン、`reuse_port`、2 プロセスの spec は、`spec/support/server_worker.cr` を 1 回ビルドして 127.0.0.1 の一時ポートで起動し、sleep ではなく出力の行を待ちます。フェーズを終える前に、`SHOMEN_SPEC_POSTGRES` を付けて `crystal spec` を走らせます。
```

- [ ] **Step 4: 現行フェーズを受入済みにする**

`docs/en/02-PHASES.md` の「## Current phase」の本文を次にする。

```markdown
## Current phase

**Phase 6 — Postgres and production hardening**

Phase 6 acceptance is met. Do not implement past this point (phase 7 and later). Wait for the next instruction.
```

`docs/02-PHASES.md` の「## 現行フェーズ」の本文を次にする。

```markdown
## 現行フェーズ

**フェーズ 6 — Postgres と本番寄せ**

フェーズ 6 の受入は満たした。ここより先（フェーズ 7 以降）を実装しない。ユーザーの次指示を待つ。
```

- [ ] **Step 5: 自動の確認をすべて走らせる**

Run:

```sh
shards install
crystal tool format --check src spec examples/hello/src examples/hello/spec
SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec
env -u SHOMEN_SPEC_POSTGRES crystal spec
crystal build src/shomen.cr --error-trace && rm -f shomen shomen.dwarf
(cd examples/hello && shards install && crystal spec)
/opt/homebrew/opt/postgresql@18/bin/psql -h localhost -d postgres -Atc "SELECT count(*) FROM pg_database WHERE datname LIKE 'shomen_spec_%'"
```

Expected: format の差分なし。1 回目の `crystal spec` は 0 failures、0 pending（Chrome がある開発機）。2 回目は 0 failures で、Postgres の例だけが pending。`crystal build` は警告なし。`examples/hello` は 0 failures。最後の問い合わせは `0`。

- [ ] **Step 6: 受入を 1 つずつ照らし合わせる**

| 受入 | 確かめる spec |
|---|---|
| SQLite and Postgres share the same Command API | `store_spec.cr`、`projection_spec.cr`、`store_concurrency_spec.cr` の `(sqlite3)` と `(postgres)` の組 |
| The example default remains SQLite | Step 7 の手動確認（`var/shomen.sqlite3` ができる） |
| With `SHOMEN_ENV=production` and no `SHOMEN_SECRET`, startup fails with a message that names the variable | `production_spec.cr` "refuses to start without SHOMEN_SECRET and names the variable"、`start_spec.cr` "fails in production without SHOMEN_SECRET and names the variable" |
| A cookie and a CSRF token signed with `SHOMEN_SECRET_VERIFY` are accepted, and the response reissues the cookie under `SHOMEN_SECRET` | `secret_rotation_spec.cr` の最初の例 |
| Two processes with one secret on one Postgres database: a form rendered by one is accepted when posted to the other, and a GET to either shows the change | `two_processes_spec.cr` |
| While one append transaction is open after its insert, an append from another process waits until the first commits | `postgres_adapter_spec.cr` "makes an append from another process wait ..." |
| Concurrent appends from two processes: a projection that follows its checkpoint receives every event once, in `id` order | `postgres_adapter_spec.cr` "gives a projection that follows its checkpoint ..." |
| After SIGTERM, a request in progress (other than an SSE stream) completes with its normal response and `Connection: close`, an idle keep-alive connection is closed, a new connection is refused, and the process exits within the limit | `shutdown_spec.cr` の 4 例 |

作るもののうち、`hides the exception body` は `production_spec.cr`、`A minimum CSP` は `server_spec.cr` と `csp_browser_spec.cr`、`reuse_port` は `start_spec.cr` が確かめる。

- [ ] **Step 7: 例を手で動かす**

SQLite（既定）:

```sh
cd examples/hello
rm -rf var
crystal build src/hello.cr -o "$TMPDIR/shomen-hello"
"$TMPDIR/shomen-hello" 2> "$TMPDIR/shomen-hello.log" &
HELLO=$!
curl -si http://127.0.0.1:3000/ | grep -E "^HTTP|^Content-Security-Policy|<h1>"
ls var/shomen.sqlite3
kill -TERM $HELLO; wait $HELLO; echo "exit $?"
cat "$TMPDIR/shomen-hello.log"
cd ../..
```

Expected: `HTTP/1.1 200 OK`、`Content-Security-Policy: default-src 'self'; ...`、`<h1>Hello</h1>`。`var/shomen.sqlite3` がある。`exit 0`。ログに `shomen: listening on http://127.0.0.1:3000` と `shomen: shutting down`。

Postgres:

```sh
/opt/homebrew/opt/postgresql@18/bin/psql -h localhost -d postgres -c "CREATE DATABASE shomen_hello_check"
cd examples/hello
HELLO_DATABASE_URL=postgres://localhost/shomen_hello_check "$TMPDIR/shomen-hello" 2> "$TMPDIR/shomen-hello.log" &
HELLO=$!
curl -s http://127.0.0.1:3000/users/1/edit | grep -o 'name="_csrf" value="[0-9a-f]*"'
kill -TERM $HELLO; wait $HELLO; echo "exit $?"
cd ../..
/opt/homebrew/opt/postgresql@18/bin/psql -h localhost -d shomen_hello_check -Atc "SELECT count(*) FROM events"
/opt/homebrew/opt/postgresql@18/bin/psql -h localhost -d postgres -c "DROP DATABASE shomen_hello_check"
rm -f "$TMPDIR/shomen-hello" "$TMPDIR/shomen-hello.dwarf" "$TMPDIR/shomen-hello.log"
```

Expected: `_csrf` の値が出る。`exit 0`。`events` 表がある（件数は `0`）。

- [ ] **Step 8: 後始末を確かめる**

Run: `git status --short`
Expected: ルートに `shomen`、`shomen.dwarf`、`lib/` の変更が出ない（`lib/` は無視されている）。`examples/hello/var/` はルートの `.gitignore` の `var/` で無視されている。変更は File Map のファイルだけ。

作業報告は短くする: 変えたファイル、走らせたコマンド、フェーズ 6 の受入を満たしたか、残っていること（無ければ無い）。commit はユーザーの指示を待つ。
