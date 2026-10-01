# Phase 7c Read-Your-Writes and Replicas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** フェーズ 7 の 4 本のサブ計画の 3 本目。セッションが最後に追記した `id` を署名付きクッキーで覚え、Postgres の replica から読み、同じセッションの後の要求が追記より古い状態を見せないようにする。受入「With a replica that lags, a POST, its redirect, and the following GET in one session show the appended change」と、「When a projection kept in tables does not reach the needed `id` within the limit, the response is 503, not an older state. After the session forgets that `id`, the same page returns 200」の後半を満たす。

**Architecture:** `Store#append` が最後の `id` を返し、ルートが `remember` で覚えさせ、`handle` が応答の `remember` に移し、サーバがクッキー `shomen_append` を書く。次の要求でサーバがクッキーを検証し、`Route#must_see` に入れる。ルートは `must_see` を `Projection#catch_up` と `Consumer#read` に渡す。replica は `Store.new(url, replica:)` で渡し、読み取り専用の `PostgresAdapter` になる。`catch_up` と `Consumer#read` は replica を上限まで待ち、primary に切り替える（D1〜D3）。

**Tech Stack:** Crystal `>= 1.20.0`（開発機は 1.21.1）、標準ライブラリだけ。shard は増やさない（`db` 0.14.0、`sqlite3` 0.23.0、`pg` 0.30.0）。開発機の Postgres は Homebrew の 18。

**Spec:** `docs/en/00-INSTRUCTION.md` の 6（セッション）と 10（スケールアウト）、`docs/en/02-PHASES.md` のフェーズ 7。既存の決定 `20260929-scale-read-your-writes.md`、`20260929-phase3-store-api.md`、`20261001-phase7-consumer-read.md`。この計画の Task 1 で足す決定:

- `docs/decisions/20261001-phase7-remember-append.md`（D1）
- `docs/decisions/20261001-phase7-replica.md`（D2）
- `docs/decisions/20261001-phase7-replica-spec.md`（D3）

## Global Constraints

- shard を足さない。DB 以外のサービスを使わない
- `ETag` と断片キャッシュを作らない（7d）。汎用のセッション map を作らない
- 既存の公開 API の引数は変えない。足すのは既定値つきの引数だけ。`Store#append` の戻り値は `Nil` から `Int64` に変わる
- モジュール境界: Store はセッションも HTML も知らない。Server は Store も Consumer も知らない。Projection と Consumer は SQLite も Postgres も名指ししない
- `examples/hello` のコードは変えない（SQLite のアプリはそのまま動く）
- テストは固定ポートを bind しない。sleep で同期しない
- ユーザーが指示するまで commit しない

## Review Focus

- 別のセッションの `shomen_append` を写しても通らない。期限を過ぎた値、署名の合わない値、形の壊れた値は 0 になる（Task 2）
- `remember` を呼ばない要求はクッキーを書かない。例外で終わった要求も書かない（Task 3）
- replica を持つ Store は replica の DB に表を作らない（Task 4）
- `catch_up` は待つ間ロックを持たない。覚えた `id` を持たない要求は replica から 1 回読むだけで返る（Task 5）
- 表のプロジェクションで、replica も primary も届かないときは 503（Task 5）
- SSE は起きた追記の `id` を `must_see` にしてから描き直す（Task 3）

## File Map

| ファイル | 役割 | Task |
|---|---|---|
| `docs/en/00-INSTRUCTION.md`、`docs/00-INSTRUCTION.md` | 仕様 6 と 10 | 1 |
| `docs/decisions/20261001-phase7-*.md` | D1〜D3 | 1 |
| `src/shomen/session.cr`、`src/shomen/session_store.cr` | `remembered`、`shomen_append` | 2 |
| `src/shomen/response.cr`、`src/shomen/route.cr`、`src/shomen/router.cr`、`src/shomen/server.cr`、`src/shomen/sse.cr` | `remember`、`must_see`、クッキー、SSE | 3 |
| `src/shomen/store.cr`、`src/shomen/postgres_adapter.cr` | `append` の `id`、replica | 4 |
| `src/shomen/projection.cr`、`src/shomen/consumer.cr` | replica を待つ | 5 |
| `spec/support/server_worker.cr`、`spec/support/postgres.cr`、`spec/support/consumer_routes.cr` | 受入の支え | 3, 6 |
| `spec/shomen/*_spec.cr` | 各 Task の spec | 2〜6 |
| `README.md`、`README.ja.md` | ここまで足したもの | 7 |

---

### Task 1: 仕様と決定ファイル

- [x] D1〜D3 を書く
- [x] 仕様 6 に `shomen_append`、仕様 10 に `replica:` と `catch_up(must_see)` を足す（英語と日本語訳）
- [x] 骨子の 7c の行にこの計画のファイル名を入れる

### Task 2: セッションが覚える `id`

**Files:** `src/shomen/session.cr`、`src/shomen/session_store.cr`、`spec/shomen/session_store_spec.cr`

