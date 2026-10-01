# Phase 7a Notification and SSE Across Processes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** フェーズ 7 の 4 本のサブ計画のうち最初の 1 本。どのプロセスで追記しても、すべてのプロセスの `wait_for_append` と SSE ストリームが起きるようにする。Postgres は追記と同じトランザクションで `NOTIFY` を送り、待つ側は専用の接続で `LISTEN` する。どちらの DB も一定間隔で最大の `id` をポーリングし、通知が落ちても遅れるだけにする。受入「An SSE client connected to process A receives an update for an event appended through process B」を満たす。

**Architecture:** `Shomen::StoreAdapter` に `last_id`（DB の最大の `id`）、`notifies?`、`listen(on_id)`、`interrupt_listen` を足す。新しい `Shomen::AppendWatcher` が、ポーリングのファイバーと（通知のある DB では）`LISTEN` のファイバーを持ち、知った `id` を既存の `Shomen::AppendSignal` に `announce` する。`Shomen::Store` は最初の `wait_for_append` で、DB（アダプタの `key`）ごとにプロセスで 1 つの watcher を起動し、その watcher を起動した Store の `close` で止める。`Shomen::SSE` とルートは変えない。SSE は今までどおり `wait_for_append` で待つので、他のプロセスの追記でも起きる（D1、D2）。

**Tech Stack:** Crystal `>= 1.20.0`（開発機は 1.21.1）、標準ライブラリの `spec`、`log`、`socket`。shard は増やさない（`pg` 0.30.0 の `PG.connect_listen` を使う）。開発機の Postgres は Homebrew の 18（`postgres://localhost/postgres`、ユーザー `hiro` は superuser）。

**Spec:** `docs/en/00-INSTRUCTION.md` の「4. Responses」（`sse`）と「10. Scale out」（通知とポーリング）、`docs/en/01-ARCHITECTURE.md` の「Module boundaries」、`docs/en/02-PHASES.md` のフェーズ 7、`docs/en/03-CONVENTIONS.md`。既存の決定 `docs/decisions/20260929-scale-notify.md`、`20260929-phase5-append-signal.md`、`20260929-phase5-sse-response.md`、`20260929-phase6-store-adapters.md`、`20260929-phase6-postgres-adapter.md`、`20260929-phase6-postgres-spec.md`、`20260929-phase6-process-spec.md`。骨子は `docs/superpowers/plans/2026-10-01-phase7-overview.md`。細部は次の決定ファイルに従う。この計画の Task 1 で足すもの:

- `docs/decisions/20261001-phase7-append-watcher.md`（D1）
- `docs/decisions/20261001-phase7-notify-channel.md`（D2）

計画前に確かめたこと（スクラッチでの試作、2026-10-01、`pg` 0.30.0、Postgres 18）:

- `PG.connect_listen(url, "shomen_events", blocking: true) { |n| ... }` を自前のファイバーで呼ぶと、そのファイバーで通知を受け続ける。サーバ側で接続を `pg_terminate_backend` すると、呼んだファイバーで `IO::EOFError` が上がる。`blocking: false` だと、読み取りのループは `pg` が spawn したファイバーで回り、切断の例外はそのファイバーで消えるので、呼び出し側は切断に気付けない
- `SELECT pg_notify('shomen_events', $1)` はトランザクションの中で呼べ、通知はコミットしたときだけ届く。巻き戻したトランザクションの通知は届かない
- URL のクエリの `application_name=...` は `pg_stat_activity.application_name` に出る。`max_pool_size` などプールの引数が URL に残っていても `PG.connect_listen` は接続できる
- `LISTEN` 中の接続の `pg_stat_activity.query` は `LISTEN "shomen_events"` で、同じロールなら `pg_terminate_backend` で切れる
- 存在しない DB への接続は `DB::ConnectionRefused`

## Global Constraints

- 言語は Crystal 1.20 以上。`shard.yml` の `crystal: ">= 1.20.0"` は変えない。shard を足さない。
- `Shomen::Store` の既存の公開 API は変えない: `Shomen::Store.new(url)`、`append(stream, expected_version, events)`、`read(after:, limit: 500)`、`last_appended`、`wait_for_append(after:, within:)`、`close`。足すのは `Shomen::Store.new` の名前付き引数 `poll_interval : Time::Span = 5.seconds` だけ。
- モジュール境界: Store、アダプタ、`AppendSignal`、`AppendWatcher` は HTML を知らない。Command、Event、Projection、SSE、AppendSignal、AppendWatcher は SQLite も Postgres も名指ししない（`spec/shomen/boundary_spec.cr` が検査する）。
- 通知とポーリングのほかに、DB 以外のサービス（Redis など）を使わない。
- コンシューマ、表に置くプロジェクション、`Shomen::Unavailable`、セッションの `id`、replica、`ETag`、断片キャッシュを作らない（7b〜7d）。
- 公開 API は `Shomen::` 配下だけ。1 ファイル 1 主要型。ファイル名は機能名。
- `examples/hello` の既定の Store は `sqlite3://./var/shomen.sqlite3` のまま。`examples/hello` のコードは変えない。
- コードと識別子は英語。この計画と決定ログは日本語。
- ユーザーが指示するまで commit しない。この計画に commit 手順は無い。
- `crystal tool format` を通し、警告を残して完了にしない。
- テストは固定ポートを bind しない。sleep で同期しない。待ちは Channel と子プロセスの出力の行で行い、別プロセスや DB が変える状態だけは `wait_until`（上限つきの繰り返し、sleep なし）で待つ。上限は失敗の検出だけに使う。
- Postgres の spec は `SHOMEN_SPEC_POSTGRES` が無ければ pending。受入の確認は `SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres` を付けて行う。以下、`PG=` と書いたらこの変数を付けて実行する意味とする。
- 検証でリポジトリルートにできる実行ファイル `shomen` と `shomen.dwarf` は `docs/decisions/20260928-build-artifact.md` のとおり削除する。

実行はリポジトリルートで行う。`Shomen::VERSION` は `"0.0.0"` のまま変えない。

## Review Focus

- `LISTEN` の接続がまだ開いている途中で Store を閉じる。最初の `pg_terminate_backend` は空振りし、その後に開いた接続が残りかねない。閉じた後に `shomen-listen-` の接続が 1 本も残らないこと。Task 4 の "closes a listening connection that was still opening when the store closed" で固定する。
- 同じチャネル `shomen_events` に、`id` でないペイロードの通知が来る（運用者の手打ち、別のツール）。watcher は無視し、接続を張り直さず、その後の通知でも起きる。Task 4 の "ignores a notification on its channel that carries no id" で固定する。
- ポーリングの問い合わせが失敗する（DB の再起動中など）。watcher のファイバーは死なずにログを書き、次の間隔で問い合わせ直し、DB が戻れば追いつく。Task 3 の "keeps polling after a poll fails, and logs the failure" で固定する。
- 同じ DB を開いた 2 つの Store のうち、watcher を起動した方が閉じ、もう一方がまだ待つ。もう一方の次の `wait_for_append` が watcher を起動し直し、他のプロセスの追記で起きる。Task 3 の "starts watching again for a store that waits after the watching store closed" で固定する。
- 閉じた Store で `wait_for_append` を呼ぶ。watcher を起動せず（閉じた DB に問い合わせず）、上限まで待って `false` を返す。Task 3 の "does not start watching after the store closed" で固定する。

