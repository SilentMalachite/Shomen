# Phase 7b Consumers and Projections Kept in Tables Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** フェーズ 7 の 4 本のサブ計画の 2 本目。要求の外で動くコンシューマ（表に置くプロジェクションと反応）と、表に置いたプロジェクションを上限つきで待つ読みを足す。受入「Two processes run the same consumer: each event's database effect is applied once, in `id` order. When one process is killed during a batch, the other continues from the stored checkpoint and loses no event」「A consumer's database writes and its checkpoint commit together. A failure between them leaves neither」と、「When a projection kept in tables does not reach the needed `id` within the limit, the response is 503, not an older state」の前半（待ちと `Shomen::Unavailable` → 503）を満たす。セッションが `id` を覚えて忘れる後半は 7c。

**Architecture:** `abstract class Shomen::Consumer` 1 つで両方を表す。アプリは `name` を決め、`create_tables(connection)`、`write(recorded, connection)`（チェックポイントと同じトランザクションで表に書く）、`react(recorded)`（DB の外への副作用）を上書きする。バッチの手順は DB ごとに違うので `Shomen::StoreAdapter#consume` に置く。Postgres はチェックポイントの行を `FOR UPDATE SKIP LOCKED` でロックしてバッチ全体を 1 トランザクションにし、SQLite は副作用を先に済ませてから `BEGIN IMMEDIATE` の短いトランザクションでチェックポイントを比べて書き換える。どちらも 1 件ごとに `SAVEPOINT` を置き、失敗したイベントの手前までをコミットしてから例外を上げる。`consumers` 表は Store を開くときに作る。`Consumer#start` は 1 本のファイバーでバッチを繰り返し、`wait_for_append`（7a）で起き、失敗は間隔を倍にしながら再試行する。`Consumer#read(id, within:)` はチェックポイントが `id` に届くまで待ち、届かなければ `Shomen::Unavailable` を投げ、サーバはそれを 503 にする（D1〜D3）。

**Tech Stack:** Crystal `>= 1.20.0`（開発機は 1.21.1）、標準ライブラリの `spec`、`log`。shard は増やさない（`db` 0.14.0、`sqlite3` 0.23.0、`pg` 0.30.0）。開発機の Postgres は Homebrew の 18（`postgres://localhost/postgres`、ユーザー `hiro` は superuser）、SQLite は 3.54.0。

**Spec:** `docs/en/00-INSTRUCTION.md` の「9. Error model」（`Shomen::Unavailable`）と「10. Scale out」（コンシューマ、表に置くプロジェクション、待ち）、`docs/en/01-ARCHITECTURE.md` の「Module boundaries」と「Scale out」、`docs/en/02-PHASES.md` のフェーズ 7、`docs/en/03-CONVENTIONS.md`。既存の決定 `docs/decisions/20260929-scale-consumers.md`、`20260929-scale-projection-checkpoint.md`、`20260929-scale-projection-rebuild.md`、`20260929-scale-read-your-writes.md`、`20260929-scale-sqlite-writes.md`、`20260929-scale-event-order.md`、`20260929-phase3-store-api.md`、`20260929-phase6-store-adapters.md`、`20260929-phase6-process-spec.md`、`20260929-phase6-postgres-spec.md`、`20261001-phase7-append-watcher.md`。骨子は `docs/superpowers/plans/2026-10-01-phase7-overview.md`。細部は次の決定ファイルに従う。この計画の Task 1 で足すもの:

- `docs/decisions/20261001-phase7-consumer-api.md`（D1）
- `docs/decisions/20261001-phase7-consumer-batch.md`（D2）
- `docs/decisions/20261001-phase7-consumer-read.md`（D3）

計画前に確かめたこと（スクラッチでの試作、2026-10-01、`db` 0.14.0、`sqlite3` 0.23.0、`pg` 0.30.0、SQLite 3.54.0、Postgres 18）:

- SQLite は `$1`、`$2` を名前付きの引数として扱い、初出の順に 1, 2, … と番号を振る。`crystal-sqlite3` は引数を番号で結ぶので、`$1`、`$2`、… を初出の順に書けば SQLite と Postgres で同じ意味になる。`VALUES ($2, $1)` や `SET checkpoint = $3 WHERE name = $1 AND checkpoint = $2` は SQLite で値がずれる（後者は 0 行更新になった）。同じ `$1` を 2 回書くのは両方で動く
- `INSERT ... ON CONFLICT (name) DO NOTHING` は両方で動く
- `SAVEPOINT shomen_event` / `ROLLBACK TO SAVEPOINT shomen_event` / `RELEASE SAVEPOINT shomen_event` は、SQLite の `BEGIN IMMEDIATE` の中でも Postgres の `BEGIN` の中でも動く。Postgres で文が失敗した後も、`ROLLBACK TO SAVEPOINT` の後なら同じトランザクションで書いてコミットできる
- `UPDATE ... WHERE name = ? AND checkpoint = ?` の `exec(...).rows_affected` は、SQLite でも Postgres でも更新した行の数（1 か 0）を返す
- Postgres の `SELECT ... FOR UPDATE SKIP LOCKED` は、別の接続が行をロックしている間 `query_one?` で `nil` を返す
- Postgres 18 の `idle_in_transaction_session_timeout` の既定は `0`（無効）。`SET LOCAL idle_in_transaction_session_timeout = '60s'` はそのトランザクションだけに効き、`SHOW` は `1min` を返す。`1s` にしてトランザクションの中で 2 秒止まると、次の問い合わせは `DB::ConnectionLost` になる
- SQLite で文が失敗すると（UNIQUE 違反など）、その文は失敗のまま接続のキャッシュに残り、`DB::Database#close` が同じ例外を投げ直す。`sqlite3_next_stmt` で接続のすべての文をたどって `sqlite3_reset` すれば、`close` は成功する。`crystal-sqlite3` は `sqlite3_next_stmt` を束縛していないが、`module Shomen; lib LibSQLite; fun next_stmt = sqlite3_next_stmt(db : LibSQLite3::SQLite3, stmt : Void*) : Void*; end; end` と `@[Link]` なしで宣言すれば使える（`@[Link("sqlite3")]` を付けると ld が重複の警告を出す）
- 抽象メソッドはブロック引数を持てる（`abstract def transaction(& : Int32 -> Bool) : Bool`）。`private abstract class` も書ける

## Global Constraints

- 言語は Crystal 1.20 以上。`shard.yml` の `crystal: ">= 1.20.0"` は変えない。shard を足さない。
- `Shomen::Store` の既存の公開 API は変えない: `Shomen::Store.new(url, poll_interval: 5.seconds)`、`append(stream, expected_version, events)`、`read(after:, limit: 500)`、`last_appended`、`wait_for_append(after:, within:)`、`close`。足すのは `poll_interval`（getter）、`register(name, &)`、`checkpoint(name)`、`consume(name, limit, react, write)`、`using_connection(&)` だけ。
- モジュール境界: Store、アダプタ、Consumer は HTML を知らない。Command、Event、Projection、Consumer、SSE、AppendSignal、AppendWatcher は SQLite も Postgres も名指ししない（`spec/shomen/boundary_spec.cr` が検査する）。Server は Store も Consumer も知らない。
- DB 以外のサービス（Redis、ジョブキューなど）を使わない。失敗を記録する表も作らない。
- セッションが覚える `id`、read-your-writes、replica、`ETag`、断片キャッシュを作らない（7c、7d）。予約実行と遅延実行も作らない。
- 公開 API は `Shomen::` 配下だけ。1 ファイル 1 主要型。ファイル名は機能名。
- `examples/hello` のコードは変えない。既定の Store は `sqlite3://./var/shomen.sqlite3` のまま。
- コードと識別子は英語。この計画と決定ログは日本語。
- ユーザーが指示するまで commit しない。この計画に commit 手順は無い。
- `crystal tool format` を通し、警告を残して完了にしない。
- テストは固定ポートを bind しない。sleep で同期しない。待ちは Channel と子プロセスの出力の行で行い、別プロセスや DB が変える状態だけは `wait_until`（上限つきの繰り返し、sleep なし）か `Consumer#read` の上限つきの待ちで待つ。上限は失敗の検出だけに使う。
- Postgres の spec は `SHOMEN_SPEC_POSTGRES` が無ければ pending。受入の確認は `SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres` を付けて行う。以下、`PG=` と書いたらこの変数を付けて実行する意味とする。
- 検証でリポジトリルートにできる実行ファイル `shomen` と `shomen.dwarf` は `docs/decisions/20260928-build-artifact.md` のとおり削除する。

実行はリポジトリルートで行う。`Shomen::VERSION` は `"0.0.0"` のまま変えない。

## Review Focus

- SQLite で、コンシューマの `write` の SQL が失敗する（UNIQUE 違反など、アプリが書いた文）。失敗した文が接続に残ると、後の `Store#close` が同じ例外を投げ直してプロセスの終了が失敗する。失敗の後にすべての文をリセットし、`close` は成功する。Task 3 の "let the store close after a statement failed on a lent connection" と Task 4 の "lets the store close after a write failed in SQL" で固定する。
- このビルドが知らない型のイベント（新しい版のプロセスが追記した）に当たる。そのイベントの失敗として扱い、手前のイベントはコミットし、飛ばさずに再試行する。Task 4 の "fails on an event it cannot decode, after committing the events before it" で固定する。
- Postgres でバッチの途中のプロセスが止まる（副作用が返らない、ホストが落ちる）。チェックポイントの行のロックが永久に残ると、ほかのプロセスが進めない。バッチのトランザクションは `SET LOCAL idle_in_transaction_session_timeout = '60s'` を持つ。Task 4 の "limits how long a batch's transaction may stay idle" で固定する。
- イベントが溜まっている（デプロイの直後、止まっていたコンシューマの再開）。満杯のバッチの後でポーリングの間隔（既定 5 秒）を待つと、追いつくのがバッチの数 × 5 秒遅れる。満杯なら待たずに次へ進む。Task 6 の "goes on to the next batch at once after a full one" で固定する。
- 追記を待っているコンシューマを `stop` する（シャットダウンのたびに起きる）。`stop` はポーリングの間隔を待たずにすぐ戻り、警告を書かない。Task 6 の "stops at once while it waits for an append" で固定する。

## File Map

| ファイル | 役割 | Task |
|---|---|---|
| `docs/en/00-INSTRUCTION.md`、`docs/00-INSTRUCTION.md` | 仕様 10 のコンシューマの API と読み | 1 |
| `docs/decisions/20261001-phase7-consumer-*.md` | D1、D2、D3 | 1 |
| `docs/superpowers/plans/2026-10-01-phase7-overview.md` | 7b の行にこの計画のファイル名 | 1 |
| `src/shomen/unavailable.cr` | `Shomen::Unavailable`（新規） | 2 |
| `src/shomen/server.cr` | `Shomen::Unavailable` → 503 | 2 |
| `src/shomen.cr` | `unavailable`、`consumer` の require | 2, 4 |
| `src/shomen/store_adapter.cr` | `register`、`checkpoint`、`using_connection`（3）、`consume` と savepoint（4） | 3, 4 |
| `src/shomen/sqlite_adapter.cr` | `consumers` 表、`Shomen::LibSQLite`、`reset_all`、`transaction`（3）、`consume`（4） | 3, 4 |
| `src/shomen/postgres_adapter.cr` | `consumers` 表（3）、`consume`（4） | 3, 4 |
| `src/shomen/store.cr` | `register`、`checkpoint`、`using_connection`（3）、`consume`（4）、`poll_interval`（6） | 3, 4, 6 |
| `src/shomen/consumer.cr` | `Shomen::Consumer`（新規）: バッチ（4）、読み（5）、ループ（6） | 4, 5, 6 |
| `spec/support/routes.cr` | `UnavailableRoutes` | 2 |
| `spec/support/store.cr` | `noted` | 4 |
| `spec/support/consumers.cr` | `SpecConsumers::Notes`（新規） | 4, 6 |
| `spec/support/consumer_routes.cr` | `ConsumerRoutes`（新規） | 5 |
| `spec/support/consumer_worker.cr` | 受入の子プロセス（新規） | 7 |
| `spec/support/consumer_process.cr` | `ConsumerProcess`（新規） | 7 |
| `spec/spec_helper.cr` | 新しい support の require | 4, 5, 7 |
| `spec/shomen/unavailable_spec.cr` | 503（新規） | 2 |
| `spec/shomen/store_consumers_spec.cr` | Store の `consumers`（新規） | 3 |
| `spec/shomen/append_watcher_spec.cr` | spec のアダプタに新しい抽象メソッドの代役 | 3, 4 |
| `spec/shomen/consumer_spec.cr` | 1 バッチ（新規） | 4 |
| `spec/shomen/consumer_read_spec.cr` | 待ちと 503（新規） | 5 |
| `spec/shomen/consumer_run_spec.cr` | `start` と `stop`、再試行（新規） | 6 |
| `spec/shomen/consumer_processes_spec.cr` | 受入（新規） | 7 |
| `spec/shomen/boundary_spec.cr` | `consumer`、`unavailable` を境界の検査に足す | 4 |
| `README.md`、`README.ja.md` | フェーズ 7 でここまで足したもの | 8 |