- [x] spec を先に書く: 覚えた `id` を読む / 期限を過ぎたら 0 / 別のセッションなら 0 / 署名が合わない・形が壊れていたら 0 / `SHOMEN_SECRET_VERIFY` で検証できる / クッキーの属性（Path=/、HttpOnly、SameSite=Lax、Max-Age=60、HTTPS で Secure）
- [x] `Shomen::Session::APPEND_COOKIE = "shomen_append"`、`REMEMBER = 60.seconds`、`Session#remembered : Int64`
- [x] `SessionStore#load(cookie_value, append_value = nil, now = Time.utc)`、`SessionStore#append_cookie(session, id, secure, now = Time.utc) : HTTP::Cookie`
- [x] `crystal spec spec/shomen/session_store_spec.cr` が緑

### Task 3: ルート、応答、サーバ、SSE

**Files:** `src/shomen/response.cr`、`src/shomen/route.cr`、`src/shomen/router.cr`、`src/shomen/server.cr`、`src/shomen/sse.cr`、`spec/support/routes.cr`、`spec/shomen/remember_spec.cr`（新規）、`spec/shomen/router_spec.cr`、`spec/shomen/sse_spec.cr`

- [x] spec を先に書く: `remember` した POST は `shomen_append` を返す / しない要求は返さない / 例外で終わった要求は返さない / 次の GET の `must_see` が覚えた `id` / 期限切れのクッキーなら 0 / `remember` は `must_see` を上げ、小さい `id` では下げない / SSE は起きた追記の `id` を `must_see` にする
- [x] `Response#remember : Int64`（property、既定 0）
- [x] `Route#must_see`（property）、`Route#remember(id)`、`Route#remembered?`。`handle(request, form, csrf_token, must_see = 0)` が設定し、応答に移す
- [x] `Router` の handler に `Int64` を足す。`Server#dispatch(request, form, csrf_token, must_see = 0)`
- [x] `Server` がクッキーを読み、`remember > 0` の応答にクッキーを書く
- [x] `SSE.new(store, fragment : Int64 -> Fragment, heartbeat)`。`Route#sse` が `must_see` を上げる proc で包む
- [x] 関係する spec が緑

### Task 4: `append` の `id` と replica の Store

**Files:** `src/shomen/store.cr`、`src/shomen/postgres_adapter.cr`、`spec/support/postgres.cr`、`spec/shomen/store_spec.cr`、`spec/shomen/replica_spec.cr`（新規）

- [x] spec を先に書く: `append` が最後の `id` を返す、空なら 0 / SQLite の primary や Postgres でない replica は `ArgumentError` / replica の DB に表を作らない / `read`、`checkpoint`、`using_connection` の `replica: true` は replica を、replica が無ければ primary を読む / `close` が replica も閉じる
- [x] `PostgresAdapter.new(uri, replica: true)` は表を作らない
- [x] `Store.new(url, poll_interval, replica)`、`replica?`、`replica:` 引数
- [x] `PostgresSpec.copy(from, to, table)`
- [x] `PG=` 付きで関係する spec が緑

### Task 5: プロジェクションとコンシューマが replica を待つ

**Files:** `src/shomen/projection.cr`、`src/shomen/consumer.cr`、`spec/shomen/replica_spec.cr`

- [x] spec を先に書く（Postgres）: `catch_up` は replica から読む / `catch_up(id)` は replica が届けば primary を読まない / 届かなければ `within` の後 primary から追いつく / `Consumer#read(0)` は replica で読む / replica が届けば replica、届かず primary が届けば primary、どちらも届かなければ `Shomen::Unavailable`
- [x] `Projection::WAIT`、`CHECK_FIRST`、`CHECK_LIMIT`、`catch_up(id = 0, within = WAIT)`
- [x] `Consumer#read` の replica の分岐
- [x] `PG=` 付きで関係する spec が緑

### Task 6: 受入

**Files:** `spec/support/server_worker.cr`、`spec/support/consumer_routes.cr`、`spec/shomen/read_your_writes_spec.cr`（新規）

- [x] ワーカーに `WORKER_REPLICA_URL`。`Add` は `remember`、`Notes` は `catch_up(must_see, within: 300.milliseconds)`
- [x] 2 プロセス: 遅れる replica でも、POST → リダイレクト → GET で変更が見える。`shomen_append` を送らなければ見えない
- [x] 表のプロジェクション（Postgres、プロセス内）: replica が遅れても POST → GET で見える
- [x] 表のプロジェクション（SQLite、プロセス内）: コンシューマが遅れていれば 503、期限を過ぎたクッキーでは 200、クッキーが無ければ 200

### Task 7: README、最終確認

- [x] README（英語と日本語）の「ここまで足したもの」に覚える `id` と replica を書き、「まだ無いもの」から外す
- [x] `crystal tool format --check`、`crystal spec`、`PG=` 付き `crystal spec`、`crystal build src/shomen.cr --error-trace`、`examples/hello` の `crystal spec`