## File Map

| ファイル | 役割 | Task |
|---|---|---|
| `docs/en/02-PHASES.md`、`docs/02-PHASES.md` | 現行フェーズをフェーズ 7 にする | 1 |
| `docs/en/00-INSTRUCTION.md`、`docs/00-INSTRUCTION.md` | 仕様 4 の `sse`、仕様 10 の通知とポーリング | 1 |
| `docs/en/01-ARCHITECTURE.md`、`docs/01-ARCHITECTURE.md` | モジュール表の Store と SSE | 1 |
| `docs/decisions/20261001-phase7-*.md` | D1、D2 | 1 |
| `src/shomen/store_adapter.cr` | `last_id`、`notifies?`、`listen`、`interrupt_listen` | 2, 3 |
| `src/shomen/sqlite_adapter.cr` | `last_id` | 2 |
| `src/shomen/postgres_adapter.cr` | `last_id`、追記の `NOTIFY`（2）、`LISTEN` と切断（4） | 2, 4 |
| `src/shomen/append_watcher.cr` | `Shomen::AppendWatcher`（新規） | 3, 4 |
| `src/shomen/store.cr` | `poll_interval:`、watcher の起動と停止 | 3 |
| `src/shomen/append_signal.cr`、`src/shomen/sse.cr`、`src/shomen/route.cr` | 「このプロセスだけ」と書いたコメント | 5 |
| `spec/support/store.cr` | `insert_unannounced`、`append_elsewhere` | 2, 4 |
| `spec/support/postgres.cr` | `PostgresSpec.listeners` | 4 |
| `spec/support/server_worker.cr` | `WORKER_POLL_MS` | 5 |
| `spec/shomen/store_spec.cr` | `last_id` | 2 |
| `spec/shomen/postgres_adapter_spec.cr` | 追記の通知 | 2 |
| `spec/shomen/append_watcher_spec.cr` | watcher（新規） | 3, 4 |
| `spec/shomen/sse_processes_spec.cr` | 受入（新規） | 5 |
| `spec/shomen/boundary_spec.cr` | `append_watcher` を境界の検査に足す | 3 |
| `README.md`、`README.ja.md` | フェーズ 7 でここまで足したもの | 6 |

---

### Task 1: 現行フェーズ、仕様、決定ファイル

**Files:**
- Modify: `docs/en/02-PHASES.md:5-9`、末尾の 1 行
- Modify: `docs/02-PHASES.md:5-9`、`:173`
- Modify: `docs/en/00-INSTRUCTION.md:159`、`:260`
- Modify: `docs/00-INSTRUCTION.md:159`、`:260`
- Modify: `docs/en/01-ARCHITECTURE.md:40`、`:44`
- Modify: `docs/01-ARCHITECTURE.md:40`、`:44`
- Create: `docs/decisions/20261001-phase7-append-watcher.md`
- Create: `docs/decisions/20261001-phase7-notify-channel.md`

**Interfaces:**
- Consumes: なし
- Produces: 後続タスクが従う決定 D1、D2。ここで決めた名前（`Shomen::AppendWatcher`、`start` しない生成即起動、`stop`、`stopped?`、`RETRY_FIRST`、`STOP_LIMIT`、`STOP_RETRY`、`Shomen::StoreAdapter#last_id`、`#notifies?`、`#listen(on_id : Int64 -> Nil)`、`#interrupt_listen`、`Shomen::Store::POLL_INTERVAL`、`poll_interval:`、`Shomen::PostgresAdapter::CHANNEL`（`"shomen_events"`）、`NOTIFY`、`SELECT_LAST`、`TERMINATE`、`LISTENER_PREFIX`（`"shomen-listen-"`）、`WORKER_POLL_MS`）は Task 2〜5 のコードと一致させる。

- [ ] **Step 1: 現行フェーズを書き換える（英語）**

`docs/en/02-PHASES.md` の「## Current phase」の本文を次にする。

```markdown
## Current phase

**Phase 7 — scale out**

Phase 6 acceptance is met. When phase 7 acceptance is met, stop and wait for the next instruction.
```

同じファイルの最後の行 `This phase does not start until the user asks for it.`（フェーズ 7 の節の最後）と、その前の空行を消す。

- [ ] **Step 2: 現行フェーズを書き換える（日本語訳）**

`docs/02-PHASES.md` の「## 現行フェーズ」の本文を次にする。

```markdown
## 現行フェーズ

**フェーズ 7 — スケールアウト**

フェーズ 6 の受入は満たした。7 の受入を満たしたら停止し、ユーザーの次指示を待つ。
```

見出しの語は、149 行目の `## フェーズ 7 — スケールアウト` に合わせてある。同じファイルの 173 行目 `このフェーズはユーザーが明示するまで開始しない。` と、その前の空行を消す。

- [ ] **Step 3: 仕様 4 と 10 を直す（英語）**

`docs/en/00-INSTRUCTION.md` の 159 行目を次にする。

```markdown
- `sse(store, heartbeat = 15.seconds) { fragment }` returns an event stream (`text/event-stream`). It renders the fragment now and again after each append to `store`, through this process or, by notification and polling, through any other, and sends its HTML whenever it changed (`docs/decisions/20260929-phase5-sse-response.md`, `docs/decisions/20261001-phase7-append-watcher.md`)
```

260 行目の末尾 `(`docs/decisions/20260929-scale-notify.md`)` の後に、同じ箇条の続きとして次の文を足す（1 行のまま）。

```markdown
 A process starts listening and polling for a database when something first waits for an append to it, and stops when the store that started them closes. `Shomen::Store.new(url, poll_interval: 5.seconds)` sets the interval (`docs/decisions/20261001-phase7-append-watcher.md`, `docs/decisions/20261001-phase7-notify-channel.md`)
```

- [ ] **Step 4: 仕様 4 と 10 を直す（日本語訳）**

`docs/00-INSTRUCTION.md` の 159 行目を次にする。

```markdown
- `sse(store, heartbeat = 15.seconds) { 断片 }` → イベントストリーム（`text/event-stream`）。断片を今描き、`store` への追記のたびに描き直し、HTML が変わったときだけ送る。このプロセスの追記に加え、ほかのプロセスの追記も通知とポーリングで届く（`docs/decisions/20260929-phase5-sse-response.md`、`docs/decisions/20261001-phase7-append-watcher.md`）
```

260 行目の末尾 `（`docs/decisions/20260929-scale-notify.md`）` の後に、同じ箇条の続きとして次の文を足す（1 行のまま）。

```markdown
プロセスは、ある DB への追記を何かが初めて待ったときに、その DB の通知の受信とポーリングを始め、それを始めた Store が閉じたときに止める。間隔は `Shomen::Store.new(url, poll_interval: 5.seconds)` で決める（`docs/decisions/20261001-phase7-append-watcher.md`、`docs/decisions/20261001-phase7-notify-channel.md`）
```

- [ ] **Step 5: モジュール表を直す（英語と日本語訳）**

`docs/en/01-ARCHITECTURE.md` の 40 行目と 44 行目を次にする。

```markdown
| `Shomen::Store` | Append and read, and wake what waits for an append, from this process at once and from others by notification and polling | Event |
```

```markdown
| `Shomen::SSE` | Send a fragment again after each append the store learns of | Response, Store, Fragment |
```

`docs/01-ARCHITECTURE.md` の 40 行目と 44 行目を次にする。