---

### Task 1: 仕様と決定ファイル

**Files:**
- Modify: `docs/en/00-INSTRUCTION.md:259`、`:261`
- Modify: `docs/00-INSTRUCTION.md:259`、`:261`
- Modify: `docs/superpowers/plans/2026-10-01-phase7-overview.md`（表の 7b の行）
- Create: `docs/decisions/20261001-phase7-consumer-api.md`
- Create: `docs/decisions/20261001-phase7-consumer-batch.md`
- Create: `docs/decisions/20261001-phase7-consumer-read.md`

**Interfaces:**
- Consumes: なし
- Produces: 後続タスクが従う決定 D1〜D3。ここで決めた名前と値（`Shomen::Consumer`、`name`、`create_tables`、`write`、`react`、`checkpoint`、`run_once`、`start`、`stop(within: 5.seconds)`、`read(id = 0, within: 2.seconds, &)`、`BATCH = 100`、`RETRY_FIRST = 1.second`、`RETRY_LIMIT = 1.minute`、`STOP_LIMIT = 5.seconds`、`WAIT = 2.seconds`、`CHECK_FIRST = 10.milliseconds`、`CHECK_LIMIT = 200.milliseconds`、`Shomen::Unavailable`、`Shomen::Server::UNAVAILABLE_DETAIL`、`Shomen::Store#poll_interval`、`#register`、`#checkpoint`、`#consume`、`#using_connection`、`Shomen::StoreAdapter#register`、`#checkpoint`、`#consume`、`#using_connection`、`SAVEPOINT`（`"SAVEPOINT shomen_event"`）、`Shomen::LibSQLite`、`Shomen::PostgresAdapter::BATCH_IDLE_LIMIT`）は Task 2〜7 のコードと一致させる。

- [ ] **Step 1: 仕様 10 を直す（英語）**

`docs/en/00-INSTRUCTION.md` の 259 行目（`- A consumer that fails on an event retries it with a growing delay and does not skip it. Other consumers keep going`）の直後に、次の 1 行を足す。

```markdown
- `Shomen::Consumer` is one type for both. `name` names its checkpoint row. `write(recorded, connection)` writes the consumer's tables in the batch's transaction, `react(recorded)` runs a side effect, and `create_tables(connection)` creates its tables once. The application calls `start` before `Shomen::Server.start`, and `stop` after it returns and before it closes the store. SQL that runs on SQLite and Postgres numbers its parameters `$1`, `$2`, … in the order they first appear (`docs/decisions/20261001-phase7-consumer-api.md`, `docs/decisions/20261001-phase7-consumer-batch.md`)
```

足した後に 262 行目になる `- A projection kept in tables is updated only by its consumer. …` の末尾（`… does not make every later page unavailable`）に、同じ箇条の続きとして次の文を足す（1 行のまま）。

```markdown
. `consumer.read(id, within: 2.seconds) { |connection| … }` waits for the checkpoint, then yields a connection for the read (`docs/decisions/20261001-phase7-consumer-read.md`)
```

元の行は句点なしで終わっているので、足した後の行は `… does not make every later page unavailable. `consumer.read(id, within: 2.seconds) { |connection| … }` waits for … (`docs/decisions/20261001-phase7-consumer-read.md`)` になる。

- [ ] **Step 2: 仕様 10 を直す（日本語訳）**

`docs/00-INSTRUCTION.md` の 259 行目（`- イベントで失敗したコンシューマは、間隔を伸ばしながら再試行し、そのイベントを飛ばさない。ほかのコンシューマは進む`）の直後に、次の 1 行を足す。

```markdown
- `Shomen::Consumer` は両方を表す 1 つの型。`name` がチェックポイントの行を名指す。`write(recorded, connection)` はバッチのトランザクションの中でコンシューマの表に書き、`react(recorded)` は副作用を実行し、`create_tables(connection)` は表を 1 回だけ作る。アプリは `Shomen::Server.start` の前に `start` を呼び、`start` から戻った後、Store を閉じる前に `stop` を呼ぶ。SQLite と Postgres の両方で動かす SQL は、パラメータを `$1`、`$2`、… と初出の順に番号付けする（`docs/decisions/20261001-phase7-consumer-api.md`、`docs/decisions/20261001-phase7-consumer-batch.md`）
```

足した後に 262 行目になる `- 表に置いたプロジェクションを更新するのは、そのコンシューマだけ。…` の末尾（`…使えなくなることはない`）に、次の文を足す（1 行のまま）。

```markdown
。`consumer.read(id, within: 2.seconds) { |connection| … }` はチェックポイントを待ってから、読むための接続を渡す（`docs/decisions/20261001-phase7-consumer-read.md`）
```

- [ ] **Step 3: D1 を書く**

`docs/decisions/20261001-phase7-consumer-api.md` を作る。

```markdown
# 状況

`20260929-scale-consumers.md` は、コンシューマのチェックポイントの置き場、バッチの手順、再試行の約束を決めた。仕様 10 とアーキテクチャ文書は `Shomen::Consumer` を「要求の外でプロジェクションや反応を動かす」とした。型の形、アプリが何を書くか、誰が動かして誰が止めるか、バッチの大きさ、再試行の間隔、失敗の記録先は決めていない。

# 決定

`abstract class Shomen::Consumer` 1 つで、表に置くプロジェクションと反応の両方を表す。

- `initialize(store : Shomen::Store, retry_first : Time::Span = 1.second, retry_limit : Time::Span = 1.minute)`。`retry_first` が正でなければ、`retry_limit` が `retry_first` より小さければ `ArgumentError`
- `abstract def name : String` がチェックポイントの行の名前。空なら、最初に DB に触れるときに `ArgumentError`。表の形を変えるときは新しい名前にする（`20260929-scale-projection-rebuild.md`）
- アプリが上書きするフックは 3 つで、既定は何もしない。`write(recorded, connection : DB::Connection)` はコンシューマの表に書き、新しいチェックポイントと同じトランザクションでコミットされる。`react(recorded)` は DB の外への副作用（メールなど）で、少なくとも 1 回実行される。`create_tables(connection)` はインスタンスごとに 1 回、最初のバッチ、読み、`checkpoint` の前に、`consumers` の行を作るのと同じトランザクションで表を作る
- SQL は `crystal-db` の `DB::Connection` に直接書く。SQLite と Postgres の両方で動かすときは、パラメータを `$1`、`$2`、… と初出の順に番号付けし、型は `BIGINT` と `TEXT` を使う
- `run_once : Int32` は 1 バッチ（`BATCH = 100` 件まで）を実行し、コミットした件数を返す。イベントが無いとき、別のプロセスがチェックポイントを持っているか動かしたときは 0。イベントが失敗したら、その手前までをコミットしてから例外を上げる
- `start` は 1 本のファイバーで `run_once` を繰り返す。満杯のバッチの後はすぐ次を実行する。そうでなければ、バッチの前に読んだ `store.last_appended` より後の追記を、`store.poll_interval` を上限に `wait_for_append` で待つ（`stop` でも起きる）。別のプロセスがバッチの途中で死んだときは、この上限ごとの試みで続きを拾う
- `run_once` が例外を上げたら、`shomen` のログに warn で「`consumer 名前 failed on the event after チェックポイント; retrying in N ms`」と例外を書き、`retry_first` 待つ。続けて失敗するたびに待ちを倍にし、`retry_limit` を上限にする。例外なく終わったバッチで `retry_first` に戻す。失敗を記録する表は作らない
- `stop(within : Time::Span = 5.seconds)` はループに止まるよう知らせ、実行中のバッチが終わるのを上限まで待つ。上限を過ぎたら warn を書いて戻る。追記や再試行を待っている間なら、すぐに止まる。`start` していなければ何もしない
- アプリは `Shomen::Server.start` の前にコンシューマの `start` を呼び、`Shomen::Server.start` から戻った後に `stop` を呼び、それから Store を `close` する。サーバはコンシューマを知らない

# 理由

表に置くプロジェクションも反応も、チェックポイントの後のイベントを順に処理する点は同じで、違うのは DB に書くか外に出すかだけである。フックを 2 つに分ければ、SQLite では副作用を書き込みトランザクションの外で先に実行でき（`20260929-scale-sqlite-writes.md`）、Postgres では両方をバッチのトランザクションの中で実行できる。両方を持つコンシューマも書ける。SQL を Shomen の型で包むと、`crystal-db` の問い合わせの API を写すことになる。初出の順の `$N` は SQLite も Postgres も同じ意味に読むので、包まなくても同じ SQL が両方で動く。

失敗したイベントの手前までをコミットすれば、再試行のたびに手前のイベントの副作用を繰り返さない。待ちを倍にすれば、DB が落ちている間の試みと警告が増え続けない。上限を 1 分にすれば、DB が戻ってから追いつくまでの遅れは最長でも 1 分ほどになる。サーバの外で `start` と `stop` を呼ぶので、サーバは Store を知らないまま、コンシューマだけを動かすプロセスも同じ書き方で作れる。

# 破棄した案

- 反応とプロジェクションを別の型にする（同じループ、チェックポイント、再試行を 2 回書く）
- フックを `apply(recorded, connection)` 1 つにする（SQLite で副作用を書き込みトランザクションの外に出せない）
- `Shomen::Server.start(consumers: [...])` に渡して、サーバに起動と停止を任せる（サーバが Store とコンシューマを知る。コンシューマだけのプロセスを作れない）
- 接続を Shomen の型で包み、`?` と `$N` を書き換える
- 失敗を表に記録する（記録の書き込みも失敗しうる。ログで足りる）
- イベントが失敗したらバッチ全体を巻き戻す（手前のイベントの副作用を再試行のたびに繰り返す）
- 満杯のバッチの後も追記を待つ（溜まったイベントに追いつくのが、バッチごとにポーリングの間隔ぶん遅れる）
```

- [ ] **Step 4: D2 を書く**

`docs/decisions/20261001-phase7-consumer-batch.md` を作る。

```markdown
# 状況

`20260929-scale-consumers.md` は、Postgres ではチェックポイントの行をロックしてバッチ全体を 1 トランザクションにし、SQLite では副作用の後の短いトランザクションでチェックポイントを比べると決めた。手順をどこに置くか、`consumers` 表をいつ作るか、途中のイベントが失敗したときの扱い、ロックがいつ外れるか、アプリの SQL が失敗した後の SQLite の扱いは決めていない。`crystal-sqlite3` は、失敗した文が接続に残ると `close` で同じ例外を投げ直す。

# 決定

`consumers(name TEXT PRIMARY KEY, checkpoint INTEGER NOT NULL)`（Postgres では `BIGINT`）は、Store を開くときに `events` と一緒に `CREATE TABLE IF NOT EXISTS` で作る。

`Shomen::StoreAdapter` に次の 4 つを足す。`Shomen::Store` は同じ名前の公開メソッドで渡し、`consume` では行を `Shomen::Recorded` に戻す。`Shomen::Consumer` はこれらを使う。

- `register(name, &)`: ブロックに接続を渡してコンシューマの表を作らせ、`INSERT INTO consumers (name, checkpoint) VALUES (…, 0) ON CONFLICT (name) DO NOTHING` を実行し、1 つのトランザクションでコミットする。Postgres では追記と同じアドバイザリロックの中で行う。Store は空の名前を `ArgumentError` にする
- `checkpoint(name)`: 行のチェックポイント。行が無ければ 0
- `consume(name, limit, react, write) : Int32`: 1 バッチ。下の手順
- `using_connection(&)`: コンシューマの表を読むための接続を渡す。SQLite ではファイルのロックの中で渡すので、ブロックの中で同じ Store を呼ばない

どちらの DB でも、各イベントを `SAVEPOINT shomen_event` の中で処理し、成功したら `RELEASE SAVEPOINT shomen_event`、失敗したら `ROLLBACK TO SAVEPOINT shomen_event` と `RELEASE SAVEPOINT shomen_event` を実行して止まる。その手前のイベントまでチェックポイントを進めてコミットし、それから例外を上げる。イベントを `Shomen::Recorded` に戻せない（知らない型）のも、そのイベントの失敗として扱う。

Postgres の `consume`:

1. `BEGIN` し、`SET LOCAL idle_in_transaction_session_timeout = '60s'` を実行する
2. `SELECT checkpoint FROM consumers WHERE name = $1 FOR UPDATE SKIP LOCKED`。行が返らなければ、別のプロセスが処理中なのでコミットして 0 を返す
3. チェックポイントより後のイベントを `limit` 件まで読み、1 件ずつ `react` と `write` を実行する
4. 1 件以上成功したら `UPDATE consumers SET checkpoint = $1 WHERE name = $2` を実行し、コミットする

SQLite の `consume`:

1. チェックポイントと、その後のイベント `limit` 件をトランザクションの外で読む
2. 1 件ずつ `react` を実行し、失敗したらそこで止める
3. `react` が成功したイベントが 1 件以上あれば、ファイルのロックを取って `BEGIN IMMEDIATE` し、それらの `write` を実行する
4. 1 件以上書けたら `UPDATE consumers SET checkpoint = ? WHERE name = ? AND checkpoint = ?`（3 つ目は 1 で読んだ値）を実行する。0 行なら、別のプロセスが先にチェックポイントを動かしたので巻き戻し、自分の失敗も捨てて 0 を返す。そうでなければコミットする

SQLite では、`register`、`consume`、`using_connection` の中で例外が起きたら、その接続のすべての文を `sqlite3_next_stmt` でたどって `sqlite3_reset` する。`crystal-sqlite3` は `sqlite3_next_stmt` を束縛していないので、`Shomen::LibSQLite` で宣言する。ライブラリはすでにリンクされているので `@[Link]` は付けない。

# 理由

バッチの手順は「誰がいつロックを持つか」で DB ごとに違うので、追記の手順と同じくアダプタに置く。savepoint を置けば、Postgres で SQL が失敗した後もトランザクションを続けて手前のイベントをコミットでき、SQLite と同じ意味になる。Postgres の `idle_in_transaction_session_timeout` は既定で無効なので、バッチのトランザクションにだけ 60 秒を付ける。副作用が返らなくなったプロセスや、落ちたホストのロックは、これで外れる。Store を開くときに `consumers` 表を作れば、コンシューマを動かさないプロセスでもチェックポイントを読める。コンシューマの表を作るのは `CREATE TABLE IF NOT EXISTS` で、Postgres ではこの文どうしが同時に走ると失敗しうるので、`events` 表を作るときと同じロックを取る。SQLite の文のリセットは、Shomen が書いていない SQL にも効くよう、接続のすべての文に対して行う。

# 破棄した案

- 手順を `Shomen::Consumer` に置き、アダプタは SQL だけを持つ（DB の種類で分岐する処理が Consumer に入る）
- コンシューマが最初に動いたときに `consumers` 表を作る（読むだけのプロセスで表が無い）
- 失敗したらバッチ全体を巻き戻す
- `SELECT … FOR UPDATE`（`SKIP LOCKED` なし）で待つ（待つ間プールの接続を 1 本持ち続ける）
- ロックの上限を設けず、Postgres の設定に任せる（既定ではホストが落ちたときのロックが外れない）
- SQLite で失敗した文を Shomen が書いた文だけリセットする（アプリの SQL が残り、`close` が失敗する）
- `crystal-sqlite3` のクラスを開き直してメソッドを足す（依存の内部に結びつく）
```

- [ ] **Step 5: D3 を書く**

`docs/decisions/20261001-phase7-consumer-read.md` を作る。

```markdown
# 状況

仕様 10 と `20260929-scale-read-your-writes.md` は、ある `id` を見る必要がある要求が、表に置いたプロジェクションのチェックポイントがそこへ届くまで上限つき（既定 2 秒）で待ち、届かなければ `Shomen::Unavailable` を投げ、捕まえられなければ 503 の HTML 文書にすると決めた。待つ API、待ち方、503 の文面は決めていない。見る必要のある `id` をセッションから得る仕組みは 7c で決める。

# 決定

- `Shomen::Consumer#read(id : Int64 = 0, within : Time::Span = 2.seconds, & : DB::Connection -> T) : T` は、チェックポイントが `id` 以上になるまで待ち、`Shomen::Store#using_connection` の接続をブロックに渡して、その値を返す。`id` が 0 以下なら待たず、チェックポイントも読まない
- 待つ間は `consumers` の行を読み直す。間隔は 10 ミリ秒から倍にし、200 ミリ秒を上限にする。`within` を過ぎても届かなければ、`Shomen::Unavailable` を「`名前 did not reach event id within 上限`」で投げる
- `Shomen::Server` は捕まえられなかった `Shomen::Unavailable` を、見出し `Unavailable` と `Shomen::Server::UNAVAILABLE_DETAIL`（`This page cannot show the latest changes yet. Try again in a moment.`）の 503 の HTML 文書にする。例外のメッセージは出さない。`Retry-After` は付けない
- 7b では、見る必要のある `id` はルートが渡す

# 理由

コンシューマは別のプロセスで動いていることがあるので、チェックポイントは DB から読むしかない。待つのは、コンシューマが遅れているときに、見る必要のある `id` を持つ要求だけである。間隔を倍にすれば、2 秒の待ちでも問い合わせは 15 回ほどで済み、同じプロセスのコンシューマがすぐ追いついたときは 10 ミリ秒ほどで返る。チェックポイントは下がらないので、確かめた後に読めば、少なくともその `id` までが表に入っている。読みと接続を 1 つのメソッドにしておけば、7c で replica から読むときも、チェックポイントを確かめた DB と読む DB を同じにできる。

# 破棄した案

- チェックポイントのコミットごとに `NOTIFY` を送り、待つ側が受ける（`LISTEN` の接続とチャネルが増える。待つのはまれ）
- 同じプロセスのコンシューマの知らせだけで待つ（別のプロセスのコンシューマを待てない）
- 待つだけのメソッド（`wait_for(id)`）と読みを分ける（7c で replica を使うと、確かめた DB と読む DB が分かれる）
- 上限なしで待つ
- 上限を過ぎたら古い状態のまま読む
```

- [ ] **Step 6: 骨子の表に計画のファイル名を書く**

`docs/superpowers/plans/2026-10-01-phase7-overview.md` の表の 7b の行の 2 列目 `コンシューマと表に置くプロジェクション` を `コンシューマと表に置くプロジェクション（`2026-10-01-phase7b-consumers.md`）` にする。

- [ ] **Step 7: 確かめる**

Run: `git diff --stat`
Expected: `docs/en/00-INSTRUCTION.md`、`docs/00-INSTRUCTION.md`、`docs/superpowers/plans/2026-10-01-phase7-overview.md` が変わり、`git status --short` に `docs/decisions/20261001-phase7-consumer-api.md`、`-batch.md`、`-read.md` が新規として出る。英語と日本語の 00-INSTRUCTION で、足した行が同じ位置（260 行目、262 行目の末尾）にあること。

---

### Task 2: `Shomen::Unavailable` を 503 にする

**Files:**
- Create: `src/shomen/unavailable.cr`
- Modify: `src/shomen.cr`（`require "./shomen/conflict"` の後）
- Modify: `src/shomen/server.cr`（定数と `respond` の rescue）
- Modify: `spec/support/routes.cr`（末尾に `UnavailableRoutes`）
- Test: `spec/shomen/unavailable_spec.cr`

**Interfaces:**
- Consumes: なし
- Produces: `class Shomen::Unavailable < Exception`、`Shomen::Server::UNAVAILABLE_DETAIL : String`。Task 5 の `Consumer#read` が投げる。

- [ ] **Step 1: 落ちる spec を書く**

`spec/support/routes.cr` の末尾（`ConflictRoutes` の後）に足す。

```crystal
module UnavailableRoutes
  class Lagging < Shomen::Route
    method GET
    path "/phase7/unavailable"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      raise Shomen::Unavailable.new("secret-8 did not reach event 7 within 00:00:02")
    end
  end
end
```

`spec/shomen/unavailable_spec.cr` を作る。

```crystal
require "../spec_helper"

describe "an unhandled Shomen::Unavailable" do
  it "returns a 503 HTML document without the exception message" do
    response = call_with(Shomen::Server.new, "GET", "/phase7/unavailable")
    response.status_code.should eq(503)
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    response.body.should start_with("<!DOCTYPE html>")
    response.body.should contain("<h1>Unavailable</h1>")
    response.body.should contain(Shomen::Server::UNAVAILABLE_DETAIL)
    response.body.should_not contain("secret-8")
  end
end
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `crystal spec spec/shomen/unavailable_spec.cr`
Expected: FAIL（コンパイルエラー `undefined constant Shomen::Unavailable`）

- [ ] **Step 3: 実装する**

`src/shomen/unavailable.cr` を作る（`conflict.cr` と同じ形）。

```crystal
class Shomen::Unavailable < Exception
end
```

`src/shomen.cr` の `require "./shomen/conflict"` の次の行に `require "./shomen/unavailable"` を足す。

`src/shomen/server.cr` の `CONFLICT_DETAIL = …` の次の行に足す。

```crystal
  # docs/decisions/20261001-phase7-consumer-read.md
  UNAVAILABLE_DETAIL = "This page cannot show the latest changes yet. Try again in a moment."
```

同じファイルの `respond` の `rescue ex : Shomen::Conflict` の節の後、`rescue ex`（500）の前に足す。

```crystal
  rescue ex : Shomen::Unavailable
    error_response(503, "Unavailable", UNAVAILABLE_DETAIL)
```

- [ ] **Step 4: 通ることを確かめる**

Run: `crystal spec spec/shomen/unavailable_spec.cr spec/shomen/conflict_spec.cr`
Expected: PASS（2 examples, 0 failures）

- [ ] **Step 5: 全体と書式**

Run: `crystal tool format --check && crystal spec`
Expected: 書式の差分なし。0 failures（Postgres と Chrome の例は pending でよい）

---

### Task 3: `consumers` 表、登録、チェックポイント、接続の貸し出し

**Files:**
- Modify: `src/shomen/store_adapter.cr`
- Modify: `src/shomen/sqlite_adapter.cr`
- Modify: `src/shomen/postgres_adapter.cr`
- Modify: `src/shomen/store.cr`
- Modify: `spec/shomen/append_watcher_spec.cr`（spec のアダプタ 3 つ）
- Test: `spec/shomen/store_consumers_spec.cr`

**Interfaces:**
- Consumes: なし
- Produces:
  - `Shomen::StoreAdapter#register(name : String, & : DB::Connection ->) : Nil`、`#checkpoint(name : String) : Int64`、`#using_connection(& : DB::Connection ->) : Nil`（抽象）
  - `Shomen::Store#register(name : String, & : DB::Connection ->) : Nil`（空の名前は `ArgumentError.new("consumer name must not be empty")`）、`#checkpoint(name : String) : Int64`、`#using_connection(& : DB::Connection -> T) : T forall T`
  - `Shomen::SQLiteAdapter` の private `transaction(& : DB::Connection -> Bool) : Bool`（真でコミット、偽か例外で巻き戻し）と `reset_all(connection)`。Task 4 が使う
  - `Shomen::LibSQLite.next_stmt`