```markdown
| `Shomen::Store` | 追記と読取。追記を待つものを、このプロセスの追記ではすぐに、ほかのプロセスの追記では通知とポーリングで起こす | Event |
```

```markdown
| `Shomen::SSE` | Store が知った追記のたびに断片を送り直す | Response, Store, Fragment |
```

- [ ] **Step 6: D1 を書く**

`docs/decisions/20261001-phase7-append-watcher.md`:

```markdown
# 状況

`20260929-scale-notify.md` は、Postgres が追記の後に通知を送り、各プロセスが `LISTEN` 専用の接続を 1 本持ち、一定間隔（既定 5 秒）でもポーリングすると決めた。`20260929-phase5-append-signal.md` は、待つ側の API を `Shomen::Store#last_appended` と `#wait_for_append` に閉じ、フェーズ 7 では同じ API の裏で通知とポーリングが `AppendSignal#announce` を呼べばよいとした。いつ受信とポーリングを始めて止めるか、間隔をどこで決めるか、接続が切れたときの扱いは決めていない。

# 決定

`Shomen::AppendWatcher` を置く。アダプタと `AppendSignal` と間隔を受け取り、生成したときに DB の最大の `id`（`StoreAdapter#last_id`）を 1 回読んで `announce` し、次の 2 つのファイバーを始める。

- ポーリング: 間隔ごとに `last_id` を読んで `announce` する。問い合わせが失敗したら `shomen` のログに warn を書き、次の間隔で続ける
- 受信（`StoreAdapter#notifies?` が真の DB だけ）: `last_id` を読んで `announce` してから `StoreAdapter#listen` で通知を待ち、届いた `id` を `announce` する。接続が切れたら warn を書き、100 ミリ秒後につなぎ直す。続けて失敗するたびに待ちを倍にし、間隔を上限にする。前の接続が間隔より長く続いていたら、待ちを 100 ミリ秒に戻す

`stop` はポーリングを止め、受信中の接続を `StoreAdapter#interrupt_listen` で切り、受信のファイバーが終わるのを待つ。接続を開いている途中で 1 回目の切断が空振りすることがあるので、50 ミリ秒ごとに切断を繰り返し、5 秒で諦めて warn を書く。

`Shomen::Store` は、最初の `wait_for_append` で watcher を作る。watcher はアダプタの `key` ごとにプロセスで 1 つにし、同じ DB を開いたほかの Store は作られた watcher を使う。間隔は、watcher を作った Store の `poll_interval`（`Shomen::Store.new(url, poll_interval: 5.seconds)`、正でなければ `ArgumentError`）にする。watcher を作った Store の `close` が watcher を止めて一覧から外す。ほかの Store は、次の `wait_for_append` で watcher を作り直す。閉じた Store の `wait_for_append` は watcher を作らない。

`last_appended` は「このプロセスが知っている最大の `id`」になる。このプロセスの追記はコミットの直後に、ほかのプロセスの追記は通知かポーリングで知る。

# 理由

待つものが無いプロセスでは、接続もファイバーも問い合わせも増えない。SSE を使わないアプリは、フェーズ 5 と同じく何も増えない。受信の前に最大の `id` を読むので、接続が切れていた間の追記はつなぎ直した時点で知らせる。読んでから `LISTEN` が効くまでの間の追記は、次のポーリングで知らせる。`crystal-pg` の `LISTEN` は接続を開いてから読み取りに入るまでを 1 つの呼び出しで行い、その間に割り込む口が無いので、この隙間はポーリングに任せる。同じ DB ごとに 1 つにすれば、仕様 10 の「LISTEN 専用の接続を 1 本」を守れる。間隔を Store の引数にしたのは、spec と、通知の無い SQLite を複数プロセスで使うアプリが短くできるようにするためである。

# 破棄した案

- Store を開いたときに必ず受信とポーリングを始める（SSE もコンシューマも使わないプロセスが接続と問い合わせを持つ）
- Store ごとに watcher を持つ（同じ DB を 2 つの Store で開くと `LISTEN` の接続が 2 本になる）
- watcher を参照の数で共有し、最後の Store が閉じるまで止めない（数え違いで接続が残る。閉じた Store のアダプタで問い合わせ続けることもある）
- つなぎ直しを一定間隔にする（DB が落ちている間、接続の試みが続く）
- 待つ側が毎回 DB の最大の `id` を読む（待つたびに問い合わせが増える）
```

- [ ] **Step 7: D2 を書く**

`docs/decisions/20261001-phase7-notify-channel.md`:

```markdown
# 状況

`20260929-scale-notify.md` は、Postgres アダプタが追記と同じトランザクションで `NOTIFY` を送り、ペイロードを新しい最大の `id` だけにし、`LISTEN` の接続をプールに入れずに `PG.connect_listen` で直接つなぐと決めた。チャネルの名前、接続の閉じ方、切断の見つけ方は決めていない。`crystal-pg` 0.30.0 の `PG.connect_listen` は、`blocking: false` なら読み取りを自分で spawn したファイバーで行い、切断の例外はそのファイバーで消える。`blocking: true` なら呼んだファイバーで読み続け、切断で例外を上げるが、呼び出しから戻らないので接続を閉じる口が無い。

# 決定

- チャネルは `shomen_events` 1 つにする。`NOTIFY` は DB ごとに届くので、DB をまたいで混ざらない
- 追記は、挿入の後、`COMMIT` の前に、同じ接続で `SELECT pg_notify('shomen_events', 最後の id の 10 進)` を実行する。版が合わずに巻き戻した追記は通知しない
- 受信は `PG.connect_listen(url, "shomen_events", blocking: true)` を watcher のファイバーで呼ぶ。切断は、そのファイバーに上がる例外で知る
- 受信の接続は、Store の URL に `application_name=shomen-listen-` と 16 桁の 16 進を足した URL でつなぐ。URL がすでに `application_name` を持っていても、受信の接続だけはこの名前で上書きする
- 受信の接続を閉じるときは、プールの接続で `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name = $1 AND pid <> pg_backend_pid()` を実行する
- ペイロードが `id`（10 進の整数）として読めない通知は無視する。`announce` は `id` を下げないので、古い `id` の通知は何もしない

# 理由

`COMMIT` の前に送った `NOTIFY` は、コミットしたときだけ、コミットの順に届く。追記はアドバイザリロックで直列なので、通知の `id` はコミットの順に増える。切断を例外で知るには、読み取りのループを自分のファイバーで回すしかない。接続を名前で探して終わらせれば、接続の内部に触れずに閉じられる。同じロールの接続は、superuser でなくても `pg_terminate_backend` で終わらせられる。名前に乱数を入れるので、同じ DB を使うほかのプロセスの受信を切らない。チャネルにはアプリの外からも `NOTIFY` を送れるので、読めないペイロードで受信を止めない。

# 破棄した案