- [ ] **Step 1: 落ちる spec を書く**

`spec/shomen/store_consumers_spec.cr` を作る。

```crystal
require "../spec_helper"

private def notes_table(connection : DB::Connection) : Nil
  connection.exec("CREATE TABLE IF NOT EXISTS spec_notes (event_id BIGINT NOT NULL, text TEXT NOT NULL, max_before BIGINT NOT NULL)")
end

private def count(store : Shomen::Store, table : String) : Int64
  store.using_connection { |connection| connection.scalar("SELECT COUNT(*) FROM #{table}").as(Int64) }
end

describe "the consumers of a store" do
  store_it "start with an empty consumers table" do |store|
    count(store, "consumers").should eq(0_i64)
  end

  store_it "register a consumer at checkpoint 0 with its tables, once" do |store|
    2.times { store.register("spec_notes") { |connection| notes_table(connection) } }
    store.checkpoint("spec_notes").should eq(0_i64)
    count(store, "consumers").should eq(1_i64)
    count(store, "spec_notes").should eq(0_i64)
  end

  store_it "have checkpoint 0 for a name the store does not know" do |store|
    store.checkpoint("nobody").should eq(0_i64)
  end

  store_it "keep neither the tables nor the row when creating the tables fails" do |store|
    expect_raises(Exception, "no tables") do
      store.register("spec_notes") do |connection|
        notes_table(connection)
        raise "no tables"
      end
    end
    count(store, "consumers").should eq(0_i64)
    expect_raises(Exception) { count(store, "spec_notes") }
  end

  store_it "reject an empty name" do |store|
    expect_raises(ArgumentError, "consumer name must not be empty") do
      store.register("") { |_| }
    end
  end

  store_it "let the store close after a statement failed on a lent connection" do |_, url|
    store = Shomen::Store.new(url)
    store.using_connection do |connection|
      connection.exec("CREATE TABLE IF NOT EXISTS spec_unique (a TEXT UNIQUE)")
      connection.exec("INSERT INTO spec_unique (a) VALUES ($1)", "x")
    end
    expect_raises(Exception) do
      store.using_connection { |connection| connection.exec("INSERT INTO spec_unique (a) VALUES ($1)", "x") }
    end
    store.close
  end
end
```

最後の例は、例で開いた Store とは別に同じ URL で Store を開く。`store.close` が例外を投げれば例は失敗する。

- [ ] **Step 2: 落ちることを確かめる**

Run: `crystal spec spec/shomen/store_consumers_spec.cr`
Expected: FAIL（コンパイルエラー `undefined method 'using_connection' for Shomen::Store`）

- [ ] **Step 3: アダプタの抽象メソッドを足す**

`src/shomen/store_adapter.cr` の先頭の `require "./conflict"` の前に `require "db"` を足す。`abstract def close : Nil` の後に足す。

```crystal
  # Creates the row of the consumer called name, at checkpoint 0 unless it
  # has one, in one transaction with the tables the block creates
  # (docs/decisions/20261001-phase7-consumer-batch.md).
  abstract def register(name : String, & : DB::Connection ->) : Nil

  # The checkpoint stored for name; 0 when it has none.
  abstract def checkpoint(name : String) : Int64

  # Lends a connection for reads of a consumer's tables.
  abstract def using_connection(& : DB::Connection ->) : Nil
```

- [ ] **Step 4: SQLite のアダプタ**

`src/shomen/sqlite_adapter.cr` の `require "./store_adapter"` の後に足す。

```crystal
module Shomen
  # crystal-sqlite3 does not bind sqlite3_next_stmt. The library is linked
  # already, so no Link annotation (a second one makes ld warn).
  lib LibSQLite
    fun next_stmt = sqlite3_next_stmt(db : LibSQLite3::SQLite3, stmt : Void*) : Void*
  end
end
```

`SCHEMA` の後に足す。

```crystal
  CONSUMERS_SCHEMA = <<-SQL
    CREATE TABLE IF NOT EXISTS consumers (
      name       TEXT    PRIMARY KEY,
      checkpoint INTEGER NOT NULL
    )
    SQL
```

`SELECT_LAST = …` の後に足す。

```crystal
  REGISTER          = "INSERT INTO consumers (name, checkpoint) VALUES (?, 0) ON CONFLICT (name) DO NOTHING"
  SELECT_CHECKPOINT = "SELECT COALESCE(MAX(checkpoint), 0) FROM consumers WHERE name = ?"
```

`initialize` の表を作る箇所を次にする（`consumers` 表を足し、失敗したらすべての文をリセットする）。

```crystal
    begin
      @db.using_connection do |connection|
        connection.exec(SCHEMA)
        connection.exec(CONSUMERS_SCHEMA)
      rescue ex
        reset_all(connection)
        raise ex
      end
    rescue ex
      @db.close
      raise ex
    end
```

`close` の後に、公開メソッドを足す。

```crystal
  def register(name : String, & : DB::Connection ->) : Nil
    transaction do |connection|
      yield connection
      connection.exec(REGISTER, name)
      true
    end
  end

  def checkpoint(name : String) : Int64
    @lock.synchronize { @db.scalar(SELECT_CHECKPOINT, name).as(Int64) }
  end

  # Inside the file's lock, so close waits for the read.
  def using_connection(& : DB::Connection ->) : Nil
    @lock.synchronize do
      @db.using_connection do |connection|
        yield connection
      rescue ex
        reset_all(connection)
        raise ex
      end
    end
  end
```

`private def reset` の後に、private メソッドを足す。

```crystal
  # BEGIN IMMEDIATE under the file's lock. Commits when the block returns
  # true; rolls back when it returns false or raises.
  private def transaction(& : DB::Connection -> Bool) : Bool
    @lock.synchronize do
      @db.using_connection do |connection|
        begin
          connection.exec("BEGIN IMMEDIATE")
        rescue ex
          reset_all(connection)
          raise ex
        end
        begin
          commit = yield connection
          connection.exec(commit ? "COMMIT" : "ROLLBACK")
          commit
        rescue ex
          begin
            connection.exec("ROLLBACK")
          rescue
          end
          reset_all(connection)
          raise ex
        end
      end
    end
  end

  # Resets every statement of the connection, as a consumer runs SQL that
  # Shomen did not write and a failed one would raise again on close
  # (docs/decisions/20261001-phase7-consumer-batch.md).
  private def reset_all(connection : DB::Connection) : Nil
    handle = connection.as(SQLite3::Connection).to_unsafe
    statement = Shomen::LibSQLite.next_stmt(handle, Pointer(Void).null)
    until statement.null?
      LibSQLite3.reset(statement.as(LibSQLite3::Statement))
      statement = Shomen::LibSQLite.next_stmt(handle, statement)
    end
  end
```

`append` と、その `rollback` / `reset` は変えない。

- [ ] **Step 5: Postgres のアダプタ**

`src/shomen/postgres_adapter.cr` の `SCHEMA` の後に足す。

```crystal
  CONSUMERS_SCHEMA = <<-SQL
    CREATE TABLE IF NOT EXISTS consumers (
      name       TEXT   PRIMARY KEY,
      checkpoint BIGINT NOT NULL
    )
    SQL
```

`SELECT_LAST = …` の後に足す。

```crystal
  REGISTER          = "INSERT INTO consumers (name, checkpoint) VALUES ($1, 0) ON CONFLICT (name) DO NOTHING"
  SELECT_CHECKPOINT = "SELECT COALESCE(MAX(checkpoint), 0) FROM consumers WHERE name = $1"
```

`initialize` の `locked { |connection| connection.exec(SCHEMA) }` を次にする。

```crystal
      locked do |connection|
        connection.exec(SCHEMA)
        connection.exec(CONSUMERS_SCHEMA)
      end
```

`close` の後に足す。

```crystal
  # Under the lock appends take, as CREATE TABLE IF NOT EXISTS can fail
  # when two run at once.
  def register(name : String, & : DB::Connection ->) : Nil
    locked do |connection|
      yield connection
      connection.exec(REGISTER, name)
    end
  end

  def checkpoint(name : String) : Int64
    @db.scalar(SELECT_CHECKPOINT, name).as(Int64)
  end

  def using_connection(& : DB::Connection ->) : Nil
    @db.using_connection { |connection| yield connection }
  end
```

- [ ] **Step 6: Store**

`src/shomen/store.cr` の `close` の前に足す。

```crystal
  # Creates the row of the consumer called name, at checkpoint 0, with the
  # tables the block creates (docs/decisions/20261001-phase7-consumer-batch.md).
  def register(name : String, & : DB::Connection ->) : Nil
    raise ArgumentError.new("consumer name must not be empty") if name.empty?
    @adapter.register(name) { |connection| yield connection }
  end

  # The checkpoint any process committed last for the consumer called name.
  def checkpoint(name : String) : Int64
    @adapter.checkpoint(name)
  end

  # Lends a connection and returns what the block returns. On SQLite the
  # block must not call this store.
  def using_connection(& : DB::Connection -> T) : T forall T
    result = nil
    @adapter.using_connection { |connection| result = yield connection }
    result.as(T)
  end
```

- [ ] **Step 7: spec のアダプタに代役を足す**

`spec/shomen/append_watcher_spec.cr` の `private class FlakyAdapter` の前に足す。

```crystal
# The consumer side of an adapter, which the watcher does not use.
private abstract class WatchedAdapter < Shomen::StoreAdapter
  def register(name : String, & : DB::Connection ->) : Nil
    raise "not used"
  end

  def checkpoint(name : String) : Int64
    raise "not used"
  end

  def using_connection(& : DB::Connection ->) : Nil
    raise "not used"
  end
end
```

同じファイルの `private class FlakyAdapter < Shomen::StoreAdapter`、`private class GatedAdapter < Shomen::StoreAdapter`、`private class BlockingAdapter < Shomen::StoreAdapter` の 3 つを `< WatchedAdapter` に変える。

- [ ] **Step 8: 通ることを確かめる**

Run: `crystal spec spec/shomen/store_consumers_spec.cr spec/shomen/append_watcher_spec.cr spec/shomen/store_spec.cr`
Expected: PASS（Postgres の例は pending）

Run: `PG= crystal spec spec/shomen/store_consumers_spec.cr spec/shomen/postgres_adapter_spec.cr`
Expected: PASS（Postgres の例も走る）

確かめるため、`reset_all(connection)` を一時的に `using_connection` の rescue から外して "let the store close after a statement failed on a lent connection (sqlite3)" が `UNIQUE constraint failed` で落ちることを見てから戻す。

- [ ] **Step 9: 全体と書式**

Run: `crystal tool format --check && crystal spec`
Expected: 書式の差分なし、ld の警告なし、0 failures

---

### Task 4: 1 バッチを実行する `Shomen::Consumer`

**Files:**
- Modify: `src/shomen/store_adapter.cr`
- Modify: `src/shomen/sqlite_adapter.cr`
- Modify: `src/shomen/postgres_adapter.cr`
- Modify: `src/shomen/store.cr`
- Create: `src/shomen/consumer.cr`
- Modify: `src/shomen.cr`（`require "./shomen/projection"` の後）
- Modify: `spec/support/store.cr`（`noted`）
- Create: `spec/support/consumers.cr`
- Modify: `spec/spec_helper.cr`（`require "./support/projections"` の後）
- Modify: `spec/shomen/append_watcher_spec.cr`（`WatchedAdapter#consume`）
- Modify: `spec/shomen/boundary_spec.cr`
- Test: `spec/shomen/consumer_spec.cr`