- `blocking: false` で受け、切断はポーリングだけで補う（切れたまま気付かず、遅れがいつもポーリングの間隔になる）
- 受信の接続から定期的に問い合わせを送って生きているか確かめる（`crystal-pg` の公開 API では、受信中の接続に問い合わせを送れない）
- `crystal-pg` のクラスを開き直して、受信中の接続を閉じるメソッドを足す（依存の内部に結びつく）
- Store が閉じても受信の接続を残し、プロセスの終了に任せる（spec と、Store を開き直すアプリで接続が残る）
- DB ごとに別の名前のチャネルにする（`NOTIFY` はもともと DB の中にしか届かない）
```

- [ ] **Step 8: 文書の差分を確かめる**

Run: `git diff --stat docs/ && git status --short docs/`
Expected: `docs/en/02-PHASES.md`、`docs/02-PHASES.md`、`docs/en/00-INSTRUCTION.md`、`docs/00-INSTRUCTION.md`、`docs/en/01-ARCHITECTURE.md`、`docs/01-ARCHITECTURE.md` が変わり、`docs/decisions/20261001-phase7-append-watcher.md` と `docs/decisions/20261001-phase7-notify-channel.md` が新しい。英語と日本語訳で同じ箇所を変えている。

---

### Task 2: DB の最大の `id` と、追記の通知

**Files:**
- Modify: `src/shomen/store_adapter.cr`
- Modify: `src/shomen/sqlite_adapter.cr`
- Modify: `src/shomen/postgres_adapter.cr`
- Modify: `spec/support/store.cr`
- Test: `spec/shomen/store_spec.cr`、`spec/shomen/postgres_adapter_spec.cr`

**Interfaces:**
- Consumes: 既存の `Shomen::StoreAdapter`、`store_it`、`postgres_it`、`note`
- Produces: `abstract def last_id : Int64`（`Shomen::StoreAdapter`）、`Shomen::SQLiteAdapter::SELECT_LAST`、`Shomen::PostgresAdapter::CHANNEL = "shomen_events"`、`NOTIFY`、`SELECT_LAST`、spec の `insert_unannounced(url : String, stream : String) : Nil`

- [ ] **Step 1: spec の補助を足す**

`spec/support/store.cr` の末尾に足す。

```crystal
# Commits one event the way another writer would: with no notification
# and no announcement to this process. The SQL runs on SQLite and Postgres.
def insert_unannounced(url : String, stream : String) : Nil
  DB.open(url) do |db|
    db.exec(%(INSERT INTO events (stream, version, type, payload, at) VALUES ('#{stream}', 1, 'spec.noted', '{"text":"unannounced","at":"2026-10-01T00:00:00Z"}', '2026-10-01T00:00:00Z')))
  end
end
```

- [ ] **Step 2: 失敗するテストを書く（最大の `id`）**

`spec/shomen/store_spec.cr` の最後の `end`（`describe` の終わり）の前に足す。

```crystal
  store_it "reads the highest id any writer committed" do |store, url|
    adapter = store.@adapter
    adapter.last_id.should eq(0_i64)
    store.append("a", 0_i64, [SpecEvents::Noted.new("1"), SpecEvents::Noted.new("2")] of Shomen::Event)
    insert_unannounced(url, "elsewhere")
    adapter.last_id.should eq(3_i64)
    store.last_appended.should eq(2_i64)
  end
```

- [ ] **Step 3: 失敗するテストを書く（通知）**

`spec/shomen/postgres_adapter_spec.cr` の最後の `end` の前に足す。

```crystal
  postgres_it "notifies its channel with the last id once an append commits, and not for a conflict" do |store, url|
    payloads = Channel(String).new(4)
    listener = PG.connect_listen(url, Shomen::PostgresAdapter::CHANNEL) { |notification| payloads.send(notification.payload) }
    begin
      store.append("a", 0_i64, [SpecEvents::Noted.new("1"), SpecEvents::Noted.new("2")] of Shomen::Event)
      expect_raises(Shomen::Conflict) { store.append("a", 0_i64, note("3")) }
      store.append("b", 0_i64, note("4"))
      received = Array.new(2) do
        select
        when payload = payloads.receive
          payload
        when timeout(5.seconds)
          fail "no notification within 5 seconds"
        end
      end
      received.should eq(["2", "3"])
    ensure
      listener.close
    end
  end
```

`PG.connect_listen` を `blocking` なしで呼ぶと、`LISTEN` が効いてから戻る。確かめるのは 2 点。2 件を書いた追記の通知は 1 つで、最後の `id`（`"2"`）を運ぶ。衝突した追記の後に余計な通知が挟まらず、次に届くのは次の追記の `"3"`。

- [ ] **Step 4: テストが失敗するのを確かめる**

Run: `PG= crystal spec spec/shomen/store_spec.cr spec/shomen/postgres_adapter_spec.cr`（`PG=` は `SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres`）
Expected: コンパイルエラー `undefined method 'last_id'`、または `undefined constant Shomen::PostgresAdapter::CHANNEL`。

- [ ] **Step 5: 抽象メソッドを足す**

`src/shomen/store_adapter.cr` の `abstract def read(...)` の後に足す。

```crystal
  # The highest id in the database, whoever appended it; 0 when it has no
  # event.
  abstract def last_id : Int64
```

- [ ] **Step 6: SQLite の `last_id`**

`src/shomen/sqlite_adapter.cr` の `SELECT_AFTER` の次の行に足す。

```crystal
  SELECT_LAST    = "SELECT COALESCE(MAX(id), 0) FROM events"
```

`def read` の後に足す。

```crystal
  def last_id : Int64
    @lock.synchronize { @db.scalar(SELECT_LAST).as(Int64) }
  end
```

- [ ] **Step 7: Postgres の `last_id` と通知**

`src/shomen/postgres_adapter.cr` の定数に足す（`SELECT_AFTER` の後）。

```crystal
  SELECT_LAST    = "SELECT COALESCE(MAX(id), 0) FROM events"
  # docs/decisions/20261001-phase7-notify-channel.md
  CHANNEL = "shomen_events"
  NOTIFY  = "SELECT pg_notify($1, $2)"
```

`append` の `locked do |connection| ... end` の中で、`last_id` を返す前に通知を送る。メソッド全体を次にする。

```crystal
  # Sends the last id on CHANNEL before COMMIT, so the notification goes
  # out only when the append commits.
  def append(stream : String, expected_version : Int64, rows : Array(Row)) : Int64
    locked do |connection|
      check_version(stream, connection.scalar(SELECT_VERSION, stream).as(Int64), expected_version)
      last_id = 0_i64
      rows.each_with_index(1) do |row, offset|
        type, payload, at = row
        last_id = connection.scalar(INSERT, stream, expected_version + offset, type, payload, at).as(Int64)
      end
      connection.exec(NOTIFY, CHANNEL, last_id.to_s)
      last_id
    end
  end
```

`def read` の後に足す。

```crystal
  def last_id : Int64
    @db.scalar(SELECT_LAST).as(Int64)
  end