**Interfaces:**
- Consumes: Task 3 の `register`、`checkpoint`、`using_connection`、SQLite の `transaction` と `reset_all`
- Produces:
  - `Shomen::StoreAdapter#consume(name : String, limit : Int32, react : Proc(Stored, Nil), write : Proc(Stored, DB::Connection, Nil)) : Int32`（抽象）と protected `each_in_savepoint`
  - `Shomen::Store#consume(name : String, limit : Int32, react : Proc(Shomen::Recorded, Nil), write : Proc(Shomen::Recorded, DB::Connection, Nil)) : Int32`
  - `abstract class Shomen::Consumer`: `BATCH = 100`、`initialize(@store : Shomen::Store)`、`abstract def name : String`、`create_tables(connection)`、`write(recorded, connection)`、`react(recorded)`、`checkpoint : Int64`、`run_once : Int32`、private `register`
  - spec: `noted(texts : Array(String)) : Array(Shomen::Event)`、`SpecConsumers::Notes`（`initialize(store, table = "spec_notes")`、`fail_react`、`fail_write`、`failures`、`on_react`、`reacted`、`texts`）

- [ ] **Step 1: spec の支えを書く**

`spec/support/store.cr` の `note` の後に足す。

```crystal
def noted(texts : Array(String)) : Array(Shomen::Event)
  texts.map { |text| SpecEvents::Noted.new(text).as(Shomen::Event) }
end
```

`spec/support/consumers.cr` を作る。

```crystal
module SpecConsumers
  # Keeps one row per Noted event in the table it is named after. Each row
  # holds the highest event id in the table before it, so a spec sees
  # whether the events were applied once and in id order. An event whose
  # text is fail_react or fail_write fails in that step, after its row is
  # written in the case of write, failures times.
  class Notes < Shomen::Consumer
    property fail_react : String? = nil
    property fail_write : String? = nil
    property failures : Int32 = Int32::MAX
    property on_react : Proc(Shomen::Recorded, Nil)? = nil
    getter reacted = [] of String

    def initialize(store : Shomen::Store, @table : String = "spec_notes")
      super(store)
    end

    def name : String
      @table
    end

    def create_tables(connection : DB::Connection) : Nil
      connection.exec("CREATE TABLE IF NOT EXISTS #{@table} (event_id BIGINT NOT NULL, text TEXT NOT NULL, max_before BIGINT NOT NULL)")
    end

    def react(recorded : Shomen::Recorded) : Nil
      @on_react.try &.call(recorded)
      event = recorded.event
      return unless event.is_a?(SpecEvents::Noted)
      fail_once("react", event.text) if event.text == fail_react
      @reacted << event.text
    end

    def write(recorded : Shomen::Recorded, connection : DB::Connection) : Nil
      event = recorded.event
      return unless event.is_a?(SpecEvents::Noted)
      before = connection.scalar("SELECT COALESCE(MAX(event_id), 0) FROM #{@table}").as(Int64)
      connection.exec("INSERT INTO #{@table} (event_id, text, max_before) VALUES ($1, $2, $3)", recorded.id, event.text, before)
      fail_once("write", event.text) if event.text == fail_write
    end

    # The texts in the table in id order, whatever the checkpoint.
    def texts : Array(String)
      @store.using_connection do |connection|
        connection.query_all("SELECT text FROM #{@table} ORDER BY event_id", as: String)
      end
    end

    private def fail_once(step : String, text : String) : Nil
      return unless @failures > 0
      @failures -= 1
      raise "cannot #{step} #{text}"
    end
  end
end
```

`spec/spec_helper.cr` の `require "./support/projections"` の次の行に `require "./support/consumers"` を足す。

- [ ] **Step 2: 落ちる spec を書く**

`spec/shomen/consumer_spec.cr` を作る。

```crystal
require "../spec_helper"

# Writes the same key twice, so its second statement fails in SQL.
private class Duplicate < Shomen::Consumer
  def name : String
    "spec_duplicate"
  end

  def create_tables(connection : DB::Connection) : Nil
    connection.exec("CREATE TABLE IF NOT EXISTS spec_duplicate (a TEXT UNIQUE)")
  end

  def write(recorded : Shomen::Recorded, connection : DB::Connection) : Nil
    2.times { connection.exec("INSERT INTO spec_duplicate (a) VALUES ($1)", "same") }
  end
end

private class Nameless < Shomen::Consumer
  def name : String
    ""
  end
end

# Records the idle limit of the transaction its writes run in.
private class IdleLimit < Shomen::Consumer
  getter shown = [] of String

  def name : String
    "spec_idle_limit"
  end

  def write(recorded : Shomen::Recorded, connection : DB::Connection) : Nil
    @shown << connection.scalar("SHOW idle_in_transaction_session_timeout").as(String)
  end
end

describe Shomen::Consumer do
  store_it "applies the events after its checkpoint and commits the checkpoint with its writes" do |store|
    notes = SpecConsumers::Notes.new(store)
    store.append("s", 0_i64, noted(%w(one two)))
    notes.run_once.should eq(2)
    notes.checkpoint.should eq(2_i64)
    store.append("s", 2_i64, noted(%w(three)))
    notes.run_once.should eq(1)
    notes.run_once.should eq(0)
    notes.texts.should eq(%w(one two three))
    notes.checkpoint.should eq(3_i64)
  end

  store_it "commits at most one batch at a time" do |store|
    notes = SpecConsumers::Notes.new(store)
    store.append("s", 0_i64, noted(Array.new(Shomen::Consumer::BATCH + 1) { |index| "n#{index}" }))
    notes.run_once.should eq(Shomen::Consumer::BATCH)
    notes.checkpoint.should eq(Shomen::Consumer::BATCH.to_i64)
    notes.run_once.should eq(1)
  end

  store_it "leaves out both the writes and the checkpoint of a failing event, and keeps the events before it" do |store|
    notes = SpecConsumers::Notes.new(store)
    notes.fail_write = "two"
    store.append("s", 0_i64, noted(%w(one two three)))
    expect_raises(Exception, "cannot write two") { notes.run_once }
    notes.texts.should eq(%w(one))
    notes.checkpoint.should eq(1_i64)
    notes.fail_write = nil
    notes.run_once.should eq(2)
    notes.texts.should eq(%w(one two three))
  end

  store_it "stops a batch at a failing reaction and does not skip the event" do |store|
    notes = SpecConsumers::Notes.new(store)
    notes.fail_react = "two"
    store.append("s", 0_i64, noted(%w(one two)))
    expect_raises(Exception, "cannot react two") { notes.run_once }
    notes.checkpoint.should eq(1_i64)
    notes.texts.should eq(%w(one))
    notes.fail_react = nil
    notes.run_once.should eq(1)
    notes.reacted.should eq(%w(one two))
  end

  store_it "fails on an event it cannot decode, after committing the events before it" do |store|
    notes = SpecConsumers::Notes.new(store)
    store.append("s", 0_i64, noted(%w(one)))
    store.using_connection do |connection|
      connection.exec(
        "INSERT INTO events (stream, version, type, payload, at) VALUES ($1, $2, $3, $4, $5)",
        "other", 1_i64, "spec.unknown", "{}", "2026-10-01T00:00:00Z",
      )
    end
    store.append("s", 1_i64, noted(%w(three)))
    expect_raises(ArgumentError, %(unknown event type "spec.unknown")) { notes.run_once }
    notes.checkpoint.should eq(1_i64)
    notes.texts.should eq(%w(one))
  end

  store_it "creates its tables and its checkpoint row before the first batch" do |store|
    notes = SpecConsumers::Notes.new(store)
    notes.checkpoint.should eq(0_i64)
    notes.texts.should be_empty
  end

  it "rejects an empty name" do
    with_store do |store|
      expect_raises(ArgumentError, "consumer name must not be empty") { Nameless.new(store).run_once }
    end
  end

  store_it "lets the store close after a write failed in SQL" do |_, url|
    store = Shomen::Store.new(url)
    duplicate = Duplicate.new(store)
    store.append("s", 0_i64, noted(%w(one)))
    expect_raises(Exception) { duplicate.run_once }
    duplicate.checkpoint.should eq(0_i64)
    store.close
  end

  postgres_it "skips a batch while another process holds its checkpoint" do |store, url|
    notes = SpecConsumers::Notes.new(store)
    notes.checkpoint
    store.append("s", 0_i64, noted(%w(one)))
    DB.open(url) do |db|
      db.using_connection do |connection|
        connection.exec("BEGIN")
        connection.query_one("SELECT checkpoint FROM consumers WHERE name = $1 FOR UPDATE", "spec_notes", as: Int64)
        notes.run_once.should eq(0)
        connection.exec("ROLLBACK")
      end
    end
    notes.texts.should be_empty
    notes.run_once.should eq(1)
  end

  postgres_it "limits how long a batch's transaction may stay idle" do |store|
    consumer = IdleLimit.new(store)
    store.append("s", 0_i64, noted(%w(one)))
    consumer.run_once.should eq(1)
    consumer.shown.should eq(["1min"])
  end

  it "rolls back its writes when another process moved the checkpoint during its reactions (sqlite3)" do
    with_store do |store, path|
      notes = SpecConsumers::Notes.new(store)
      notes.checkpoint
      store.append("s", 0_i64, noted(%w(one two)))
      notes.on_react = ->(_recorded : Shomen::Recorded) {
        DB.open("sqlite3://#{path}") { |db| db.exec("UPDATE consumers SET checkpoint = 2 WHERE name = 'spec_notes'") }
        nil
      }
      notes.run_once.should eq(0)
      notes.texts.should be_empty
      notes.checkpoint.should eq(2_i64)
    end
  end
end
```

- [ ] **Step 3: 落ちることを確かめる**

Run: `crystal spec spec/shomen/consumer_spec.cr`
Expected: FAIL（コンパイルエラー `undefined constant Shomen::Consumer`）

- [ ] **Step 4: アダプタの `consume` と savepoint**

`src/shomen/store_adapter.cr` の `alias Stored = …` の後に足す。

```crystal
  # Each event of a consumer's batch runs inside this savepoint
  # (docs/decisions/20261001-phase7-consumer-batch.md).
  SAVEPOINT          = "SAVEPOINT shomen_event"
  ROLLBACK_SAVEPOINT = "ROLLBACK TO SAVEPOINT shomen_event"
  RELEASE_SAVEPOINT  = "RELEASE SAVEPOINT shomen_event"
```

`abstract def using_connection …` の後に足す。

```crystal
  # Runs one batch of the consumer called name on up to limit events after
  # its checkpoint, in id order. react runs an event's side effects and
  # write its writes, which commit with the new checkpoint. Returns how many
  # events it committed: 0 when there were none, or when another process
  # holds or moved the checkpoint. When an event fails, the events before
  # it commit and the error is raised.
  abstract def consume(name : String, limit : Int32, react : Proc(Stored, Nil), write : Proc(Stored, DB::Connection, Nil)) : Int32
```

`protected def check_version` の後に足す。

```crystal
  # Runs the block for each row inside the savepoint, until one raises.
  # Returns how many ran, the id of the last, and the error.
  protected def each_in_savepoint(connection : DB::Connection, rows : Array(Stored), & : Stored ->) : {Int32, Int64, Exception?}
    last = 0_i64
    rows.each_with_index do |row, index|
      connection.exec(SAVEPOINT)
      begin
        yield row
      rescue ex
        connection.exec(ROLLBACK_SAVEPOINT)
        connection.exec(RELEASE_SAVEPOINT)
        return {index, last, ex}
      end
      connection.exec(RELEASE_SAVEPOINT)
      last = row[0]
    end
    {rows.size, last, nil}
  end
```

`src/shomen/sqlite_adapter.cr` の `SELECT_CHECKPOINT = …` の後に足す。

```crystal
  ADVANCE = "UPDATE consumers SET checkpoint = ? WHERE name = ? AND checkpoint = ?"
```

`using_connection` の後に足す。

```crystal
  # Runs the side effects outside any transaction, as SQLite's lock covers
  # the whole file, then commits the writes in a short transaction that
  # moves the checkpoint only from the value it read. When another process
  # moved it first, the writes roll back, and a failure here no longer
  # matters.
  def consume(name : String, limit : Int32, react : Proc(Stored, Nil), write : Proc(Stored, DB::Connection, Nil)) : Int32
    from = checkpoint(name)
    rows = read(from, limit)
    error = nil
    reacted = 0
    rows.each do |row|
      begin
        react.call(row)
      rescue ex
        error = ex
        break
      end
      reacted += 1
    end
    applied = 0
    if reacted > 0
      committed = transaction do |connection|
        applied, last, failure = each_in_savepoint(connection, rows[0, reacted]) { |row| write.call(row, connection) }
        if failure
          reset_all(connection)
          error = failure
        end
        applied == 0 || connection.exec(ADVANCE, last, name, from).rows_affected == 1
      end
      return 0 unless committed
    end
    raise error if error
    applied
  end
```

`src/shomen/postgres_adapter.cr` の `SELECT_CHECKPOINT = …` の後に足す。

```crystal
  CLAIM   = "SELECT checkpoint FROM consumers WHERE name = $1 FOR UPDATE SKIP LOCKED"
  ADVANCE = "UPDATE consumers SET checkpoint = $1 WHERE name = $2"
  # Ends a batch whose process stopped answering, and its lock
  # (docs/decisions/20261001-phase7-consumer-batch.md).
  BATCH_IDLE_LIMIT = "SET LOCAL idle_in_transaction_session_timeout = '60s'"
```

`using_connection` の後に足す。

```crystal
  # Locks the consumer's row for the whole batch, so its events, their side
  # effects and writes, and the new checkpoint are one transaction that no
  # other process runs at the same time. A process that finds the row
  # locked commits nothing and returns 0.
  def consume(name : String, limit : Int32, react : Proc(Stored, Nil), write : Proc(Stored, DB::Connection, Nil)) : Int32
    applied = 0
    error = nil
    @db.using_connection do |connection|
      connection.exec("BEGIN")
      begin
        connection.exec(BATCH_IDLE_LIMIT)
        if from = connection.query_one?(CLAIM, name, as: Int64)
          rows = connection.query_all(SELECT_AFTER, from, limit, as: {Int64, String, Int64, String, String})
          applied, last, error = each_in_savepoint(connection, rows) do |row|
            react.call(row)
            write.call(row, connection)
          end
          connection.exec(ADVANCE, last, name) if applied > 0
        end
        connection.exec("COMMIT")
      rescue ex
        rollback(connection)
        raise ex
      end
    end
    raise error if error
    applied
  end
```

- [ ] **Step 5: Store の `consume`**

`src/shomen/store.cr` の `read` を、行を戻す処理を private メソッドに出して次にする。

```crystal
  def read(after : Int64, limit : Int32 = 500) : Array(Shomen::Recorded)
    @adapter.read(after, limit).map { |row| recorded(row) }
  end
```

`using_connection` の後に足す。

```crystal
  # One batch of the consumer called name
  # (docs/decisions/20261001-phase7-consumer-batch.md). An event that cannot
  # be decoded fails like one whose react or write raises.
  def consume(name : String, limit : Int32, react : Proc(Shomen::Recorded, Nil), write : Proc(Shomen::Recorded, DB::Connection, Nil)) : Int32
    @adapter.consume(
      name, limit,
      ->(row : Shomen::StoreAdapter::Stored) { react.call(recorded(row)) },
      ->(row : Shomen::StoreAdapter::Stored, connection : DB::Connection) { write.call(recorded(row), connection) },
    )
  end
```

`private def watch` の前に足す。

```crystal
  private def recorded(row : Shomen::StoreAdapter::Stored) : Shomen::Recorded
    id, stream, version, type, payload = row
    Shomen::Recorded.new(id, stream, version, Shomen::Event.decode(type, payload))
  end
```

- [ ] **Step 6: `Shomen::Consumer`**

`src/shomen/consumer.cr` を作る。

```crystal
require "db"
require "./store"
require "./recorded"

# A projection kept in tables, or a reaction, run outside the request. It
# applies the events after its checkpoint in batches, and a batch commits
# its writes and the new checkpoint together, so every process may run the
# same consumer (docs/decisions/20261001-phase7-consumer-api.md).
abstract class Shomen::Consumer
  BATCH = 100

  @registered = false
  @register_lock = Mutex.new

  def initialize(@store : Shomen::Store)
  end

  # Names the checkpoint. A projection whose tables change shape takes a
  # new name (docs/decisions/20260929-scale-projection-rebuild.md).
  abstract def name : String

  # Creates the consumer's tables, once, before its first batch or read.
  def create_tables(connection : DB::Connection) : Nil
  end

  # Writes the consumer's tables, in the transaction that moves its
  # checkpoint.
  def write(recorded : Shomen::Recorded, connection : DB::Connection) : Nil
  end

  # A side effect outside the database, such as mail. It runs at least
  # once per event, so it must tolerate a repeat.
  def react(recorded : Shomen::Recorded) : Nil
  end

  # The checkpoint any process committed last.
  def checkpoint : Int64
    register
    @store.checkpoint(name)
  end

  # One batch of up to BATCH events after the checkpoint. Returns how many
  # it committed: 0 when there were none, or when another process holds or
  # moved the checkpoint. When an event fails, the events before it commit
  # and the error is raised.
  def run_once : Int32
    register
    @store.consume(
      name, BATCH,
      ->(recorded : Shomen::Recorded) { react(recorded) },
      ->(recorded : Shomen::Recorded, connection : DB::Connection) { write(recorded, connection) },
    )
  end

  private def register : Nil
    @register_lock.synchronize do
      return if @registered
      @store.register(name) { |connection| create_tables(connection) }
      @registered = true
    end
  end
end
```

`src/shomen.cr` の `require "./shomen/projection"` の次の行に `require "./shomen/consumer"` を足す。

- [ ] **Step 7: spec のアダプタと境界の検査**

`spec/shomen/append_watcher_spec.cr` の `WatchedAdapter` の `using_connection` の後に足す。

```crystal
  def consume(name : String, limit : Int32, react : Proc(Stored, Nil), write : Proc(Stored, DB::Connection, Nil)) : Int32
    raise "not used"
  end
```

`spec/shomen/boundary_spec.cr` の 1 つ目の一覧 `%w(store store_adapter sqlite_adapter postgres_adapter event recorded conflict append_signal append_watcher)` の末尾に `consumer unavailable` を、2 つ目の一覧 `%w(command event rejected recorded projection append_signal append_watcher sse)` の末尾に `consumer` を足す。

- [ ] **Step 8: 通ることを確かめる**

Run: `crystal spec spec/shomen/consumer_spec.cr spec/shomen/boundary_spec.cr spec/shomen/append_watcher_spec.cr spec/shomen/store_spec.cr`
Expected: PASS（Postgres の例は pending）

Run: `PG= crystal spec spec/shomen/consumer_spec.cr`
Expected: PASS（Postgres の 2 つの例を含めて走る）

- [ ] **Step 9: 全体と書式**

Run: `crystal tool format --check && crystal spec`
Expected: 書式の差分なし、ld の警告なし、0 failures

---

### Task 5: 表に置いたプロジェクションを待って読む

**Files:**
- Modify: `src/shomen/consumer.cr`
- Create: `spec/support/consumer_routes.cr`
- Modify: `spec/spec_helper.cr`（`require "./support/sse_routes"` の後）
- Test: `spec/shomen/consumer_read_spec.cr`

**Interfaces:**
- Consumes: Task 2 の `Shomen::Unavailable`、`UNAVAILABLE_DETAIL`。Task 4 の `Shomen::Consumer`、`checkpoint`、`Shomen::Store#using_connection`
- Produces: `Shomen::Consumer#read(id : Int64 = 0_i64, within : Time::Span = WAIT, & : DB::Connection -> T) : T forall T`、`WAIT = 2.seconds`、`CHECK_FIRST = 10.milliseconds`、`CHECK_LIMIT = 200.milliseconds`。Task 6 と 7 の spec が待ちに使う

- [ ] **Step 1: 落ちる spec を書く**

`spec/support/consumer_routes.cr` を作る。

```crystal
# A page that reads SpecConsumers::Notes once its checkpoint reached the id
# in the path, waiting at most 50 ms. A spec sets the consumer.
module ConsumerRoutes
  @@notes : SpecConsumers::Notes? = nil

  def self.notes=(notes : SpecConsumers::Notes?) : Nil
    @@notes = notes
  end

  def self.notes! : SpecConsumers::Notes
    @@notes || raise "set ConsumerRoutes.notes first"
  end

  class NotesView < Shomen::View
    def initialize(@texts : Array(String))
    end

    def to_html : String
      texts = @texts
      html lang: "en" do
        head do
          title "Notes"
        end
        body do
          main do
            ul do
              texts.each { |text| li text }
            end
          end
        end
      end
    end
  end

  class Show < Shomen::Route
    method GET
    path "/phase7/notes/:seen"

    struct Input
      getter seen : Int64

      def initialize(@seen : Int64)
      end
    end

    def call(input : Input) : Shomen::Response
      texts = ConsumerRoutes.notes!.read(input.seen, within: 50.milliseconds) do |connection|
        connection.query_all("SELECT text FROM spec_notes ORDER BY event_id", as: String)
      end
      render NotesView.new(texts)
    end
  end
end
```

`spec/spec_helper.cr` の `require "./support/sse_routes"` の次の行に `require "./support/consumer_routes"` を足す。

`spec/shomen/consumer_read_spec.cr` を作る。

```crystal
require "../spec_helper"

describe "Shomen::Consumer#read" do
  store_it "yields at once for id 0" do |store|
    notes = SpecConsumers::Notes.new(store)
    store.append("s", 0_i64, note("one"))
    notes.read { |connection| connection.scalar("SELECT COUNT(*) FROM spec_notes").as(Int64) }.should eq(0_i64)
  end

  store_it "yields once the checkpoint reached the id" do |store|
    notes = SpecConsumers::Notes.new(store)
    store.append("s", 0_i64, note("one"))
    spawn { notes.run_once }
    texts = notes.read(1_i64, within: 5.seconds) do |connection|
      connection.query_all("SELECT text FROM spec_notes", as: String)
    end
    texts.should eq(%w(one))
  end

  store_it "raises Shomen::Unavailable when the checkpoint does not reach the id within the limit" do |store|
    notes = SpecConsumers::Notes.new(store)
    store.append("s", 0_i64, note("one"))
    expect_raises(Shomen::Unavailable, /\Aspec_notes did not reach event 1 within /) do
      notes.read(1_i64, within: 50.milliseconds) { |_| }
    end
  end
end

describe "a page that reads a projection kept in tables" do
  store_it "is a 503 document while the projection lags, and a 200 once it reached the id" do |store|
    notes = SpecConsumers::Notes.new(store)
    ConsumerRoutes.notes = notes
    begin
      store.append("s", 0_i64, note("one"))
      response = call_with(Shomen::Server.new, "GET", "/phase7/notes/1")
      response.status_code.should eq(503)
      response.body.should contain("<h1>Unavailable</h1>")
      response.body.should_not contain("<li>")
      notes.run_once.should eq(1)
      response = call_with(Shomen::Server.new, "GET", "/phase7/notes/1")
      response.status_code.should eq(200)
      response.body.should contain("<li>one</li>")
    ensure
      ConsumerRoutes.notes = nil
    end
  end
end
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `crystal spec spec/shomen/consumer_read_spec.cr`
Expected: FAIL（コンパイルエラー `undefined method 'read' for SpecConsumers::Notes`）

- [ ] **Step 3: 実装する**

`src/shomen/consumer.cr` の `require "./recorded"` の次の行に `require "./unavailable"` を足す。`BATCH = 100` の後に足す。

```crystal
  # docs/decisions/20261001-phase7-consumer-read.md
  WAIT        = 2.seconds
  CHECK_FIRST = 10.milliseconds
  CHECK_LIMIT = 200.milliseconds