```

- [ ] **Step 8: テストが通るのを確かめる**

Run: `PG= crystal spec spec/shomen/store_spec.cr spec/shomen/postgres_adapter_spec.cr`
Expected: すべて PASS（pending 0）。

- [ ] **Step 9: 全体を確かめる**

Run: `crystal tool format && PG= crystal spec`
Expected: 失敗 0。既存の Postgres の spec（ロックの待ち、2 プロセスの順序）も PASS。

---

### Task 3: ポーリングで他のプロセスの追記を知る（`Shomen::AppendWatcher`）

**Files:**
- Create: `src/shomen/append_watcher.cr`
- Modify: `src/shomen/store_adapter.cr`
- Modify: `src/shomen/store.cr`
- Modify: `spec/shomen/boundary_spec.cr`
- Test: `spec/shomen/append_watcher_spec.cr`（新規）

**Interfaces:**
- Consumes: Task 2 の `StoreAdapter#last_id`、`insert_unannounced`、既存の `Shomen::AppendSignal`（`announce`、`wait`、`waiting`、`last`）、`wait_until`
- Produces:
  - `Shomen::StoreAdapter#notifies? : Bool`（既定 `false`）、`#listen(on_id : Int64 -> Nil) : Nil`（既定は何もしない）、`#interrupt_listen : Nil`（既定は何もしない）
  - `Shomen::AppendWatcher.new(adapter : Shomen::StoreAdapter, signal : Shomen::AppendSignal, interval : Time::Span)`（生成で最大の `id` を `announce` し、ファイバーを始める）、`#stop : Nil`、`#stopped? : Bool`
  - `Shomen::Store::POLL_INTERVAL = 5.seconds`、`Shomen::Store.new(url : String, poll_interval : Time::Span = POLL_INTERVAL)`、spec が読む ivar `@watcher : Shomen::AppendWatcher?` と `@signal`

- [ ] **Step 1: 失敗するテストを書く**

`spec/shomen/append_watcher_spec.cr`:

```crystal
require "../spec_helper"

private def receive_within(channel : Channel(Bool), within : Time::Span = 20.seconds) : Bool
  select
  when value = channel.receive
    value
  when timeout(within)
    raise "no answer within #{within}"
  end
end

# An adapter whose polls fail a given number of times after the first.
private class FlakyAdapter < Shomen::StoreAdapter
  property last : Int64 = 0_i64
  @calls = 0

  def initialize(@failures : Int32)
  end

  def key : String
    "flaky"
  end

  def append(stream : String, expected_version : Int64, rows : Array(Row)) : Int64
    raise "not used"
  end

  def read(after : Int64, limit : Int32) : Array(Stored)
    [] of Stored
  end

  def last_id : Int64
    @calls += 1
    if @calls > 1 && @failures > 0
      @failures -= 1
      raise "the database is away"
    end
    @last
  end

  def close : Nil
  end
end

describe Shomen::AppendWatcher do
  it "keeps polling after a poll fails, and logs the failure" do
    signal = Shomen::AppendSignal.new
    adapter = FlakyAdapter.new(failures: 2)
    Log.capture("shomen") do |logs|
      watcher = Shomen::AppendWatcher.new(adapter, signal, 1.millisecond)
      begin
        adapter.last = 5_i64
        signal.wait(after: 0_i64, within: 10.seconds).should be_true
        signal.last.should eq(5_i64)
        logs.check(:warn, "could not poll for appends")
      ensure
        watcher.stop
      end
    end
  end

  store_it "learns of an event another writer committed at the next poll" do |_, url|
    store = Shomen::Store.new(url, poll_interval: 20.milliseconds)
    begin
      woke = Channel(Bool).new(1)
      spawn { woke.send(store.wait_for_append(after: 0_i64, within: 20.seconds)) }
      wait_until { store.@signal.waiting == 1 }
      insert_unannounced(url, "elsewhere")
      receive_within(woke).should be_true
      store.last_appended.should eq(1_i64)
    ensure
      store.close
    end
  end

  store_it "starts watching only when something waits, and stops when the store that started it closes" do |_, url|
    store = Shomen::Store.new(url)
    store.append("a", 0_i64, note("1"))
    store.read(after: 0_i64)
    store.@watcher.should be_nil
    store.wait_for_append(after: 0_i64, within: 1.millisecond).should be_true
    watcher = store.@watcher
    watcher.should_not be_nil
    store.close
    watcher.try(&.stopped?).should be_true
  end

  store_it "starts watching again for a store that waits after the watching store closed" do |_, url|
    first = Shomen::Store.new(url, poll_interval: 20.milliseconds)
    second = Shomen::Store.new(url, poll_interval: 20.milliseconds)
    begin
      first.wait_for_append(after: 0_i64, within: 1.millisecond).should be_false
      second.wait_for_append(after: 0_i64, within: 1.millisecond).should be_false
      second.@watcher.should be_nil
      first.close
      woke = Channel(Bool).new(1)
      spawn { woke.send(second.wait_for_append(after: 0_i64, within: 20.seconds)) }
      wait_until { second.@signal.waiting == 1 }
      insert_unannounced(url, "elsewhere")
      receive_within(woke).should be_true
      second.@watcher.should_not be_nil
    ensure
      second.close
    end
  end

  store_it "does not start watching after the store closed" do |_, url|
    store = Shomen::Store.new(url)
    store.close
    store.wait_for_append(after: 0_i64, within: 1.millisecond).should be_false
    store.@watcher.should be_nil
  end

  it "refuses a poll interval that is not positive" do
    path = File.tempname("shomen-store", ".sqlite3")
    begin
      expect_raises(ArgumentError, "poll_interval must be positive") do
        Shomen::Store.new("sqlite3://#{path}", poll_interval: 0.seconds)
      end
      File.exists?(path).should be_false
    ensure
      remove_database(path)
    end
  end
end
```

`store_it` が渡す Store はこの例では使わない（開いたまま例の終わりに閉じる）。例の中で別の Store を開くのは、間隔を変えるためと、`close` の後を確かめるため。2 つ目の例の Postgres 版は、Task 3 の時点では `notifies?` が偽なのでポーリングだけで起きる。Task 4 の後も、`insert_unannounced` は通知を送らないのでポーリングだけで起きる。

- [ ] **Step 2: テストが失敗するのを確かめる**

Run: `PG= crystal spec spec/shomen/append_watcher_spec.cr`
Expected: コンパイルエラー `undefined constant Shomen::AppendWatcher`。

- [ ] **Step 3: アダプタの既定のメソッドを足す**

`src/shomen/store_adapter.cr` の `abstract def close : Nil` の後に足す。

```crystal
  # Whether an append sends a notification that listen receives.
  def notifies? : Bool
    false
  end

  # Waits for notifications and passes on the id each carries, until
  # interrupt_listen ends it or the connection breaks, which raises.
  # Returns at once for a database that sends none.
  def listen(on_id : Int64 -> Nil) : Nil
  end

  # Ends a listen in progress from another fiber.
  def interrupt_listen : Nil
  end
```

- [ ] **Step 4: `Shomen::AppendWatcher` を書く**

`src/shomen/append_watcher.cr`:

```crystal
require "log"
require "./store_adapter"
require "./append_signal"

# Tells this process of the appends of every process: it polls the
# highest id at an interval and, on a database that sends notifications,
# listens on a connection of its own. Both announce to the signal, so a
# lost notification only adds delay
# (docs/decisions/20261001-phase7-append-watcher.md).
class Shomen::AppendWatcher
  RETRY_FIRST = 100.milliseconds
  STOP_LIMIT  = 5.seconds
  STOP_RETRY  = 50.milliseconds

  Log = ::Log.for("shomen")

  @stop = Channel(Nil).new
  @listened = Channel(Nil).new(1)
  @stopped = Atomic(Bool).new(false)

  def initialize(@adapter : Shomen::StoreAdapter, @signal : Shomen::AppendSignal, @interval : Time::Span)
    catch_up
    spawn(name: "shomen poll") { poll }
    spawn(name: "shomen listen") { listen } if @adapter.notifies?
  end

  def stopped? : Bool
    @stopped.get
  end

  # The connection may still be opening when the first interrupt runs, so
  # the interrupt repeats until the listen ends.
  def stop : Nil
    return if @stopped.swap(true)
    @stop.close
    return unless @adapter.notifies?
    deadline = Time.instant + STOP_LIMIT
    until Time.instant > deadline
      @adapter.interrupt_listen
      select
      when @listened.receive
        return
      when timeout(STOP_RETRY)
      end
    end
    Log.warn { "the connection that listens for appends did not close within #{STOP_LIMIT}" }
  rescue ex
    Log.warn(exception: ex) { "could not close the connection that listens for appends" }
  end

  private def catch_up : Nil
    @signal.announce(@adapter.last_id)
  end

  private def poll : Nil
    loop do
      select
      when @stop.receive?
        return
      when timeout(@interval)
      end
      begin
        catch_up
      rescue ex
        return if stopped?
        Log.warn(exception: ex) { "could not poll for appends" }
      end
    end
  end

  # Reads the highest id before each connection, so what was appended
  # while none listened arrives at once; an append between that read and
  # the LISTEN arrives with the next poll.
  private def listen : Nil
    delay = RETRY_FIRST
    until stopped?
      began = Time.instant
      begin
        catch_up
        @adapter.listen(->(id : Int64) { @signal.announce(id) })
      rescue ex
        break if stopped?
        Log.warn(exception: ex) { "lost the connection that listens for appends; connecting again" }
      end
      delay = RETRY_FIRST if Time.instant - began > @interval
      select
      when @stop.receive?
        break
      when timeout(delay)
      end
      delay = {delay * 2, @interval}.min
    end
  ensure
    @listened.send(nil)
  end
end
```

- [ ] **Step 5: Store に組み込む**

`src/shomen/store.cr` を次のように変える。`require "./postgres_adapter"` の後に `require "./append_watcher"` を足す。クラスの先頭を次にする。

```crystal
class Shomen::Store
  POLL_INTERVAL = 5.seconds

  @@signals = {} of String => Shomen::AppendSignal
  @@signals_lock = Mutex.new
  # One per database in a process (docs/decisions/20261001-phase7-append-watcher.md).
  @@watchers = {} of String => Shomen::AppendWatcher
  @@watchers_lock = Mutex.new

  @adapter : Shomen::StoreAdapter
  @signal : Shomen::AppendSignal
  # The watcher this store started; it stops it on close.
  @watcher : Shomen::AppendWatcher? = nil
  @closed = false

  def initialize(url : String, @poll_interval : Time::Span = POLL_INTERVAL)
    raise ArgumentError.new("poll_interval must be positive") unless @poll_interval.positive?
    uri = begin
```

（`uri = begin` 以降の既存の本体はそのまま。）

`last_appended` と `wait_for_append` を次にする。

```crystal
  # The highest id this process knows the database holds: its own appends
  # at once, those of other processes once a notification or a poll tells
  # it. 0 before the first.
  def last_appended : Int64
    @signal.last
  end

  # Waits until this process learns of an event with an id above after.
  # The first wait on a database starts listening and polling for it.
  # False when within passes first.
  def wait_for_append(after : Int64, within : Time::Span) : Bool
    watch
    @signal.wait(after, within)
  end
```

`close` を次にし、その後に `watch` を足す。

```crystal
  def close : Nil
    watcher = @@watchers_lock.synchronize do
      @closed = true
      owned = @watcher
      @watcher = nil
      @@watchers.delete(@adapter.key) if owned
      owned
    end
    watcher.try(&.stop)
    @adapter.close
  end

  private def watch : Nil
    @@watchers_lock.synchronize do
      return if @closed
      key = @adapter.key
      unless @@watchers.has_key?(key)
        watcher = Shomen::AppendWatcher.new(@adapter, @signal, @poll_interval)
        @@watchers[key] = watcher
        @watcher = watcher
      end
    end
  end
```

クラスのコメントの最後の文 `After a commit an append wakes what waits for it in this process.` を次にする。

```crystal
# After a commit an append wakes what waits for it in this process; the
# appends of other processes wake it through Shomen::AppendWatcher.
```

- [ ] **Step 6: 境界の検査に足す**

`spec/shomen/boundary_spec.cr` の 2 つの一覧に `append_watcher` を足す。

```crystal
    %w(store store_adapter sqlite_adapter postgres_adapter event recorded conflict append_signal append_watcher).each do |name|
```

```crystal
    %w(command event rejected recorded projection append_signal append_watcher sse).each do |name|
```

- [ ] **Step 7: テストが通るのを確かめる**

Run: `PG= crystal spec spec/shomen/append_watcher_spec.cr spec/shomen/boundary_spec.cr spec/shomen/store_spec.cr spec/shomen/sse_spec.cr`
Expected: すべて PASS（pending 0）。

- [ ] **Step 8: 全体を確かめる**

Run: `crystal tool format && PG= crystal spec && crystal spec`
Expected: どちらも失敗 0。`PG=` なしでは Postgres の例が pending になる。

---

### Task 4: Postgres の `LISTEN`、つなぎ直し、切断

**Files:**
- Modify: `src/shomen/postgres_adapter.cr`
- Modify: `spec/support/postgres.cr`
- Modify: `spec/support/store.cr`
- Test: `spec/shomen/append_watcher_spec.cr`

**Interfaces:**
- Consumes: Task 2 の `CHANNEL`、`insert_unannounced`。Task 3 の `notifies?`、`listen`、`interrupt_listen`、`Shomen::AppendWatcher`、`Shomen::Store.new(url, poll_interval:)`
- Produces: `Shomen::PostgresAdapter::LISTENER_PREFIX = "shomen-listen-"`、`TERMINATE`、ivar `@listen_url`、`@listener_name`。spec の `PostgresSpec.listeners(db : DB::Database) : Array(Int32)`（受信中の接続の pid）、`append_elsewhere(url : String, stream : String, count : Int32) : Nil`

- [ ] **Step 1: spec の補助を足す**

`spec/support/postgres.cr` の `module PostgresSpec` の中、`with_database` の後に足す。

```crystal
  # The pids of the connections in db's database that listen for appends
  # (docs/decisions/20261001-phase7-notify-channel.md).
  def self.listeners(db : DB::Database) : Array(Int32)
    db.query_all(
      "SELECT pid FROM pg_stat_activity WHERE datname = current_database() AND application_name LIKE 'shomen-listen-%' AND query LIKE 'LISTEN%'",
      as: Int32,
    )
  end
```

`spec/support/store.cr` の末尾に足す。

```crystal
# Appends count events to stream through a store in another process.
def append_elsewhere(url : String, stream : String, count : Int32) : Nil
  status = Process.run(Workers.binary("spec/support/store_worker.cr"), [url, stream, count.to_s], error: :inherit)
  raise "store_worker failed" unless status.success?
end
```

- [ ] **Step 2: 失敗するテストを書く**

`spec/shomen/append_watcher_spec.cr` の `describe` の最後の `end` の前に足す。