```

`run_once` の後に足す。

```crystal
  # Yields a connection once the checkpoint reached id, and returns what
  # the block returns. Raises Shomen::Unavailable, rather than show an older
  # state, when within passes first. Registers first, so the consumer's
  # tables exist even for id 0, which neither waits nor reads the
  # checkpoint.
  def read(id : Int64 = 0_i64, within : Time::Span = WAIT, & : DB::Connection -> T) : T forall T
    register
    await(id, within)
    @store.using_connection { |connection| yield connection }
  end
```

`private def register` の後に足す。

```crystal
  # Reads the checkpoint again after CHECK_FIRST, then twice as long each
  # time, at most CHECK_LIMIT, as the consumer may run in another process.
  private def await(id : Int64, within : Time::Span) : Nil
    return if id <= 0
    deadline = Time.instant + within
    check = CHECK_FIRST
    until checkpoint >= id
      left = deadline - Time.instant
      raise Shomen::Unavailable.new("#{name} did not reach event #{id} within #{within}") unless left.positive?
      sleep({check, left}.min)
      check = {check * 2, CHECK_LIMIT}.min
    end
  end
```

- [ ] **Step 4: 通ることを確かめる**

Run: `crystal spec spec/shomen/consumer_read_spec.cr spec/shomen/unavailable_spec.cr`
Expected: PASS

Run: `PG= crystal spec spec/shomen/consumer_read_spec.cr`
Expected: PASS

- [ ] **Step 5: 全体と書式**

Run: `crystal tool format --check && crystal spec`
Expected: 書式の差分なし、0 failures

---

### Task 6: `start` と `stop`、追記で起き、失敗を再試行する

**Files:**
- Modify: `src/shomen/store.cr`（`poll_interval`）
- Modify: `src/shomen/consumer.cr`
- Modify: `spec/support/consumers.cr`（`Notes#initialize`）
- Test: `spec/shomen/consumer_run_spec.cr`

**Interfaces:**
- Consumes: Task 4 の `run_once`、Task 5 の `read`。7a の `Shomen::Store#last_appended`、`#wait_for_append`
- Produces:
  - `Shomen::Store#poll_interval : Time::Span`
  - `Shomen::Consumer#initialize(@store : Shomen::Store, @retry_first : Time::Span = RETRY_FIRST, @retry_limit : Time::Span = RETRY_LIMIT)`、`RETRY_FIRST = 1.second`、`RETRY_LIMIT = 1.minute`、`STOP_LIMIT = 5.seconds`、`start : Nil`、`stop(within : Time::Span = STOP_LIMIT) : Nil`
  - `SpecConsumers::Notes#initialize(store, table = "spec_notes", retry_first = 10.milliseconds, retry_limit = 1.second)`。Task 7 の子プロセスが使う

- [ ] **Step 1: 落ちる spec を書く**

`spec/support/consumers.cr` の `Notes#initialize` を次にする。

```crystal
    def initialize(store : Shomen::Store, @table : String = "spec_notes", retry_first : Time::Span = 10.milliseconds, retry_limit : Time::Span = 1.second)
      super(store, retry_first, retry_limit)
    end
```

`spec/shomen/consumer_run_spec.cr` を作る。

```crystal
require "../spec_helper"

describe "a started Shomen::Consumer" do
  store_it "applies each append without being asked, until stop" do |store|
    notes = SpecConsumers::Notes.new(store)
    notes.start
    begin
      store.append("s", 0_i64, note("one"))
      notes.read(1_i64, within: 5.seconds) { |_| }
      store.append("s", 1_i64, note("two"))
      notes.read(2_i64, within: 5.seconds) { |_| }
      notes.texts.should eq(%w(one two))
    ensure
      notes.stop
    end
  end

  store_it "goes on to the next batch at once after a full one" do |store|
    count = Shomen::Consumer::BATCH + 1
    store.append("s", 0_i64, noted(Array.new(count) { |index| "n#{index}" }))
    notes = SpecConsumers::Notes.new(store)
    notes.start
    begin
      # The store polls every 5 seconds, so only a batch that follows at
      # once arrives within 2.
      notes.read(count.to_i64, within: 2.seconds) { |_| }
    ensure
      notes.stop
    end
  end

  store_it "retries a failing event with a growing delay, logs each failure, and does not skip it" do |store|
    notes = SpecConsumers::Notes.new(store)
    notes.fail_react = "one"
    notes.failures = 2
    store.append("s", 0_i64, noted(%w(one two)))
    Log.capture("shomen") do |logs|
      notes.start
      begin
        notes.read(2_i64, within: 5.seconds) { |_| }
      ensure
        notes.stop
      end
      logs.check(:warn, /\Aconsumer spec_notes failed on the event after 0; retrying in 10 ms\z/)
      logs.next(:warn, /\Aconsumer spec_notes failed on the event after 0; retrying in 20 ms\z/)
    end
    notes.texts.should eq(%w(one two))
  end

  store_it "keeps other consumers going while one fails" do |store|
    failing = SpecConsumers::Notes.new(store, "spec_failing")
    failing.fail_react = "one"
    other = SpecConsumers::Notes.new(store, "spec_other")
    store.append("s", 0_i64, note("one"))
    failing.start
    other.start
    begin
      other.read(1_i64, within: 5.seconds) { |_| }
      failing.checkpoint.should eq(0_i64)
    ensure
      failing.stop
      other.stop
    end
  end

  store_it "stops at once while it waits for an append" do |store|
    notes = SpecConsumers::Notes.new(store)
    notes.start
    store.append("s", 0_i64, note("one"))
    notes.read(1_i64, within: 5.seconds) { |_| }
    Log.capture("shomen") do |logs|
      notes.stop(within: 1.second)
      logs.empty
    end
  end

  it "rejects a retry_first that is not positive, and a retry_limit below it" do
    with_store do |store|
      expect_raises(ArgumentError, "retry_first must be positive") do
        SpecConsumers::Notes.new(store, retry_first: 0.seconds)
      end
      expect_raises(ArgumentError, "retry_limit must not be less than retry_first") do
        SpecConsumers::Notes.new(store, retry_first: 2.seconds, retry_limit: 1.second)
      end
    end
  end
end
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `crystal spec spec/shomen/consumer_run_spec.cr`
Expected: FAIL（コンパイルエラー。`super(store, retry_first, retry_limit)` に合う `initialize` が無い、または `undefined method 'start'`）

- [ ] **Step 3: Store の `poll_interval`**

`src/shomen/store.cr` の `@closed = false` の後に足す。

```crystal
  # How often a watcher this store starts polls; a consumer on this store
  # tries again at least this often.
  getter poll_interval : Time::Span
```

- [ ] **Step 4: ループを実装する**

`src/shomen/consumer.cr` の先頭に `require "log"` を足す。`BATCH = 100` の後に足す。

```crystal
  RETRY_FIRST = 1.second
  RETRY_LIMIT = 1.minute
  STOP_LIMIT  = 5.seconds
```

`CHECK_LIMIT = …` の後に足す。

```crystal
  Log = ::Log.for("shomen")
```

`@register_lock = Mutex.new` の後に足す。

```crystal
  @started = Atomic(Bool).new(false)
  @stopping = Atomic(Bool).new(false)
  @stop = Channel(Nil).new
  # Closed when the loop ends, which wakes every receiver.
  @stopped = Channel(Nil).new
```

`initialize` を次にする。

```crystal
  def initialize(@store : Shomen::Store, @retry_first : Time::Span = RETRY_FIRST, @retry_limit : Time::Span = RETRY_LIMIT)
    raise ArgumentError.new("retry_first must be positive") unless @retry_first.positive?
    raise ArgumentError.new("retry_limit must not be less than retry_first") if @retry_limit < @retry_first
  end
```

`read` の後に足す。

```crystal
  # Runs batches in a fiber of its own until stop.
  def start : Nil
    return if @started.swap(true)
    spawn(name: "shomen consumer #{name}") { run }
  end

  # Tells the loop to stop and waits, up to within, for the batch in
  # progress to end. A loop that waits for an append or a retry stops at
  # once.
  def stop(within : Time::Span = STOP_LIMIT) : Nil
    return unless @started.get
    return if @stopping.swap(true)
    @stop.close
    select
    when @stopped.receive?
    when timeout(within)
      Log.warn { "consumer #{name} did not stop within #{within}" }
    end
  end
```

`private def await` の後に足す。

```crystal
  # After a full batch the next runs at once; after any other, the loop
  # waits for an append after the last id it knew before that batch, or for
  # the store's poll interval, so it picks up a batch another process left
  # when it died.
  private def run : Nil
    delay = @retry_first
    until @stopping.get
      seen = @store.last_appended
      applied = 0
      begin
        applied = run_once
      rescue ex
        after = (@store.checkpoint(name) rescue nil)
        Log.warn(exception: ex) { "consumer #{name} failed on the event after #{after || "its checkpoint"}; retrying in #{delay.total_milliseconds.to_i} ms" }
        break if stopped_within?(delay)
        delay = {delay * 2, @retry_limit}.min
        next
      end
      delay = @retry_first
      next if applied == BATCH
      break if idle(seen)
    end
  ensure
    @stopped.close
  end

  # Waits for an append after seen, at most the store's poll interval. The
  # wait runs in a fiber of its own so stop ends this one at once; that
  # fiber ends by itself within the interval. True when stopped.
  private def idle(seen : Int64) : Bool
    woke = Channel(Nil).new(1)
    store = @store
    spawn(name: "shomen consumer wait") do
      store.wait_for_append(after: seen, within: store.poll_interval)
      woke.send(nil)
    end
    select
    when woke.receive
      false
    when @stop.receive?
      true
    end
  end

  private def stopped_within?(span : Time::Span) : Bool
    select
    when @stop.receive?
      true
    when timeout(span)
      false
    end
  end
```

- [ ] **Step 5: 通ることを確かめる**

Run: `crystal spec spec/shomen/consumer_run_spec.cr spec/shomen/consumer_spec.cr spec/shomen/consumer_read_spec.cr`
Expected: PASS

Run: `PG= crystal spec spec/shomen/consumer_run_spec.cr`
Expected: PASS

確かめるため、`run` の `next if applied == BATCH` を一時的に消して "goes on to the next batch at once after a full one" が `Shomen::Unavailable` で落ちることを見てから戻す。

- [ ] **Step 6: 全体と書式**

Run: `crystal tool format --check && crystal spec`
Expected: 書式の差分なし、0 failures

---

### Task 7: 2 つのプロセスで同じコンシューマ（受入）

**Files:**
- Create: `spec/support/consumer_worker.cr`
- Create: `spec/support/consumer_process.cr`
- Modify: `spec/spec_helper.cr`（`require "./support/server_process"` の後）
- Test: `spec/shomen/consumer_processes_spec.cr`

**Interfaces:**
- Consumes: Task 6 の `SpecConsumers::Notes`（`retry_first:`、`retry_limit:`）、`start`、`stop`。`Workers.binary`、`wait_until`、`postgres_database_it`、`remove_database`
- Produces: `ConsumerProcess`（`new(url, mode)`、`expect(line, within)`、`finish(within)`、`kill`）と `with_consumer_process(url, mode, &)`

- [ ] **Step 1: 子プロセスを書く**

`spec/support/consumer_worker.cr` を作る。

```crystal
# Runs SpecConsumers::Notes on the store at the URL until a line on
# standard input, then stops it and closes the store
# (docs/decisions/20260929-phase6-process-spec.md). Arguments: the store
# URL, and "run" or "stall". With "stall", the consumer writes "stalled"
# after the row of the event "stall" and never ends that batch.
require "../../src/shomen"
require "./events"
require "./consumers"

class StallingNotes < SpecConsumers::Notes
  def write(recorded : Shomen::Recorded, connection : DB::Connection) : Nil
    super
    event = recorded.event
    if event.is_a?(SpecEvents::Noted) && event.text == "stall"
      STDOUT.puts "stalled"
      STDOUT.flush
      Channel(Nil).new.receive
    end
  end
end

url, mode = ARGV
store = Shomen::Store.new(url, poll_interval: 50.milliseconds)
consumer = mode == "stall" ? StallingNotes.new(store) : SpecConsumers::Notes.new(store)
consumer.start
STDOUT.puts "started"
STDOUT.flush
STDIN.gets
consumer.stop
store.close
```

`spec/support/consumer_process.cr` を作る。

```crystal
# A spec/support/consumer_worker.cr process. Its standard output goes to a
# channel line by line, so a spec waits for a line instead of sleeping
# (docs/decisions/20260929-phase6-process-spec.md).
class ConsumerProcess
  SOURCE = "spec/support/consumer_worker.cr"

  @status : Process::Status? = nil

  def initialize(url : String, mode : String)
    @lines = Channel(String?).new(64)
    @process = Process.new(Workers.binary(SOURCE), [url, mode], input: :pipe, output: :pipe, error: :inherit)
    lines = @lines
    output = @process.output
    spawn do
      while line = output.gets
        lines.send(line)
      end
    rescue IO::Error
    ensure
      lines.send(nil)
    end
    expect("started")
  end

  def expect(line : String, within : Time::Span = 20.seconds) : Nil
    deadline = Time.instant + within
    loop do
      select
      when received = @lines.receive
        raise "consumer_worker ended before #{line.inspect}" unless received
        return if received == line
      when timeout(deadline - Time.instant)
        raise "consumer_worker did not write #{line.inspect} within #{within}"
      end
    end
  end

  # Asks the worker to stop its consumer and close its store, and waits
  # for it to exit successfully.
  def finish(within : Time::Span = 10.seconds) : Nil
    @process.input.puts("stop")
    @process.input.flush
    status = wait(within)
    raise "consumer_worker exited with #{status.exit_code}" unless status.success?
  end

  def kill : Nil
    return if @status
    @process.signal(Signal::KILL) unless @process.terminated?
    wait(10.seconds)
  end

  private def wait(within : Time::Span) : Process::Status
    if status = @status
      return status
    end
    done = Channel(Process::Status).new(1)
    process = @process
    spawn { done.send(process.wait) }
    select
    when status = done.receive
      @status = status
    when timeout(within)
      raise "consumer_worker did not exit within #{within}"
    end
  end
end

def with_consumer_process(url : String, mode : String = "run", & : ConsumerProcess ->) : Nil
  process = ConsumerProcess.new(url, mode)
  begin
    yield process
  ensure
    process.kill
  end
end
```

`spec/spec_helper.cr` の `require "./support/server_process"` の次の行に `require "./support/consumer_process"` を足す。

- [ ] **Step 2: 受入の spec を書く**

`spec/shomen/consumer_processes_spec.cr` を作る。

```crystal
require "../spec_helper"

private def wait_for_checkpoint(url : String, id : Int64) : Nil
  DB.open(url) do |db|
    wait_until(30.seconds) do
      db.query_one?("SELECT checkpoint FROM consumers WHERE name = 'spec_notes'", as: Int64) == id
    end
  end
end

# Each event of 1 to count has exactly one row, and each row was written
# when the rows of every earlier event were in the table and no later one.
private def check_applied(url : String, count : Int32) : Nil
  DB.open(url) do |db|
    rows = db.query_all("SELECT event_id, max_before FROM spec_notes ORDER BY event_id", as: {Int64, Int64})
    rows.map(&.[0]).should eq((1_i64..count.to_i64).to_a)
    rows.map(&.[1]).should eq((0_i64...count.to_i64).to_a)
  end
end

private def texts(prefix : String, count : Int32) : Array(Shomen::Event)
  noted(Array.new(count) { |index| "#{prefix} #{index}" })
end

private def two_processes(url : String) : Nil
  Workers.binary(ConsumerProcess::SOURCE)
  store = Shomen::Store.new(url)
  begin
    store.append("before", 0_i64, texts("before", 250))
    with_consumer_process(url) do |first|
      with_consumer_process(url) do |second|
        store.append("after", 0_i64, texts("after", 50))
        wait_for_checkpoint(url, 300_i64)
        first.finish
        second.finish
      end
    end
    check_applied(url, 300)
  ensure
    store.close
  end
end

private def killed_during_batch(url : String) : Nil
  Workers.binary(ConsumerProcess::SOURCE)
  store = Shomen::Store.new(url)
  begin
    store.append("notes", 0_i64, noted((1..10).map { |index| index == 5 ? "stall" : "note #{index}" }))
    with_consumer_process(url, "stall") do |stalling|
      stalling.expect("stalled")
      with_consumer_process(url) do |other|
        stalling.kill
        wait_for_checkpoint(url, 10_i64)
        other.finish
      end
    end
    check_applied(url, 10)
  ensure
    store.close
  end
end

private def with_sqlite_url(& : String ->) : Nil
  path = File.tempname("shomen-consumers", ".sqlite3")
  begin
    yield "sqlite3://#{path}"
  ensure
    remove_database(path)
  end
end

describe "one consumer in two processes" do
  it "applies each event's writes once, in id order, on one SQLite file" do
    with_sqlite_url { |url| two_processes(url) }
  end

  postgres_database_it "applies each event's writes once, in id order, on one Postgres database" do |url|
    two_processes(url)
  end

  it "continues from the stored checkpoint after the other process is killed during a batch, on SQLite" do
    with_sqlite_url { |url| killed_during_batch(url) }
  end

  postgres_database_it "continues from the stored checkpoint after the other process is killed during a batch, on Postgres" do |url|
    killed_during_batch(url)
  end
end
```

"killed during a batch" では、止まったプロセスはイベント 1〜5 の行を書いた後、コミットの前に止まっている。殺された後に行が重複せず、10 件がちょうど 1 回ずつ順に入っていれば、書き込みとチェックポイントが一緒に巻き戻ったことになる（受入の 2 つ目）。SQLite では、もう一方のプロセスは止まったプロセスの書き込みロックをビジータイムアウト（5 秒）の間待ち、殺された時点で続ける。Postgres では、もう一方は行のロックを `SKIP LOCKED` で飛ばし、ポーリングの間隔（50 ミリ秒）ごとに試し直す。

- [ ] **Step 3: 走らせる**

Run: `crystal spec spec/shomen/consumer_processes_spec.cr`
Expected: PASS（SQLite の 2 例。Postgres の 2 例は pending）

Run: `PG= crystal spec spec/shomen/consumer_processes_spec.cr`
Expected: PASS（4 examples, 0 failures）

この spec は Task 4〜6 の実装を確かめるもので、ここで新しい本体のコードは書かない。落ちたら `superpowers:systematic-debugging` で原因を探し、本体を直した後に Task 4〜6 の spec も通ることを確かめる。

- [ ] **Step 4: 全体と書式**

Run: `crystal tool format --check && crystal spec`
Expected: 書式の差分なし、0 failures

---

### Task 8: README、最終確認

**Files:**
- Modify: `README.md:10`、`:135-139`
- Modify: `README.ja.md:10`、`:135-139`

**Interfaces:**
- Consumes: Task 1〜7 の公開 API
- Produces: なし

- [ ] **Step 1: README（英語）**

`README.md` の 10 行目の `Phase 7 has begun: an append wakes SSE streams in every process.` を `Phase 7 has begun: an append wakes SSE streams in every process, and consumers run projections and reactions outside the request.` にする。

137 行目（`- An append through any process wakes …`）の後に、次の 2 行を足す。

```markdown
- `Shomen::Consumer`: a projection kept in tables, or a reaction, run outside the request. Give it a `name`, and override `create_tables(connection)` and `write(recorded, connection)` for the rows it keeps, and `react(recorded)` for a side effect such as mail. Call `start` before `Shomen::Server.start`, and `stop` after it returns, before you close the store. Every process may run the same consumer: a batch commits its writes and the checkpoint together, Postgres locks the checkpoint row and SQLite compares it, so each event's writes apply once, in id order. A side effect runs at least once. A failing event is retried after 1 second, then twice as long each time up to 1 minute, and never skipped. SQL numbered `$1`, `$2`, … in the order the parameters first appear runs on SQLite and Postgres
- `consumer.read(id, within: 2.seconds) { |connection| … }` waits until the consumer's checkpoint reaches `id`, then lends a connection for the read. Past the limit it raises `Shomen::Unavailable`, which the server answers with a 503 HTML document
```

139 行目を次にする。

```markdown
The rest of phase 7 is specified and not in the code: a session that remembers its last append, HTTP caching, and reads from replicas.
```

- [ ] **Step 2: README（日本語訳）**

`README.ja.md` の 10 行目の `フェーズ 7 は始まっていて、追記がすべてのプロセスの SSE を起こします。` を `フェーズ 7 は始まっていて、追記がすべてのプロセスの SSE を起こし、コンシューマが要求の外でプロジェクションと反応を動かします。` にする。

137 行目の後に、次の 2 行を足す。

```markdown
- `Shomen::Consumer`: 要求の外で動く、表に置くプロジェクションか反応です。`name` を決め、持つ行のために `create_tables(connection)` と `write(recorded, connection)` を、メールなどの副作用のために `react(recorded)` を上書きします。`Shomen::Server.start` の前に `start` を呼び、戻った後、Store を閉じる前に `stop` を呼びます。同じコンシューマをどのプロセスで動かしても構いません。バッチは書き込みとチェックポイントを一緒にコミットし、Postgres はチェックポイントの行をロックし、SQLite は比べるので、各イベントの書き込みは `id` 順に 1 回だけ入ります。副作用は少なくとも 1 回実行されます。失敗したイベントは 1 秒後に、その後は倍ずつ、最長 1 分の間隔で再試行され、飛ばされません。パラメータを初出の順に `$1`、`$2`、… と番号付けした SQL は、SQLite と Postgres の両方で動きます
- `consumer.read(id, within: 2.seconds) { |connection| … }` は、コンシューマのチェックポイントが `id` に届くまで待ってから、読むための接続を渡します。上限を過ぎると `Shomen::Unavailable` を投げ、サーバはそれを 503 の HTML 文書にします
```

139 行目を次にする。

```markdown
フェーズ 7 の残りは仕様にあり、コードにはありません。最後の追記を覚えるセッション、HTTP キャッシュ、replica からの読み出しです。
```

- [ ] **Step 3: 最終確認**

Run: `crystal tool format --check`
Expected: 差分なし

Run: `crystal spec`
Expected: 0 failures（Postgres と Chrome の例は pending）

Run: `PG= crystal spec`
Expected: 0 failures（Postgres の例も走る。Chrome が無ければその例だけ pending）

Run: `crystal build src/shomen.cr --error-trace && rm -f shomen shomen.dwarf`
Expected: 警告なしでビルドでき、生成物を消す

Run: `cd examples/hello && shards install && crystal spec`
Expected: 0 failures（`examples/hello` のコードは変えていない）

Run: `git status --short`
Expected: この計画の File Map にあるファイルだけが変わり、`shomen`、`shomen.dwarf`、`lib/` の変更が無い

- [ ] **Step 4: 受入の対応を確かめる**

次の対応を、走らせた spec の名前で確かめる。

| フェーズ 7 の受入 | spec |
|---|---|
| 2 プロセスで同じコンシューマ: 各イベントの DB への効果は 1 回、`id` 順 | `consumer_processes_spec.cr` の "applies each event's writes once, in id order"（SQLite、Postgres） |
| 1 つがバッチの途中で殺されても、もう一方が保存したチェックポイントから続け、イベントを失わない | 同 "continues from the stored checkpoint after the other process is killed during a batch"（SQLite、Postgres） |
| 書き込みとチェックポイントは一緒にコミットされ、間の失敗はどちらも残さない | `consumer_spec.cr` の "leaves out both the writes and the checkpoint of a failing event" と、上の "killed during a batch" |
| 表のプロジェクションが上限までに必要な `id` に届かなければ 503（前半） | `consumer_read_spec.cr` の "is a 503 document while the projection lags, and a 200 once it reached the id" |

セッションが `id` を忘れた後に 200 になる後半は 7c で満たす。現行フェーズの表示は変えない（7d で「フェーズ 7 の受入を満たした」にする）。