```crystal
  postgres_it "wakes a waiting fiber on the notification of an append through another process, before any poll" do |_, url|
    store = Shomen::Store.new(url, poll_interval: 1.hour)
    begin
      woke = Channel(Bool).new(1)
      spawn { woke.send(store.wait_for_append(after: 0_i64, within: 20.seconds)) }
      DB.open(url) { |db| wait_until(10.seconds) { PostgresSpec.listeners(db).size == 1 } }
      append_elsewhere(url, "elsewhere", 1)
      receive_within(woke).should be_true
      store.last_appended.should eq(1_i64)
    ensure
      store.close
    end
  end

  postgres_it "listens on one connection of its own for every store on the database in this process" do |store, url|
    other = Shomen::Store.new(url)
    begin
      store.wait_for_append(after: 0_i64, within: 1.millisecond)
      other.wait_for_append(after: 0_i64, within: 1.millisecond)
      other.@watcher.should be_nil
      DB.open(url) { |db| wait_until(10.seconds) { PostgresSpec.listeners(db).size == 1 } }
    ensure
      other.close
    end
  end

  postgres_it "connects again and catches up at once when the listening connection drops" do |_, url|
    store = Shomen::Store.new(url, poll_interval: 1.hour)
    DB.open(url) do |db|
      begin
        store.wait_for_append(after: 0_i64, within: 1.millisecond).should be_false
        wait_until(10.seconds) { PostgresSpec.listeners(db).size == 1 }
        first = PostgresSpec.listeners(db)
        insert_unannounced(url, "unannounced")
        woke = Channel(Bool).new(1)
        spawn { woke.send(store.wait_for_append(after: 0_i64, within: 20.seconds)) }
        wait_until { store.@signal.waiting == 1 }
        db.exec("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = current_database() AND application_name LIKE 'shomen-listen-%'")
        receive_within(woke).should be_true
        store.last_appended.should eq(1_i64)
        wait_until(10.seconds) do
          now = PostgresSpec.listeners(db)
          now.size == 1 && now != first
        end
      ensure
        store.close
      end
    end
  end

  postgres_it "closes its listening connection when the store closes" do |_, url|
    other = Shomen::Store.new(url)
    other.wait_for_append(after: 0_i64, within: 1.millisecond)
    DB.open(url) do |db|
      wait_until(10.seconds) { PostgresSpec.listeners(db).size == 1 }
      other.close
      wait_until(10.seconds) { PostgresSpec.listeners(db).empty? }
    end
  end

  postgres_it "closes a listening connection that was still opening when the store closed" do |_, url|
    other = Shomen::Store.new(url)
    other.wait_for_append(after: 0_i64, within: 1.millisecond)
    other.close
    DB.open(url) do |db|
      wait_until(10.seconds) do
        db.scalar("SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND application_name LIKE 'shomen-listen-%'").as(Int64) == 0
      end
    end
  end

  postgres_it "ignores a notification on its channel that carries no id" do |_, url|
    store = Shomen::Store.new(url, poll_interval: 1.hour)
    DB.open(url) do |db|
      begin
        woke = Channel(Bool).new(1)
        spawn { woke.send(store.wait_for_append(after: 0_i64, within: 20.seconds)) }
        wait_until(10.seconds) { PostgresSpec.listeners(db).size == 1 }
        first = PostgresSpec.listeners(db)
        db.exec("SELECT pg_notify($1, $2)", Shomen::PostgresAdapter::CHANNEL, "not an id")
        append_elsewhere(url, "elsewhere", 1)
        receive_within(woke).should be_true
        store.last_appended.should eq(1_i64)
        PostgresSpec.listeners(db).should eq(first)
      ensure
        store.close
      end
    end
  end
```

5 つ目の例は、`stop` の切断が 1 回だけだと失敗する。`wait_for_append` の直後は受信のファイバーがまだ接続していないので、1 回目の切断が空振りし、その後に開いた接続が残る。数えるのは `query` を問わない接続（開いている途中の接続も含む）。

- [ ] **Step 3: テストが失敗するのを確かめる**

Run: `PG= crystal spec spec/shomen/append_watcher_spec.cr`
Expected: 新しい 6 例のうち、通知で起きる例は 20 秒の待ちで `false` になって FAIL（`notifies?` がまだ偽なので受信しない）、`listeners` の例は 10 秒で `the condition did not hold` の FAIL。

- [ ] **Step 4: 受信と切断を書く**

`src/shomen/postgres_adapter.cr` の先頭の `require` に `require "random/secure"` を足す。定数に足す（`NOTIFY` の後）。

```crystal
  LISTENER_PREFIX = "shomen-listen-"
  TERMINATE       = "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name = $1 AND pid <> pg_backend_pid()"
```

ivar の宣言に足す。

```crystal
  @listen_url : String
  @listener_name : String
```

`initialize` の `@key = self.class.key(uri)` の次に、プールの引数を足す前の URL から受信の URL を作る。

```crystal
    @listener_name = LISTENER_PREFIX + Random::Secure.hex(8)
    listen_uri = uri.dup
    listen_params = listen_uri.query_params
    listen_params["application_name"] = @listener_name
    listen_uri.query_params = listen_params
    @listen_url = listen_uri.to_s
```

`def last_id` の後に足す。

```crystal
  def notifies? : Bool
    true
  end

  # On a connection outside the pool, named so interrupt_listen can end it
  # (docs/decisions/20261001-phase7-notify-channel.md). A payload that is
  # not an id comes from outside Shomen and is ignored.
  def listen(on_id : Int64 -> Nil) : Nil
    PG.connect_listen(@listen_url, CHANNEL, blocking: true) do |notification|
      if id = notification.payload.to_i64?
        on_id.call(id)
      end
    end
  end

  def interrupt_listen : Nil
    @db.exec(TERMINATE, @listener_name)
  end
```

- [ ] **Step 5: テストが通るのを確かめる**

Run: `PG= crystal spec spec/shomen/append_watcher_spec.cr spec/shomen/postgres_adapter_spec.cr spec/shomen/store_spec.cr`
Expected: すべて PASS（pending 0）。

- [ ] **Step 6: 全体を確かめる**

Run: `crystal tool format && PG= crystal spec && crystal spec`
Expected: どちらも失敗 0。`PG=` の実行の後、`psql-18 postgres -c "SELECT count(*) FROM pg_stat_activity WHERE application_name LIKE 'shomen-listen-%'"` が `0`（spec が受信の接続を残していない）。

---

### Task 5: プロセスをまたぐ SSE（受入）

**Files:**
- Modify: `spec/support/server_worker.cr:9-10`
- Modify: `src/shomen/append_signal.cr:1-2`
- Modify: `src/shomen/sse.cr:6-8`
- Modify: `src/shomen/route.cr`（`sse` のコメント）
- Test: `spec/shomen/sse_processes_spec.cr`（新規）

**Interfaces:**
- Consumes: Task 3 の `poll_interval:`、Task 4 の受信と `PostgresSpec.listeners`、`append_elsewhere`。既存の `with_server_process`、`send_get`、`read_until`、`remove_database`、`postgres_database_it`、`server_worker` の `/worker/stream`（`NOTES` の行数を `<p id="count">` で送る SSE）
- Produces: `server_worker` の環境変数 `WORKER_POLL_MS`（ミリ秒、既定 5000）

- [ ] **Step 1: 失敗するテストを書く**

`spec/shomen/sse_processes_spec.cr`:

```crystal
require "../spec_helper"
require "socket"

# Opens /worker/stream on a server process over url, appends one event
# through another process, and reads the count the stream sends again.
# Each read waits at most 3 seconds, shorter than the default poll.
private def stream_across_processes(url : String, poll_ms : String, &) : Nil
  Workers.binary("spec/support/store_worker.cr")
  with_server_process(env: {"WORKER_DATABASE_URL" => url, "WORKER_POLL_MS" => poll_ms}) do |server|
    TCPSocket.open("127.0.0.1", server.port) do |socket|
      socket.read_timeout = 3.seconds
      send_get(socket, "/worker/stream")
      read_until(socket, %(data: <p id="count">0</p>))
      yield
      append_elsewhere(url, "from-another-process", 1)
      read_until(socket, %(data: <p id="count">1</p>))
    end
  end
end

describe "an SSE stream" do
  it "receives an event appended through another process on one SQLite file, by polling" do
    path = File.tempname("shomen-sse", ".sqlite3")
    begin
      stream_across_processes("sqlite3://#{path}", "50") { }
    ensure
      remove_database(path)
    end
  end

  postgres_database_it "receives an event appended through another process on one Postgres database, by notification" do |url|
    # The poll is an hour away, so only the notification can wake the stream.
    stream_across_processes(url, "3600000") do
      DB.open(url) { |db| wait_until(20.seconds) { PostgresSpec.listeners(db).size == 1 } }
    end
  end
end
```

SSE は最初のメッセージを書いてから `wait_for_append` に入るので、Postgres の例は、受信の接続が `LISTEN` に入ってから別のプロセスで追記する（ブロックの中の `wait_until`）。SQLite の例は、watcher が始まる前に追記されても、watcher が生成時に最大の `id` を知らせるので待たずに済む。`store_worker` は読み取りの上限に入らないよう、ストリームを開く前にビルドしておく。

- [ ] **Step 2: テストが失敗するのを確かめる**

Run: `PG= crystal spec spec/shomen/sse_processes_spec.cr`
Expected: SQLite の例が `IO::TimeoutError` で FAIL（`server_worker` はまだ `WORKER_POLL_MS` を読まず、間隔は 5 秒のまま。読み取りの上限 3 秒の間に何も届かない）。Postgres の例は、Task 4 で通知が届くようになっているので、すでに PASS する。この例は受入を通知の経路で固定するためのもの。

- [ ] **Step 3: `server_worker` が間隔を読む**

`spec/support/server_worker.cr` の先頭のコメントの最後の文 `WORKER_DATABASE_URL names the store.` を次にする。

```crystal
# seconds. WORKER_DATABASE_URL names the store, and WORKER_POLL_MS its
# poll interval in milliseconds (5000 unless set).
```

`STORE` の行を次にする。

```crystal
  STORE = Shomen::Store.new(ENV["WORKER_DATABASE_URL"], poll_interval: (ENV["WORKER_POLL_MS"]? || "5000").to_i.milliseconds)
```

- [ ] **Step 4: テストが通るのを確かめる**

Run: `PG= crystal spec spec/shomen/sse_processes_spec.cr`
Expected: 2 例とも PASS。受入「An SSE client connected to process A receives an update for an event appended through process B」を SQLite（ポーリング）と Postgres（通知）の両方で満たす。

- [ ] **Step 5: 「このプロセスだけ」のコメントを直す**

`src/shomen/append_signal.cr` の先頭 2 行のコメントを次にする。

```crystal
# Wakes the fibers of this process that wait for an append to one
# database. An append through this process announces itself after its
# commit; Shomen::AppendWatcher announces those of other processes.
```

`src/shomen/sse.cr` のクラスのコメントを次にする。

```crystal
# An event stream a route opens with sse. It sends the fragment's HTML
# first, then again after each append the store learns of, through this
# process or another, that changed it.
```

`src/shomen/route.cr` の `sse` の上のコメントを次にする。

```crystal
  # Opts this GET route into an event stream for an element with
  # data-shomen-sse. fragment renders now and again after each append to
  # store, through this process or another; the stream sends its HTML
  # whenever it changed.
```

- [ ] **Step 6: 全体を確かめる**

Run: `crystal tool format && PG= crystal spec && crystal spec`
Expected: どちらも失敗 0。

---

### Task 6: README、最終確認

**Files:**
- Modify: `README.md:10`、`:121`、`:135`
- Modify: `README.ja.md:10`、`:121`、`:135`

**Interfaces:**
- Consumes: Task 1〜5 のすべて
- Produces: なし

- [ ] **Step 1: README（英語）**

`README.md` の 10 行目の `Phase 7 is specified and not implemented.` を次にする。

```markdown
Phase 7 has begun: an append wakes SSE streams in every process. The rest of phase 7 is specified and not implemented.
```

121 行目の末尾 `Appends in other processes reach it in a later phase` を次にする。

```markdown
Appends through other processes reach it too (phase 7 below)
```

135 行目を次にする（1 段落を、見出し文、箇条、段落の 3 つにする）。

```markdown
Phase 7 adds these so far:

- An append through any process wakes `sse` streams and `wait_for_append` in every process. On Postgres an append sends a notification, and a process that waits listens for it on one connection of its own, outside the pool. Each store also polls for the highest id, every 5 seconds unless `Shomen::Store.new(url, poll_interval:)` says otherwise, so a lost notification only adds delay. SQLite uses polling alone. A process listens and polls only after something waited on the store

The rest of phase 7 is specified and not in the code: consumers that run outside the request, HTTP caching, and reads from replicas.
```

- [ ] **Step 2: README（日本語訳）**

`README.ja.md` の 10 行目の `フェーズ 7 は仕様にあり、実装はまだありません。` を次にする。

```markdown
フェーズ 7 は始まっていて、追記がすべてのプロセスの SSE を起こします。フェーズ 7 の残りは仕様にあり、実装はまだありません。
```

121 行目の末尾 `他のプロセスの追記が届くのは後のフェーズです` を次にする。

```markdown
他のプロセスの追記も届きます（下のフェーズ 7）
```

135 行目を次にする。

```markdown
フェーズ 7 でここまでに足したもの:

- どのプロセスで追記しても、すべてのプロセスの `sse` と `wait_for_append` が起きます。Postgres では追記が通知を送り、待っているプロセスはプールの外の専用の接続 1 本でそれを受けます。どの Store も最大の id をポーリングするので（既定 5 秒、`Shomen::Store.new(url, poll_interval:)` で変えられます）、通知が落ちても遅れるだけです。SQLite はポーリングだけを使います。受信とポーリングは、その Store で何かが待ってから始まります

フェーズ 7 の残りは仕様にあり、コードにはありません。要求の外で動くコンシューマ、HTTP キャッシュ、replica からの読み出しです。
```

- [ ] **Step 3: 最終確認**

Run:

```sh
crystal tool format --check
crystal build src/shomen.cr --error-trace && rm -f shomen shomen.dwarf
SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec
crystal spec
cd examples/hello && shards install && crystal spec && cd ../..
git status --short
```

Expected: format の差分なし。build 成功（警告なし）。`SHOMEN_SPEC_POSTGRES` 付きの spec は失敗 0、pending 0（Chrome が無い環境ではブラウザの例だけ pending）。付けない spec は失敗 0、Postgres の例が pending。`examples/hello` の spec は失敗 0（コードは変えていない）。`git status` に `shomen`、`shomen.dwarf`、`lib/` の生成物が出ない。

- [ ] **Step 4: 作業報告**

CLAUDE.md の「作業報告」に従い、変更ファイル、走らせたコマンド、満たした受入（「An SSE client connected to process A receives an update for an event appended through process B」）、次に残っていること（7b: コンシューマと表に置くプロジェクション）を短く報告する。
