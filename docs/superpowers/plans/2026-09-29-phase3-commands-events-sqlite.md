# Phase 3 Commands, Events, and SQLite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** フェーズ 3 の受入まで届ける。`Shomen::Command` と `Shomen::Event`、追記のみの SQLite ストア（`events` 表、ストリームと版、ストリームをまたぐ `id`）、期待した版と違う追記での `Shomen::Conflict` と 409、チェックポイントを持つメモリ上のプロジェクション、起動時の再構築、`examples/hello` での名前変更の例。

**Architecture:** `Shomen::Event` は `JSON::Serializable` を include し、`event_type "name"` で `type` 列に入る名前を宣言する。読み戻しは `Shomen::Event.decode` が include した型をマクロで列挙して行う（D1）。`Shomen::Command#call` は `Array(Shomen::Event) | Shomen::Rejected` を返し、ルートが分岐して `Shomen::Store#append` を呼ぶ（D2）。`Shomen::Store` は `crystal-db` 経由で SQLite を開き、追記をプロセス内の実パスごとの `Mutex` と `BEGIN IMMEDIATE` で直列にし、同じトランザクションの中でストリームの最大の版を確かめてから挿入する（D3）。`Shomen::Projection` は `catch_up` で `id` 順にチェックポイントより後のイベントを適用する（D5）。サーバは捕まえられなかった `Shomen::Conflict` を 409 の HTML 文書にする（D6）。

**Tech Stack:** Crystal `>= 1.20.0`（開発機は 1.21.1）、標準ライブラリの `spec`、`json`、`uri`、`http/server`。外部 shard は `crystal-lang/crystal-sqlite3`（shard `sqlite3`、0.23.0）と `crystal-lang/crystal-db`（shard `db`、0.14.0）だけ。システムの libsqlite3（開発機は 3.54.0）。

**Spec:** `docs/en/00-INSTRUCTION.md` の「1. Package layout」（依存してよい shard）、「7. Commands and events」、「9. Error model」（`Shomen::Conflict`）、`docs/en/01-ARCHITECTURE.md` の「Request path」「Module boundaries」「Persistence」の Phase 3、`docs/en/02-PHASES.md` のフェーズ 3、`docs/en/03-CONVENTIONS.md`。細部は次の決定ファイルに従う。既存のもの:

- `docs/decisions/20260929-scale-event-stream.md`（ストリーム、版、`Conflict`、再試行しない）
- `docs/decisions/20260929-scale-event-evolution.md`（行を書き換えない、宣言した名前を `type` に入れる）
- `docs/decisions/20260929-scale-sqlite-writes.md`（`BEGIN IMMEDIATE`、ファイルごとに 1 つの `Mutex`、ビジータイムアウト 5 秒）
- `docs/decisions/20260929-scale-projection-checkpoint.md`（チェックポイント、読む前に追いつく）

この計画の Task 1 で足すもの:

- `docs/decisions/20260929-phase3-event-type.md`（D1）
- `docs/decisions/20260929-phase3-command-result.md`（D2）
- `docs/decisions/20260929-phase3-store-api.md`（D3）
- `docs/decisions/20260929-phase3-store-in-core.md`（D4）
- `docs/decisions/20260929-phase3-projection-api.md`（D5）
- `docs/decisions/20260929-phase3-conflict-response.md`（D6）
- `docs/decisions/20260929-phase3-users-example.md`（D7）

## Global Constraints

- 言語は Crystal 1.20 以上。`shard.yml` の下限は `>= 1.20.0` のまま。
- 本体 shard に足す依存は `sqlite3`（`github: crystal-lang/crystal-sqlite3`、`version: ">= 0.23.0"`）と `db`（`github: crystal-lang/crystal-db`、`version: ">= 0.14.0"`）だけ（仕様 1、03 の「下限を書く」）。
- `events` 表は仕様 7 のとおり: `id INTEGER PRIMARY KEY`、`stream TEXT NOT NULL`、`version INTEGER NOT NULL`、`type TEXT NOT NULL`、`payload TEXT NOT NULL`（JSON）、`at TEXT NOT NULL`（UTC、RFC 3339）、`UNIQUE (stream, version)`。整数は `Int64` で読む。
- 版はストリームごとに 1 から数える。追記は期待する版を渡し、違えば何も書かずに `Shomen::Conflict`。ストアは再試行しない。
- 追記は `BEGIN IMMEDIATE`。プロセス内では同じファイル（実パス）に 1 つの `Mutex` を先に取る。ビジータイムアウトは 5000 ミリ秒。書き込みトランザクションの中で副作用を実行しない。
- WAL モード。既定のファイルは `var/shomen.sqlite3`（アプリが変えてよい）。
- モジュール境界: Store は HTML を import しない。Command、Event、Projection は SQLite を名指ししない（コメントにも `sqlite` と書かない。Task 5 の境界 spec が文字列で検査する）。
- 公開 API は `Shomen::` 配下だけ。1 ファイル 1 主要型。ファイル名は機能名。
- 予想される 4xx は例外で流さない（コマンドの検証失敗は `Shomen::Rejected` を返し、ルートが 422 を返す）。`Shomen::Conflict` と `Shomen::NotFound` は仕様 9 の例外として投げてよい。
- 色コード、デザイントークン、国際化の仕組みを作らない。
- フェーズ 4 以降は作らない。`render_fragment`、JSON 応答、`shomen.js`、SSE、島、Postgres、コンシューマ、通知、`ETag`、CSP、本番の例外秘匿は範囲外。
- コードと識別子は英語。この計画と決定ログは日本語。
- ユーザーが指示するまで commit しない。この計画に commit 手順は無い。
- `crystal tool format` を通し、警告を残して完了にしない。
- テストはポートを bind しない。sleep で同期しない。SQLite のファイルは `File.tempname` で作り、`-wal` と `-shm` も含めて消す。ポート 3000 を使うのは Task 7 の手動確認だけ。
- 検証でリポジトリルートにできる実行ファイル `shomen` は `docs/decisions/20260928-build-artifact.md` のとおり削除する。

実行はリポジトリルートで行う。`Shomen::VERSION` は `"0.0.0"` のまま変えない。

## Review Focus

- 古いフォームの送信。別のタブで名前を変えた後、先に開いていたフォーム（hidden の `version` が古い）を送る。409 の HTML 文書になり、行は増えず、例外メッセージ（ストリーム名と版）は画面に出ない。Task 7 の spec で固定する。
- 衝突の後のストア。`Shomen::Conflict` を投げた後も同じストアで追記と読み取りができ、`close` が例外を投げない。crystal-sqlite3 は、失敗した文が残ると `close` で例外を投げるので、衝突は SQL の失敗ではなく版の確認で止める必要がある。Task 3 の spec で固定する。
- `apply` の途中の失敗。プロジェクションの `apply` が 2 件目で例外を投げる。チェックポイントは 1 件目の `id` に留まり、次の `catch_up` は 2 件目からやり直し、1 件目を二度適用しない。Task 4 の spec で固定する。
- 知らない `type` の行。新しいビルドが書いた行や、消されたイベント型の行を読む。黙って読み飛ばさず、型の名前を含む `ArgumentError` を投げる。Task 3 の spec で固定する。
- URL の形。`sqlite3://./var/shomen.sqlite3` のように `var/` がまだ無い相対パスは、ディレクトリを作って開く。`sqlite3::memory:`、`sqlite3://:memory:`、`sqlite3://`、`sqlite3:///`、`postgres://…` は `ArgumentError`。開けないファイルは、ファイル名を含む `DB::ConnectionRefused`。Task 3 の spec で固定する。
- 使用中の `close`。実行中の `append` や `read` がある間、`close` は同じファイルのロックを待つ。UTC でない `at` は `ArgumentError`。`prepared_statements_cache` を切る URL は `ArgumentError`。Task 3 の spec で固定する（PR のレビュー後に追加）。
- ロック待ちのタイムアウトと、SQLite が自分でロールバックした追記。どちらの後も同じストアで追記と読み取りができ、`close` が例外を投げない。後者は元のエラーを上げ、`ROLLBACK` の失敗で隠さない。Task 3 の spec で固定する（最終レビュー後に追加）。

## File Map

| ファイル | 役割 | Task |
|---|---|---|
| `docs/en/02-PHASES.md`、`docs/02-PHASES.md` | 現行フェーズをフェーズ 3 にする | 1 |
| `docs/decisions/20260929-phase3-*.md` | D1〜D7 | 1 |
| `src/shomen/event.cr` | `Shomen::Event`。`event_type` マクロ、`decode`、宣言の検査 | 2 |
| `src/shomen/rejected.cr` | `Shomen::Rejected`。検証失敗のメッセージ | 2 |
| `src/shomen/command.cr` | `Shomen::Command`。`call` の契約 | 2 |
| `src/shomen/recorded.cr` | `Shomen::Recorded`。`id`、`stream`、`version`、`event` | 3 |
| `src/shomen/conflict.cr` | `Shomen::Conflict` 例外 | 3 |
| `src/shomen/store.cr` | `Shomen::Store`。開く、追記、読む、閉じる | 3 |
| `src/shomen/projection.cr` | `Shomen::Projection`。`catch_up` とチェックポイント | 4 |
| `src/shomen/server.cr` | `Shomen::Conflict` を 409 にする | 6 |
| `src/shomen.cr` | 新しいファイルの require | 2, 3, 4 |
| `shard.yml`、`shard.lock` | `sqlite3` と `db` | 3 |
| `spec/spec_helper.cr` | 新しい support の require | 2, 3, 4 |
| `spec/support/events.cr` | spec 用のイベントとコマンド | 2 |
| `spec/support/store.cr` | `with_store`、`remove_database`、`note` | 3 |
| `spec/support/projections.cr` | spec 用のプロジェクション `SpecEvents::Log` | 4 |
| `spec/support/store_worker.cr` | 別プロセスで追記する実行ファイルの元 | 5 |
| `spec/support/routes.cr` | 409 を確かめるルート | 6 |
| `spec/shomen/event_spec.cr`、`spec/shomen/command_spec.cr` | Task 2 | 2 |
| `spec/fixtures/event_missing_type.cr`、`spec/fixtures/event_duplicate_type.cr` | コンパイル失敗のフィクスチャ | 2 |
| `spec/shomen/store_spec.cr` | Task 3 | 3 |
| `spec/shomen/projection_spec.cr` | Task 4 | 4 |
| `spec/shomen/store_concurrency_spec.cr`、`spec/shomen/boundary_spec.cr` | Task 5 | 5 |
| `spec/shomen/conflict_spec.cr` | Task 6 | 6 |
| `examples/hello/src/users.cr` | `Users` の例 | 7 |
| `examples/hello/src/hello.cr` | `require "./users"`、起動前の `catch_up` | 7 |
| `examples/hello/spec/spec_helper.cr` | 一時 DB の URL と後片付け | 7 |
| `examples/hello/spec/users_spec.cr` | 例での受入 | 7 |
| `examples/hello/shard.lock` | 推移的な依存 | 3 |
| `README.md`、`README.ja.md` | フェーズ 3 の反映、libsqlite3 の要件 | 8 |

---

### Task 1: 現行フェーズと決定ファイル

**Files:**
- Modify: `docs/en/02-PHASES.md:5-9`
- Modify: `docs/02-PHASES.md:5-9`
- Create: `docs/decisions/20260929-phase3-event-type.md`
- Create: `docs/decisions/20260929-phase3-command-result.md`
- Create: `docs/decisions/20260929-phase3-store-api.md`
- Create: `docs/decisions/20260929-phase3-store-in-core.md`
- Create: `docs/decisions/20260929-phase3-projection-api.md`
- Create: `docs/decisions/20260929-phase3-conflict-response.md`
- Create: `docs/decisions/20260929-phase3-users-example.md`

**Interfaces:**
- Consumes: なし
- Produces: 後続タスクが従う決定 D1〜D7。ここで決めた名前（`event_type`、`Shomen::Rejected`、`Shomen::Store.new(url)`、`append`、`read`、`close`、`Shomen::Projection#catch_up`、`#checkpoint`、`#apply`、`BATCH`、`HELLO_DATABASE_URL`）は Task 2〜7 のコードと一致させる。

- [ ] **Step 1: 現行フェーズを書き換える（英語）**

`docs/en/02-PHASES.md` の「## Current phase」の本文を次にする。

```markdown
## Current phase

**Phase 3 — commands, events, and SQLite**

Phase 2 acceptance is met. Do not implement past this point (phase 4 and later). When phase 3 acceptance is met, stop and wait for the next instruction.
```

- [ ] **Step 2: 現行フェーズを書き換える（日本語訳）**

`docs/02-PHASES.md` の「## 現行フェーズ」の本文を次にする。見出しの表記は同じファイルの 69 行目「## フェーズ 3 — コマンドとイベントと SQLite」に合わせる。

```markdown
## 現行フェーズ

**フェーズ 3 — コマンドとイベントと SQLite**

フェーズ 2 の受入は満たした。ここより先（フェーズ 4 以降）を実装しない。3 の受入を満たしたら停止し、ユーザーの次指示を待つ。
```

- [ ] **Step 3: D1 を書く**

`docs/decisions/20260929-phase3-event-type.md`:

```markdown
# 状況

仕様 7 は、`type` 列にイベント型が宣言する名前を入れるとする（`20260929-scale-event-evolution.md`）。宣言の書き方、`payload` の作り方、行からイベントを読み戻す方法は決めていない。標準の `Time#to_json` は秒未満を落とす。

# 決定

`include Shomen::Event` した struct は、本体で `event_type "user_renamed"` と書いて名前を宣言する。引数は空でない文字列リテラルに限る。宣言の無い型と、2 つの型が同じ名前を宣言したプログラムは、コンパイルエラーにする。`Shomen::Event` は `JSON::Serializable` を include させ、`payload` はその JSON にする。読み戻しは `Shomen::Event.decode(type, payload)` が、`Shomen::Event` を include した型をマクロで列挙して行う。知らない名前は、名前を含む `ArgumentError` にする。`at` は `payload` と `at` 列のどちらも秒までの UTC の RFC 3339 にし、秒未満は保存しない。`at` が UTC でないイベントは、`Shomen::Store#append` が何も書かずに `ArgumentError` にする。

# 理由

宣言をマクロにすれば、書き忘れと重複をコンパイル時に止められる。`JSON::Serializable` は標準ライブラリで、既定値のあるフィールドを足しても古い行を読める。知らない名前を読み飛ばすと、リードモデルが黙って欠ける。秒未満を残すには独自の変換器が要り、イベントの順序は `id` が決めるので要らない。

# 破棄した案

- 実行時に型を登録する表（登録漏れが読むときまで見つからない）
- アノテーションで名前を付ける（書き忘れを検出する仕組みが別に要る）
- Crystal の型名をそのまま使う（改名で古い行が読めなくなる）
- 知らない名前の行を読み飛ばす
- 秒未満まで保存する変換器を入れる
- UTC でない `at` を追記のときに UTC へ直す（`payload` はイベント型の JSON なので、ストアが中の時刻を書き換えることになる）
```

- [ ] **Step 4: D2 を書く**

`docs/decisions/20260929-phase3-command-result.md`:

```markdown
# 状況

仕様 7 は、コマンドが検証してイベントの列を返すとする。検証に失敗したときの返し方と、だれがストアに追記するかは決めていない。03-CONVENTIONS は、予想される 4xx を例外で流さないとする。01-ARCHITECTURE の表で、Store は Event にだけ依存してよい。

# 決定

`Shomen::Command` は `abstract def call : Array(Shomen::Event) | Shomen::Rejected` だけを持つ。`Shomen::Rejected` は利用者に見せるメッセージの配列 `messages : Array(String)` を持つ。ルートが結果を分岐する。`Shomen::Rejected` なら 422 でフォームを描き直し、イベントの配列なら `store.append(stream, expected_version, events)` を呼ぶ。コマンドはストアもストリーム名も知らない。

# 理由

union を返せば、呼び出し側は失敗の分岐をコンパイラに強制される。ストアがコマンドを知らなければ、モジュール境界の表を守れる。ストリーム名と期待する版はルートが持つ入力（パスの id とフォームの版）から決まるので、ルートが渡すのが最短である。

# 破棄した案

- 検証の失敗を例外にする
- `errors` と `call` を別のメソッドにする（`errors` を見ずに `call` できる）
- `Store#execute(command, expected_version)`（Store が Command に依存する）
- コマンドに `stream` を宣言させる（フェーズ 3 の受入に要らない）
```

- [ ] **Step 5: D3 を書く**

`docs/decisions/20260929-phase3-store-api.md`:

```markdown
# 状況

仕様とアーキテクチャは、表の形、WAL、`BEGIN IMMEDIATE`、ファイルごとのロック、ビジータイムアウトを決めた。Store の公開 API は決めていない。フェーズ 6 では Postgres が同じコマンドの API で動く必要がある。

# 決定

- `Shomen::Store.new(url : String)`。フェーズ 3 はスキーム `sqlite3` だけを受け付ける。URL として読めないもの、ほかのスキーム、ファイル名が空、`:memory:`、ディレクトリは `ArgumentError`。ファイルを開けなければ、ファイル名を含む `DB::ConnectionRefused` にする。`events` 表を作れなければ、失敗した文をリセットし、開いた DB を閉じてから例外を上げる。`prepared_statements_cache` を `true` 以外にする URL は `ArgumentError`（文が解放されず、失敗した文をリセットできない）
- URL に無ければ `journal_mode=wal` と `busy_timeout=5000` を足す。URL にあればそれを使う
- ファイルの親ディレクトリが無ければ作る。`events` 表を `CREATE TABLE IF NOT EXISTS` で作る。マイグレーションの仕組みは作らない
- `append(stream : String, expected_version : Int64, events : Array(Shomen::Event)) : Nil`。空の配列は何もしない。空のストリーム名と負の版は `ArgumentError`。版の確認は `BEGIN IMMEDIATE` の中で `SELECT COALESCE(MAX(version), 0)` で行い、違えば `ROLLBACK` して `Shomen::Conflict` を投げる。`payload` と `at` の文字列はロックを取る前に作る
- `UNIQUE (stream, version)` に当たったときは、`SQLite3::Exception` をそのまま上げる。追記が直列なので、通常は版の確認が先に止める
- `read(after : Int64, limit : Int32 = 500) : Array(Shomen::Recorded)` は `id` が `after` より大きい行を `id` 順に返す
- 失敗した文は `ROLLBACK` の前後にリセットする。SQLite がすでにロールバックしていて `ROLLBACK` が失敗しても、元の例外を上げる
- `close : Nil`
- プロセス内のロックは、`File.realpath` で求めた実パスごとに 1 つの `Mutex` にする。`read` と `close` も同じロックを取る。`close` が、実行中の `append` や `read` の文を解放しないため

# 理由

URL にしておけば、フェーズ 6 で呼び出し側を変えずにスキームを足せる。`:memory:` は接続ごとに別の DB になり、接続プールと両立しない。crystal-sqlite3 は、失敗した文が残ると `close` で例外を投げるので、衝突は SQL の失敗ではなく版の確認で止める。`append` が最後の `id` を返すかどうかは、それを使うフェーズ 7 の read-your-writes で決める。

# 破棄した案

- ファイルパスだけを受け取る（フェーズ 6 で API が変わる）
- アダプタの抽象クラスを今作る（実装が 1 つしか無い）
- `UNIQUE` 違反を `Shomen::Conflict` に変換する（失敗した文が残る）
- `append` が最後の `id` を返す
```

- [ ] **Step 6: D4 を書く**

`docs/decisions/20260929-phase3-store-in-core.md`:

```markdown
# 状況

Store は `crystal-db` と `crystal-sqlite3` を require し、libsqlite3 をリンクする。`require "shomen"` で Store も読み込むか、アプリが別に require するかを決めていない。

# 決定

`src/shomen.cr` が Command、Event、Store、Projection も require する。`require "shomen"` するアプリは libsqlite3 をリンクする。

# 理由

00-INSTRUCTION の前提は、アプリが SQLite の 1 プロセスで始まることである。事実はイベントログにあり、Store を使わないアプリは想定の外にある。require を分けると、例と README の手順が 1 つ増えるだけで、利点が小さい。

# 破棄した案

- `require "shomen/store"` を別にして、Store を選んで使う
- SQLite をコンパイル時フラグで切り替える
```

- [ ] **Step 7: D5 を書く**

`docs/decisions/20260929-phase3-projection-api.md`:

```markdown
# 状況

`20260929-scale-projection-checkpoint.md` は、メモリ上のプロジェクションがチェックポイントを持ち、ビューが読む前に追いつくとした。クラスの形、いつ追いつくか、同時に追いつこうとしたとき、適用が失敗したときの扱いは決めていない。

# 決定

`abstract class Shomen::Projection` は `initialize(store : Shomen::Store)`、`abstract def apply(recorded : Shomen::Recorded) : Nil`、`checkpoint : Int64`（初期値 0）、`catch_up : self` を持つ。`catch_up` は `Mutex` の中で、`store.read(after: checkpoint, limit: BATCH)`（`BATCH = 500`）を、返った件数が `BATCH` より少なくなるまで繰り返す。1 件適用するたびにチェックポイントをその `id` に進める。`apply` が例外を投げたら、チェックポイントはその手前に留まり、例外をそのまま上げる。ルートは読む前に自分で `catch_up` を呼ぶ。起動時の再構築は、アプリが `Shomen::Server.start` の前に `catch_up` を呼ぶことで行う。

# 理由

`Mutex` があれば、同時に来た要求のファイバーが同じイベントを二度適用しない。1 件ごとにチェックポイントを進めれば、失敗したイベントを飛ばさず、適用済みのイベントを繰り返さない。サーバがすべてのプロジェクションを知って毎回追いつかせる仕組みは、フェーズ 3 の受入に要らない。`catch_up` が `self` を返すので、`NAMES.catch_up.find(id)` と 1 行で読める。

# 破棄した案

- バッチ単位でチェックポイントを進める（途中の失敗で適用済みを繰り返す）
- サーバが登録済みのプロジェクションを要求ごとに追いつかせる
- 読み取りもロックで囲む API（フェーズ 3 のサーバは 1 スレッドで動く）
- 起動時にスナップショットから始める
```

- [ ] **Step 8: D6 を書く**

`docs/decisions/20260929-phase3-conflict-response.md`:

```markdown
# 状況

仕様 9 は、捕まえられなかった `Shomen::Conflict` を 409 の HTML 文書にするとする。本文に何を出すかは決めていない。例外メッセージにはストリーム名と版が入る。

# 決定

サーバは `Shomen::ErrorView` で 409 を返す。見出しは `Conflict`、本文は固定の `This changed after the page was loaded. Reload the page and try again.` にする。例外メッセージは出さない。

# 理由

ストリーム名と版は内部の識別子で、利用者の役に立たない。利用者がすべきことは読み直して送り直すことなので、それを書く。開発中に 500 のメッセージを出すのとは違い、409 は予想される結果である。

# 破棄した案

- 例外メッセージを出す
- サーバが自動でフォームを描き直す（どのフォームかをサーバは知らない）
```

- [ ] **Step 9: D7 を書く**

`docs/decisions/20260929-phase3-users-example.md`:

```markdown
# 状況

フェーズ 3 の例は「名前を変えると、イベントの行が 1 つ増える」ことである。AGENTS.md の検証コマンドは `examples/hello` だけを走らせる。フェーズ 2 の `Greeting` はフェーズ 4 の受入（JavaScript なしでフォームが動く）でも使う。

# 決定

`examples/hello/src/users.cr` に次を置き、`hello.cr` から require する。

- コマンド `Users::RenameUser`、イベント `Users::UserRenamed`（`event_type "user_renamed"`）、ストリーム `user-<id>`、プロジェクション `Users::Names`
- `Users::Edit`（`GET /users/:id/edit`）、`Users::Rename`（`POST /users/:id`）、`Users::Show`（`GET /users/:id`）
- フォームは、開いたときのストリームの版を hidden の `version` で送る。版は最後の改名ではなく、ストリームの最後のイベントの版にする。`Users::Rename` はそれを期待する版にして追記する。古いフォームは 409、負の版は 400 になる
- 名前が前後の空白を除いて 2 文字未満なら、コマンドが `Shomen::Rejected` を返し、422 で描き直す
- 名前のまだ無い利用者の `Users::Show` は 404
- DB の URL は環境変数 `HELLO_DATABASE_URL`、無ければ `sqlite3://./var/shomen.sqlite3`
- `Shomen::Server.start` の前に `Users::NAMES.catch_up` を呼ぶ
- `Greeting` は変えない

# 理由

期待する版をフォームに載せれば、フォームを開いてから送るまでの間の別の変更を検出でき、409 の経路を例で確かめられる。`Greeting` を残せば、フェーズ 2 の受入とフェーズ 4 の前提が変わらない。

# 破棄した案

- `Greeting` を永続化に書き換える
- 送信時にリードモデルの版を期待する版にする（古いフォームで黙って上書きする）
- `examples/users` を新しく作る（検証コマンドが走らせない）
```

- [ ] **Step 10: 確認する**

Run: `grep -n "Phase 3 — commands" docs/en/02-PHASES.md && grep -n "フェーズ 3 — コマンドとイベントと SQLite" docs/02-PHASES.md && ls docs/decisions/20260929-phase3-*.md | wc -l`
Expected: 英語は 2 行（現行フェーズと本文の見出し）、日本語も 2 行、決定ファイルは `7`。

---

### Task 2: Event、Rejected、Command

**Files:**
- Create: `src/shomen/event.cr`
- Create: `src/shomen/rejected.cr`
- Create: `src/shomen/command.cr`
- Modify: `src/shomen.cr`
- Create: `spec/support/events.cr`
- Modify: `spec/spec_helper.cr`
- Test: `spec/shomen/event_spec.cr`
- Test: `spec/shomen/command_spec.cr`
- Create: `spec/fixtures/event_missing_type.cr`
- Create: `spec/fixtures/event_duplicate_type.cr`

**Interfaces:**
- Consumes: なし
- Produces:
  - `module Shomen::Event`。include した型は `JSON::Serializable` を持つ。マクロ `event_type(name)` は定数 `EVENT_TYPE` とインスタンスメソッド `event_type : String` を定義する
  - `Shomen::Event#event_type : String`、`#at : Time`、`#to_json : String`
  - `Shomen::Event.decode(type : String, payload : String) : Shomen::Event`。知らない名前は `ArgumentError`（メッセージ `unknown event type "<name>"`）
  - `struct Shomen::Rejected`、`#messages : Array(String)`、`.new(messages : Array(String))`
  - `module Shomen::Command`、`abstract def call : Array(Shomen::Event) | Shomen::Rejected`
  - spec 用: `SpecEvents::Noted`（`text : String`、`at : Time`、`event_type "spec.noted"`）、`SpecEvents::Renamed`（`name : String`、`at : Time`、`event_type "spec.renamed"`）、`SpecEvents::Note`（コマンド。空の `text` は `Rejected`）

- [ ] **Step 1: spec 用のイベントとコマンドを書く**

`spec/support/events.cr`:

```crystal
module SpecEvents
  struct Noted
    include Shomen::Event
    event_type "spec.noted"

    getter text : String
    getter at : Time

    def initialize(@text : String, @at : Time = Time.utc)
    end
  end

  struct Renamed
    include Shomen::Event
    event_type "spec.renamed"

    getter name : String
    getter at : Time

    def initialize(@name : String, @at : Time = Time.utc)
    end
  end

  struct Note
    include Shomen::Command

    def initialize(@text : String)
    end

    def call : Array(Shomen::Event) | Shomen::Rejected
      return Shomen::Rejected.new(["text must not be empty"]) if @text.empty?
      [Noted.new(@text)] of Shomen::Event
    end
  end
end
```

`spec/spec_helper.cr` の `require "./support/routes"` の後に足す:

```crystal
require "./support/events"
```

- [ ] **Step 2: 失敗する spec を書く**

`spec/shomen/event_spec.cr`:

```crystal
require "../spec_helper"

describe Shomen::Event do
  it "returns the name the type declares" do
    SpecEvents::Noted.new("a").event_type.should eq("spec.noted")
    SpecEvents::Noted::EVENT_TYPE.should eq("spec.noted")
  end

  it "decodes a payload by its declared name" do
    at = Time.utc(2026, 9, 29, 1, 2, 3)
    event = Shomen::Event.decode("spec.renamed", SpecEvents::Renamed.new("Ada", at).to_json)
    event.should be_a(SpecEvents::Renamed)
    event.as(SpecEvents::Renamed).name.should eq("Ada")
    event.at.should eq(at)
  end

  it "keeps the time to the second" do
    at = Time.utc(2026, 9, 29, 1, 2, 3, nanosecond: 500_000_000)
    decoded = Shomen::Event.decode("spec.noted", SpecEvents::Noted.new("a", at).to_json)
    decoded.at.should eq(Time.utc(2026, 9, 29, 1, 2, 3))
  end

  it "raises for a name no type declares" do
    expect_raises(ArgumentError, %(unknown event type "gone")) do
      Shomen::Event.decode("gone", "{}")
    end
  end

  it "fails to compile an event without event_type" do
    status, output = crystal_build_fixture("spec/fixtures/event_missing_type.cr")
    status.should_not eq(0)
    output.should contain("event_type")
  end

  it "fails to compile two events with one event_type" do
    status, output = crystal_build_fixture("spec/fixtures/event_duplicate_type.cr")
    status.should_not eq(0)
    output.should contain("both declare event_type")
  end
end
```

`spec/shomen/command_spec.cr`:

```crystal
require "../spec_helper"

describe Shomen::Command do
  it "returns events when the input is valid" do
    result = SpecEvents::Note.new("hello").call
    result.should be_a(Array(Shomen::Event))
    result.as(Array(Shomen::Event)).first.as(SpecEvents::Noted).text.should eq("hello")
  end

  it "returns Rejected with messages when the input is invalid" do
    result = SpecEvents::Note.new("").call
    result.should be_a(Shomen::Rejected)
    result.as(Shomen::Rejected).messages.should eq(["text must not be empty"])
  end
end
```

`spec/fixtures/event_missing_type.cr`:

```crystal
require "../../src/shomen"

struct Unnamed
  include Shomen::Event

  getter at : Time

  def initialize(@at : Time)
  end
end

Unnamed.new(Time.utc).to_json
```

`spec/fixtures/event_duplicate_type.cr`:

```crystal
require "../../src/shomen"

struct First
  include Shomen::Event
  event_type "same"

  getter at : Time

  def initialize(@at : Time)
  end
end

struct Second
  include Shomen::Event
  event_type "same"

  getter at : Time

  def initialize(@at : Time)
  end
end

First.new(Time.utc).to_json
```

- [ ] **Step 3: 失敗を確かめる**

Run: `crystal spec spec/shomen/event_spec.cr spec/shomen/command_spec.cr`
Expected: FAIL。`undefined constant Shomen::Event`（または `Shomen::Command`）でコンパイルが止まる。

- [ ] **Step 4: 実装する**

`src/shomen/event.cr`:

```crystal
require "json"

# A fact. Stored rows are never rewritten, so each type keeps the name it
# declares with event_type, even after the Crystal type is renamed.
module Shomen::Event
  macro included
    include JSON::Serializable
  end

  macro event_type(name)
    {% unless name.is_a?(StringLiteral) && !name.empty? %}
      {% name.raise "event_type takes a non-empty string literal" %}
    {% end %}
    EVENT_TYPE = {{name}}

    def event_type : String
      EVENT_TYPE
    end
  end

  abstract def event_type : String
  abstract def at : Time

  def self.decode(type : String, payload : String) : Shomen::Event
    {% begin %}
      {% events = Shomen::Event.includers %}
      {% if events.empty? %}
        raise ArgumentError.new("unknown event type #{type.inspect}")
      {% else %}
        case type
        {% for event in events %}
          when {{event}}::EVENT_TYPE then {{event}}.from_json(payload)
        {% end %}
        else
          raise ArgumentError.new("unknown event type #{type.inspect}")
        end
      {% end %}
    {% end %}
  end

  macro finished
    {% seen = {} of Nil => Nil %}
    {% for event in @type.includers %}
      {% unless event.has_constant?("EVENT_TYPE") %}
        {% raise "#{event.name} must declare event_type" %}
      {% end %}
      {% name = event.constant("EVENT_TYPE") %}
      {% if seen[name] %}
        {% raise "#{event.name} and #{seen[name]} both declare event_type #{name}" %}
      {% end %}
      {% seen[name] = event.name %}
    {% end %}
  end
end
```

`src/shomen/rejected.cr`:

```crystal
# What a command returns instead of events when its input is invalid.
# The messages are shown to the person who sent the input.
struct Shomen::Rejected
  getter messages : Array(String)

  def initialize(@messages : Array(String))
  end
end
```

`src/shomen/command.cr`:

```crystal
require "./event"
require "./rejected"

# An intent. It validates and returns the events to append; it never
# writes. The route appends them with the version it expects.
module Shomen::Command
  abstract def call : Array(Shomen::Event) | Shomen::Rejected
end
```

`src/shomen.cr` の `require "./shomen/forbidden"` の後に足す:

```crystal
require "./shomen/event"
require "./shomen/rejected"
require "./shomen/command"
```

- [ ] **Step 5: 通ることを確かめる**

Run: `crystal spec spec/shomen/event_spec.cr spec/shomen/command_spec.cr`
Expected: PASS（8 examples, 0 failures）。`event_missing_type.cr` の出力は `Unnamed must declare event_type` を含む。

- [ ] **Step 6: 全体を確かめる**

Run: `crystal spec && crystal tool format --check && crystal build src/shomen.cr --error-trace && rm -f shomen`
Expected: 0 failures、整形の差分なし、ビルド成功。

---

### Task 3: Store、Recorded、Conflict と依存 shard

**Files:**
- Modify: `shard.yml`
- Modify: `shard.lock`（`shards install` が更新する）
- Modify: `examples/hello/shard.lock`（`shards update` が更新する）
- Create: `src/shomen/recorded.cr`
- Create: `src/shomen/conflict.cr`
- Create: `src/shomen/store.cr`
- Modify: `src/shomen.cr`
- Create: `spec/support/store.cr`
- Modify: `spec/spec_helper.cr`
- Test: `spec/shomen/store_spec.cr`

**Interfaces:**
- Consumes: Task 2 の `Shomen::Event`（`event_type`、`at`、`to_json`、`Shomen::Event.decode`）、`SpecEvents::Noted`、`SpecEvents::Note`
- Produces:
  - `class Shomen::Conflict < Exception`
  - `struct Shomen::Recorded`: `.new(id : Int64, stream : String, version : Int64, event : Shomen::Event)`、`#id`、`#stream`、`#version`、`#event`
  - `class Shomen::Store`: `.new(url : String)`、`#append(stream : String, expected_version : Int64, events : Array(Shomen::Event)) : Nil`、`#read(after : Int64, limit : Int32 = 500) : Array(Shomen::Recorded)`、`#close : Nil`、定数 `BUSY_TIMEOUT_MS = 5000`。失敗した文は `ROLLBACK` の前後にリセットするので、衝突、ロック待ちのタイムアウト、SQLite によるロールバックの後も `close` は例外を投げない（最終レビュー後に追加）
  - spec 用: `with_store(& : Shomen::Store, String ->)`（一時ファイルのストアとそのパス）、`remove_database(path : String) : Nil`、`note(text : String) : Array(Shomen::Event)`

- [ ] **Step 1: 依存を足す**

`shard.yml` の末尾に足す:

```yaml

dependencies:
  sqlite3:
    github: crystal-lang/crystal-sqlite3
    version: ">= 0.23.0"
  db:
    github: crystal-lang/crystal-db
    version: ">= 0.14.0"
```

Run: `shards install && (cd examples/hello && shards update)`
Expected: ルートで `Installing db (0.14.0)` と `Installing sqlite3 (0.23.0)`、`shard.lock` に 2 つの shard が入る。`examples/hello/shard.lock` にも `db` と `sqlite3` が入る。

- [ ] **Step 2: spec の支えを書く**

`spec/support/store.cr`:

```crystal
def remove_database(path : String) : Nil
  [path, "#{path}-wal", "#{path}-shm"].each do |file|
    File.delete(file) if File.exists?(file)
  end
end

def with_store(&) : Nil
  path = File.tempname("shomen-store", ".sqlite3")
  store = Shomen::Store.new("sqlite3://#{path}")
  begin
    yield store, path
  ensure
    store.close
    remove_database(path)
  end
end

def note(text : String) : Array(Shomen::Event)
  [SpecEvents::Noted.new(text)] of Shomen::Event
end
```

`spec/spec_helper.cr` の `require "./support/events"` の後に足す:

```crystal
require "./support/store"
```

- [ ] **Step 3: 失敗する spec を書く**

`spec/shomen/store_spec.cr`:

```crystal
require "../spec_helper"
require "file_utils"

private def texts(rows : Array(Shomen::Recorded)) : Array(String)
  rows.map { |row| row.event.as(SpecEvents::Noted).text }
end

describe Shomen::Store do
  it "numbers each stream from 1 and orders ids across streams" do
    with_store do |store|
      store.append("a", 0_i64, note("a1"))
      store.append("b", 0_i64, note("b1"))
      store.append("a", 1_i64, [SpecEvents::Noted.new("a2"), SpecEvents::Noted.new("a3")] of Shomen::Event)
      rows = store.read(after: 0_i64)
      rows.map { |row| {row.id, row.stream, row.version} }.should eq([
        {1_i64, "a", 1_i64}, {2_i64, "b", 1_i64}, {3_i64, "a", 2_i64}, {4_i64, "a", 3_i64},
      ])
      texts(rows).should eq(%w(a1 b1 a2 a3))
    end
  end

  it "reads only the events after a given id, up to the limit" do
    with_store do |store|
      5.times { |index| store.append("s", index.to_i64, note("n#{index}")) }
      store.read(after: 2_i64, limit: 2).map(&.id).should eq([3_i64, 4_i64])
      store.read(after: 5_i64).should be_empty
    end
  end

  it "appends two rows when the same command is handled twice" do
    with_store do |store|
      2.times do |version|
        events = SpecEvents::Note.new("same").call.as(Array(Shomen::Event))
        store.append("s", version.to_i64, events)
      end
      rows = store.read(after: 0_i64)
      rows.map(&.version).should eq([1_i64, 2_i64])
      texts(rows).should eq(%w(same same))
    end
  end

  it "raises Conflict and adds no row when two appends expect the same version" do
    with_store do |store|
      store.append("s", 0_i64, note("first"))
      expect_raises(Shomen::Conflict, "stream s is at version 1, expected 0") do
        store.append("s", 0_i64, note("second"))
      end
      texts(store.read(after: 0_i64)).should eq(["first"])
    end
  end

  it "raises Conflict and adds no row when the expected version is ahead" do
    with_store do |store|
      expect_raises(Shomen::Conflict, "stream s is at version 0, expected 3") do
        store.append("s", 3_i64, note("ahead"))
      end
      store.read(after: 0_i64).should be_empty
    end
  end

  it "stays usable and closes cleanly after a conflict" do
    with_store do |store|
      store.append("s", 0_i64, note("one"))
      expect_raises(Shomen::Conflict) { store.append("s", 0_i64, note("two")) }
      store.append("s", 1_i64, note("two"))
      texts(store.read(after: 0_i64)).should eq(%w(one two))
      store.close
    end
  end

  it "does nothing for an empty list of events" do
    with_store do |store|
      store.append("s", 7_i64, [] of Shomen::Event)
      store.read(after: 0_i64).should be_empty
    end
  end

  it "rejects an empty stream name and a negative version" do
    with_store do |store|
      expect_raises(ArgumentError) { store.append("", 0_i64, note("x")) }
      expect_raises(ArgumentError) { store.append("s", -1_i64, note("x")) }
    end
  end

  it "writes the declared type, the JSON payload, and the time to the second" do
    with_store do |store, path|
      at = Time.utc(2026, 9, 29, 1, 2, 3, nanosecond: 500_000_000)
      store.append("s", 0_i64, [SpecEvents::Noted.new("x", at)] of Shomen::Event)
      DB.open("sqlite3://#{path}") do |db|
        type, payload, stored_at = db.query_one("SELECT type, payload, at FROM events", as: {String, String, String})
        type.should eq("spec.noted")
        JSON.parse(payload)["text"].as_s.should eq("x")
        stored_at.should eq("2026-09-29T01:02:03Z")
      end
      store.read(after: 0_i64).first.event.at.should eq(Time.utc(2026, 9, 29, 1, 2, 3))
    end
  end

  it "raises with the type name for a row whose type no event declares" do
    with_store do |store, path|
      DB.open("sqlite3://#{path}") do |db|
        db.exec("INSERT INTO events (stream, version, type, payload, at) VALUES ('s', 1, 'gone', '{}', '2026-09-29T00:00:00Z')")
      end
      expect_raises(ArgumentError, %(unknown event type "gone")) { store.read(after: 0_i64) }
    end
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

  it "refuses a URL that is not a sqlite3 file" do
    expect_raises(ArgumentError) { Shomen::Store.new("postgres://localhost/app") }
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

  it "refuses an event whose time is not UTC and adds no row" do
    with_store do |store|
      at = Time.local(2026, 9, 29, 0, 30, 0, location: Time::Location.fixed(9 * 3600))
      expect_raises(ArgumentError, "UTC") do
        store.append("s", 0_i64, [SpecEvents::Noted.new("x", at)] of Shomen::Event)
      end
      store.read(after: 0_i64).should be_empty
    end
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
      lock = store.@lock
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
end
```

- [ ] **Step 4: 失敗を確かめる**

Run: `crystal spec spec/shomen/store_spec.cr`
Expected: FAIL。`undefined constant Shomen::Store` でコンパイルが止まる。

- [ ] **Step 5: 実装する**

`src/shomen/conflict.cr`:

```crystal
class Shomen::Conflict < Exception
end
```

`src/shomen/recorded.cr`:

```crystal
require "./event"

# An event as the store keeps it: its place across every stream (id)
# and within its own stream (version).
struct Shomen::Recorded
  getter id : Int64
  getter stream : String
  getter version : Int64
  getter event : Shomen::Event

  def initialize(@id : Int64, @stream : String, @version : Int64, @event : Shomen::Event)
  end
end
```

`src/shomen/store.cr`:

```crystal
require "uri"
require "db"
require "sqlite3"
require "./event"
require "./recorded"
require "./conflict"

# Append-only event log in one SQLite file. Appends, reads, and close in a
# process take one fiber-aware lock per file, and appends then BEGIN
# IMMEDIATE; other processes wait through the busy timeout.
class Shomen::Store
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

  @@locks = {} of String => Mutex
  @@locks_lock = Mutex.new

  @db : DB::Database
  @lock : Mutex

  def initialize(url : String)
    uri = begin
      URI.parse(url)
    rescue ex : URI::Error
      raise ArgumentError.new("store URL is not valid: #{ex.message}")
    end
    raise ArgumentError.new("store URL must use sqlite3, got #{uri.scheme.inspect}") unless uri.scheme == "sqlite3"
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
    @lock = @@locks_lock.synchronize { @@locks[real] ||= Mutex.new }
  end

  def append(stream : String, expected_version : Int64, events : Array(Shomen::Event)) : Nil
    raise ArgumentError.new("stream must not be empty") if stream.empty?
    raise ArgumentError.new("expected_version must not be negative") if expected_version < 0
    return if events.empty?
    events.each do |event|
      raise ArgumentError.new("#{event.event_type} at must be UTC, got #{event.at}") unless event.at.utc?
    end
    rows = events.map { |event| {event.event_type, event.to_json, event.at.to_rfc3339} }
    @lock.synchronize do
      @db.using_connection do |connection|
        begin
          connection.exec("BEGIN IMMEDIATE")
        rescue ex
          reset(connection, "BEGIN IMMEDIATE")
          raise ex
        end
        begin
          insert(connection, stream, expected_version, rows)
          connection.exec("COMMIT")
        rescue ex
          rollback(connection)
          raise ex
        end
      end
    end
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

  private def insert(connection : DB::Connection, stream : String, expected_version : Int64, rows : Array({String, String, String})) : Nil
    current = connection.scalar(SELECT_VERSION, stream).as(Int64)
    unless current == expected_version
      raise Shomen::Conflict.new("stream #{stream} is at version #{current}, expected #{expected_version}")
    end
    rows.each_with_index(1) do |row, offset|
      type, payload, at = row
      connection.exec(INSERT, stream, expected_version + offset, type, payload, at)
    end
  end

  def read(after : Int64, limit : Int32 = 500) : Array(Shomen::Recorded)
    rows = @lock.synchronize do
      @db.query_all(
        "SELECT id, stream, version, type, payload FROM events WHERE id > ? ORDER BY id LIMIT ?",
        after, limit,
        as: {Int64, String, Int64, String, String},
      )
    end
    rows.map do |row|
      id, stream, version, type, payload = row
      Shomen::Recorded.new(id, stream, version, Shomen::Event.decode(type, payload))
    end
  end

  # Waits for an append or read in progress, which would otherwise use a
  # statement that close has finalized.
  def close : Nil
    @lock.synchronize { @db.close }
  end
end
```

`src/shomen.cr` の `require "./shomen/command"` の後に足す:

```crystal
require "./shomen/conflict"
require "./shomen/recorded"
require "./shomen/store"
```

- [ ] **Step 6: 通ることを確かめる**

Run: `crystal spec spec/shomen/store_spec.cr`
Expected: PASS（21 examples, 0 failures。うち 4 つは最終レビュー後、5 つは PR のレビュー後に追加）。`it "stays usable and closes cleanly after a conflict"` は `with_store` の `ensure` で 2 回目の `close` を呼ぶが、crystal-db の `Disposable#close` は閉じ済みなら何もしない。

- [ ] **Step 7: 全体と例を確かめる**

Run: `crystal spec && crystal tool format --check && crystal build src/shomen.cr --error-trace && rm -f shomen && (cd examples/hello && crystal spec)`
Expected: すべて 0 failures。hello は libsqlite3 をリンクしてもそのまま通る（D4）。

---

### Task 4: Projection

**Files:**
- Create: `src/shomen/projection.cr`
- Modify: `src/shomen.cr`
- Create: `spec/support/projections.cr`
- Modify: `spec/spec_helper.cr`
- Test: `spec/shomen/projection_spec.cr`

**Interfaces:**
- Consumes: Task 3 の `Shomen::Store#read(after:, limit:)`、`Shomen::Recorded`、`with_store`、`note`、`remove_database`
- Produces:
  - `abstract class Shomen::Projection`: `BATCH = 500`、`.new(store : Shomen::Store)`、`#checkpoint : Int64`、`#catch_up : self`、`abstract def apply(recorded : Shomen::Recorded) : Nil`
  - spec 用: `SpecEvents::Log < Shomen::Projection`、`record Line, id : Int64, stream : String, version : Int64, text : String`、`#lines : Array(Line)`、`#fail_on : String?`（その `text` の `Noted` を適用するときに例外）

- [ ] **Step 1: spec 用のプロジェクションを書く**

`spec/support/projections.cr`:

```crystal
module SpecEvents
  class Log < Shomen::Projection
    record Line, id : Int64, stream : String, version : Int64, text : String

    getter lines = [] of Line
    property fail_on : String? = nil

    def apply(recorded : Shomen::Recorded) : Nil
      case event = recorded.event
      when Noted
        raise "cannot apply #{event.text}" if event.text == fail_on
        @lines << Line.new(recorded.id, recorded.stream, recorded.version, event.text)
      end
    end
  end
end
```

`spec/spec_helper.cr` の `require "./support/store"` の後に足す:

```crystal
require "./support/projections"
```

- [ ] **Step 2: 失敗する spec を書く**

`spec/shomen/projection_spec.cr`:

```crystal
require "../spec_helper"

describe Shomen::Projection do
  it "applies every event from id 1 and records the checkpoint" do
    with_store do |store|
      store.append("a", 0_i64, note("one"))
      store.append("b", 0_i64, note("two"))
      log = SpecEvents::Log.new(store).catch_up
      log.lines.map(&.text).should eq(%w(one two))
      log.checkpoint.should eq(2_i64)
    end
  end

  it "applies only the events after its checkpoint" do
    with_store do |store|
      log = SpecEvents::Log.new(store)
      store.append("s", 0_i64, note("one"))
      log.catch_up
      store.append("s", 1_i64, note("two"))
      log.catch_up
      log.catch_up
      log.lines.map(&.text).should eq(%w(one two))
      log.checkpoint.should eq(2_i64)
    end
  end

  it "reads past one batch" do
    with_store do |store|
      count = Shomen::Projection::BATCH + 1
      events = Array(Shomen::Event).new(count) { |index| SpecEvents::Noted.new("n#{index}") }
      store.append("s", 0_i64, events)
      log = SpecEvents::Log.new(store).catch_up
      log.lines.size.should eq(count)
      log.checkpoint.should eq(count.to_i64)
    end
  end

  it "rebuilds the read model after a restart" do
    path = File.tempname("shomen-store", ".sqlite3")
    begin
      first = Shomen::Store.new("sqlite3://#{path}")
      first.append("s", 0_i64, note("one"))
      first.append("s", 1_i64, note("two"))
      first.close

      second = Shomen::Store.new("sqlite3://#{path}")
      log = SpecEvents::Log.new(second).catch_up
      log.lines.map { |line| {line.text, line.version} }.should eq([{"one", 1_i64}, {"two", 2_i64}])
      second.close
    ensure
      remove_database(path)
    end
  end

  it "sees an event appended through another store on the same file" do
    with_store do |store, path|
      other = Shomen::Store.new("sqlite3://#{path}")
      log = SpecEvents::Log.new(store).catch_up
      other.append("s", 0_i64, note("elsewhere"))
      log.catch_up.lines.map(&.text).should eq(["elsewhere"])
      other.close
    end
  end

  it "stops before an event it cannot apply and retries it next time" do
    with_store do |store|
      store.append("s", 0_i64, [
        SpecEvents::Noted.new("a"), SpecEvents::Noted.new("b"), SpecEvents::Noted.new("c"),
      ] of Shomen::Event)
      log = SpecEvents::Log.new(store)
      log.fail_on = "b"
      expect_raises(Exception, "cannot apply b") { log.catch_up }
      log.checkpoint.should eq(1_i64)
      log.lines.map(&.text).should eq(["a"])

      log.fail_on = nil
      log.catch_up
      log.lines.map(&.text).should eq(%w(a b c))
      log.checkpoint.should eq(3_i64)
    end
  end
end
```

- [ ] **Step 3: 失敗を確かめる**

Run: `crystal spec spec/shomen/projection_spec.cr`
Expected: FAIL。`undefined constant Shomen::Projection` でコンパイルが止まる。

- [ ] **Step 4: 実装する**

`src/shomen/projection.cr`:

```crystal
require "./store"
require "./recorded"

# A read model built by applying events in id order. The checkpoint is
# the last id applied, so a catch_up sees events any process appended.
abstract class Shomen::Projection
  BATCH = 500

  getter checkpoint : Int64 = 0_i64
  @lock = Mutex.new

  def initialize(@store : Shomen::Store)
  end

  abstract def apply(recorded : Shomen::Recorded) : Nil

  def catch_up : self
    @lock.synchronize do
      loop do
        batch = @store.read(after: @checkpoint, limit: BATCH)
        batch.each do |recorded|
          apply(recorded)
          @checkpoint = recorded.id
        end
        break if batch.size < BATCH
      end
    end
    self
  end
end
```

`src/shomen.cr` の `require "./shomen/store"` の後に足す:

```crystal
require "./shomen/projection"
```

- [ ] **Step 5: 通ることを確かめる**

Run: `crystal spec spec/shomen/projection_spec.cr`
Expected: PASS（6 examples, 0 failures）

- [ ] **Step 6: 全体を確かめる**

Run: `crystal spec && crystal tool format --check && crystal build src/shomen.cr --error-trace && rm -f shomen`
Expected: 0 failures、整形の差分なし、ビルド成功。

---

### Task 5: 並行の追記とモジュール境界

**Files:**
- Create: `spec/support/store_worker.cr`
- Test: `spec/shomen/store_concurrency_spec.cr`
- Test: `spec/shomen/boundary_spec.cr`

**Interfaces:**
- Consumes: `Shomen::Store`、`Shomen::Projection`、`SpecEvents::Noted`、`SpecEvents::Log`、`with_store`、`note`
- Produces: `spec/support/store_worker.cr`（引数 `url stream count`。`count` 件を `stream` に版 0 から順に追記して終わる。失敗すると非 0 で終わる）。本体コードの変更は無い。この Task の spec が最初から通るなら、それは Task 3 と 4 の実装が受入を満たしている証拠であり、失敗を作るために実装を壊さない。

- [ ] **Step 1: 別プロセス用の実行ファイルの元を書く**

`spec/support/store_worker.cr`（`src/shomen` の HTML 側を require しないので、Store が HTML なしでビルドできることの確認も兼ねる）:

```crystal
require "../../src/shomen/store"
require "../../src/shomen/command"
require "./events"

url, stream, count = ARGV
store = Shomen::Store.new(url)
count.to_i64.times do |version|
  store.append(stream, version, [SpecEvents::Noted.new("#{stream} #{version}")] of Shomen::Event)
end
store.close
```

- [ ] **Step 2: spec を書く**

`spec/shomen/store_concurrency_spec.cr`:

```crystal
require "../spec_helper"

describe "Shomen::Store with concurrent writers" do
  it "lets many fibers in one process append at once" do
    with_store do |store, path|
      other = Shomen::Store.new("sqlite3://#{path}")
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
      other.close
    end
  end

  it "lets two processes append to one file and a projection see both" do
    binary = File.tempname("shomen-store-worker")
    output = IO::Memory.new
    build = Process.run("crystal", ["build", "spec/support/store_worker.cr", "-o", binary], output: output, error: output)
    fail "worker build failed: #{output}" unless build.success?
    begin
      with_store do |store, path|
        errors = IO::Memory.new
        worker = Process.new(binary, ["sqlite3://#{path}", "worker", "300"], error: errors)
        300.times { |version| store.append("main", version.to_i64, note("main #{version}")) }
        status = worker.wait
        fail "worker failed: #{errors}" unless status.success?

        log = SpecEvents::Log.new(store).catch_up
        log.lines.map(&.id).should eq((1_i64..600_i64).to_a)
        %w(main worker).each do |stream|
          log.lines.select(&.stream.==(stream)).map(&.version).should eq((1_i64..300_i64).to_a)
        end
      end
    ensure
      File.delete(binary) if File.exists?(binary)
      File.delete("#{binary}.dwarf") if File.exists?("#{binary}.dwarf")
    end
  end
end
```

`spec/shomen/boundary_spec.cr`:

```crystal
require "../spec_helper"

private def source(name : String) : String
  File.read("src/shomen/#{name}.cr")
end

describe "phase 3 module boundaries" do
  it "keeps HTML out of the store and what it requires" do
    %w(store event recorded conflict).each do |name|
      source(name).should_not match(/Shomen::(HTML|View|ErrorView)|require "\.\/(html|view|a11y|error_view)"/)
    end
  end

  it "keeps SQLite out of commands, events, and projections" do
    %w(command event rejected recorded projection).each do |name|
      source(name).should_not match(/sqlite/i)
    end
  end
end
```

- [ ] **Step 3: 走らせる**

Run: `crystal spec spec/shomen/store_concurrency_spec.cr spec/shomen/boundary_spec.cr`
Expected: PASS（4 examples, 0 failures）。2 プロセスの spec は worker のビルドで 10〜30 秒かかる。

- [ ] **Step 4: 境界の spec が本当に止めることを確かめる**

`src/shomen/projection.cr` の先頭のコメントに一時的に `# sqlite` と足し、`crystal spec spec/shomen/boundary_spec.cr` が FAIL することを見てから、その行を消して PASS に戻す。

- [ ] **Step 5: 全体を確かめる**

Run: `crystal spec && crystal tool format --check`
Expected: 0 failures、整形の差分なし。

---

### Task 6: 409 の HTML 文書

**Files:**
- Modify: `src/shomen/server.cr:9-12`（定数）、`src/shomen/server.cr:56-63`（rescue）
- Modify: `spec/support/routes.cr`（末尾に追加）
- Test: `spec/shomen/conflict_spec.cr`

**Interfaces:**
- Consumes: Task 3 の `Shomen::Conflict`、既存の `call_with(server, method, path)`
- Produces: `Shomen::Server::CONFLICT_DETAIL : String`。`Shomen::Conflict` を捕まえなかったルートの応答は 409、`text/html; charset=utf-8`、`<h1>Conflict</h1>` と `CONFLICT_DETAIL` を含み、例外メッセージを含まない

- [ ] **Step 1: spec 用のルートを書く**

`spec/support/routes.cr` の末尾に足す:

```crystal
module ConflictRoutes
  class Clash < Shomen::Route
    method GET
    path "/phase3/conflict"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      raise Shomen::Conflict.new("stream secret-7 is at version 2, expected 1")
    end
  end
end
```

- [ ] **Step 2: 失敗する spec を書く**

`spec/shomen/conflict_spec.cr`:

```crystal
require "../spec_helper"

describe "an unhandled Shomen::Conflict" do
  it "returns a 409 HTML document without the exception message" do
    response = call_with(Shomen::Server.new, "GET", "/phase3/conflict")
    response.status_code.should eq(409)
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    response.body.should start_with("<!DOCTYPE html>")
    response.body.should contain("<h1>Conflict</h1>")
    response.body.should contain(Shomen::Server::CONFLICT_DETAIL)
    response.body.should_not contain("secret-7")
  end
end
```

- [ ] **Step 3: 失敗を確かめる**

Run: `crystal spec spec/shomen/conflict_spec.cr`
Expected: FAIL。`undefined constant Shomen::Server::CONFLICT_DETAIL` でコンパイルが止まる（定数の参照を消すと 500 が返って落ちる）。

- [ ] **Step 4: 実装する**

`src/shomen/server.cr` の `MAX_FORM_BYTES = 1_048_576` の次の行に足す:

```crystal
  CONFLICT_DETAIL = "This changed after the page was loaded. Reload the page and try again."
```

`respond` の `rescue ex : Shomen::NotFound` 節の後、`rescue ex` の前に足す:

```crystal
  rescue ex : Shomen::Conflict
    error_response(409, "Conflict", CONFLICT_DETAIL)
```

`crystal tool format src/shomen/server.cr` で定数の揃えを直す。

- [ ] **Step 5: 通ることを確かめる**

Run: `crystal spec spec/shomen/conflict_spec.cr`
Expected: PASS（1 example, 0 failures）。`ErrorView` の `html` は `<!DOCTYPE html>` から書き出す（`src/shomen/a11y.cr`）。

- [ ] **Step 6: 全体を確かめる**

Run: `crystal spec && crystal tool format --check && crystal build src/shomen.cr --error-trace && rm -f shomen`
Expected: 0 failures、整形の差分なし、ビルド成功。

---

### Task 7: `examples/hello` の名前変更

**Files:**
- Create: `examples/hello/src/users.cr`
- Modify: `examples/hello/src/hello.cr:1`（require）、`examples/hello/src/hello.cr:138`（起動）
- Modify: `examples/hello/spec/spec_helper.cr`
- Test: `examples/hello/spec/users_spec.cr`

**Interfaces:**
- Consumes: `Shomen::Event`、`Shomen::Command`、`Shomen::Rejected`、`Shomen::Store`、`Shomen::Projection`、`Shomen::Recorded`、`Shomen::NotFound`、Task 6 の 409
- Produces:
  - `Users::STORE : Shomen::Store`、`Users::NAMES : Users::Names`、`Users.stream(user_id : String) : String`（`"user-<id>"`）
  - `Users::UserRenamed`（`user_id : String`、`name : String`、`at : Time`、`event_type "user_renamed"`）、`Users::RenameUser`（コマンド）
  - `Users::Names#find(user_id : String) : Users::Names::Entry?`、`Entry`（`name : String`、`version : Int64`）、`Users::Names#version(user_id : String) : Int64`（名前の無い利用者は 0）。版は最後の改名ではなく、ストリームの最後のイベントの版（最終レビュー後に変更）
  - `Users::Edit`（`GET /users/:id/edit`）、`Users::Rename`（`POST /users/:id`、フィールド `name`、`version`）、`Users::Show`（`GET /users/:id`）

- [ ] **Step 1: spec の支えを変える**

`examples/hello/spec/spec_helper.cr` を次にする:

```crystal
require "spec"
ENV["SHOMEN_SPEC"] = "1"
ENV["SHOMEN_SECRET"] = "spec-secret"
HELLO_DATABASE = File.tempname("hello", ".sqlite3")
ENV["HELLO_DATABASE_URL"] = "sqlite3://#{HELLO_DATABASE}"
require "../src/hello"

Spec.after_suite do
  Users::STORE.close
  [HELLO_DATABASE, "#{HELLO_DATABASE}-wal", "#{HELLO_DATABASE}-shm"].each do |file|
    File.delete(file) if File.exists?(file)
  end
end
```

- [ ] **Step 2: 失敗する spec を書く**

`examples/hello/spec/users_spec.cr`:

```crystal
require "./spec_helper"
require "http/client"

struct UserNoted
  include Shomen::Event
  event_type "spec.user_noted"

  getter at : Time

  def initialize(@at : Time = Time.utc)
  end
end

private def request(server : Shomen::Server, method : String, path : String, cookie : String? = nil, body : String? = nil) : HTTP::Client::Response
  headers = HTTP::Headers.new
  headers["Cookie"] = cookie if cookie
  headers["Content-Type"] = "application/x-www-form-urlencoded" if body
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  server.call(HTTP::Server::Context.new(HTTP::Request.new(method, path, headers, body), response))
  response.close
  HTTP::Client::Response.from_io(IO::Memory.new(io.to_s))
end

private def open_edit(server : Shomen::Server, id : Int64) : {String, String, String}
  response = request(server, "GET", "/users/#{id}/edit")
  cookie = response.headers["Set-Cookie"].split(';').first
  token = response.body.match(/name="_csrf" value="([^"]+)"/).not_nil![1]
  version = response.body.match(/name="version" value="(\d+)"/).not_nil![1]
  {cookie, token, version}
end

private def post_rename(server : Shomen::Server, id : Int64, cookie : String, token : String, version : String, name : String) : HTTP::Client::Response
  body = URI::Params.encode({"_csrf" => token, "version" => version, "name" => name})
  request(server, "POST", "/users/#{id}", cookie, body)
end

private def rename(server : Shomen::Server, id : Int64, name : String) : HTTP::Client::Response
  cookie, token, version = open_edit(server, id)
  post_rename(server, id, cookie, token, version, name)
end

private def rows(id : Int64) : Int32
  Users::STORE.read(after: 0_i64, limit: 10_000).count { |row| row.stream == Users.stream(id.to_s) }
end

describe Users do
  it "shows an empty form at version 0 for a user with no name" do
    response = request(Shomen::Server.new, "GET", "/users/1/edit")
    response.status_code.should eq(200)
    response.body.should contain(%(<input type="hidden" name="version" value="0">))
    response.body.should contain(%(<label for="name">Name</label>))
  end

  it "appends one event row per rename and shows the new name" do
    server = Shomen::Server.new
    response = rename(server, 2_i64, " Ada ")
    response.status_code.should eq(303)
    response.headers["Location"].should eq("/users/2")
    rows(2_i64).should eq(1)
    shown = request(server, "GET", "/users/2")
    shown.status_code.should eq(200)
    shown.body.should contain("<h1>Ada</h1>")
  end

  it "appends a second row when the same rename is sent again" do
    server = Shomen::Server.new
    rename(server, 3_i64, "Ada").status_code.should eq(303)
    rename(server, 3_i64, "Ada").status_code.should eq(303)
    rows(3_i64).should eq(2)
    request(server, "GET", "/users/3/edit").body.should contain(%(name="version" value="2"))
  end

  it "answers a stale form with 409 and adds no row" do
    server = Shomen::Server.new
    cookie, token, version = open_edit(server, 4_i64)
    rename(server, 4_i64, "Ada").status_code.should eq(303)
    response = post_rename(server, 4_i64, cookie, token, version, "Grace")
    response.status_code.should eq(409)
    response.body.should contain("<h1>Conflict</h1>")
    response.body.should_not contain("user-4")
    rows(4_i64).should eq(1)
    request(server, "GET", "/users/4").body.should contain("<h1>Ada</h1>")
  end

  it "redisplays a short name with 422 and adds no row" do
    server = Shomen::Server.new
    response = rename(server, 5_i64, " A")
    response.status_code.should eq(422)
    response.body.should contain(%(value=" A"))
    response.body.should contain("Name must be at least 2 characters")
    rows(5_i64).should eq(0)
  end

  it "returns 404 for a user with no name" do
    request(Shomen::Server.new, "GET", "/users/6").status_code.should eq(404)
  end

  it "answers a negative version with 400 and adds no row" do
    server = Shomen::Server.new
    cookie, token, _ = open_edit(server, 7_i64)
    response = post_rename(server, 7_i64, cookie, token, "-1", "Ada")
    response.status_code.should eq(400)
    response.body.should_not contain("expected_version")
    rows(7_i64).should eq(0)
  end

  it "puts the stream version in the form when another event type follows a rename" do
    server = Shomen::Server.new
    rename(server, 8_i64, "Ada").status_code.should eq(303)
    Users::STORE.append(Users.stream("8"), 1_i64, [UserNoted.new] of Shomen::Event)
    request(server, "GET", "/users/8/edit").body.should contain(%(name="version" value="2"))
    rename(server, 8_i64, "Grace").status_code.should eq(303)
    request(server, "GET", "/users/8").body.should contain("<h1>Grace</h1>")
  end
end
```

- [ ] **Step 3: 失敗を確かめる**

Run: `cd examples/hello && crystal spec spec/users_spec.cr`
Expected: FAIL。`undefined constant Users::STORE` でコンパイルが止まる（`spec_helper.cr` が先に参照する）。

- [ ] **Step 4: 実装する**

`examples/hello/src/users.cr`:

```crystal
module Users
  struct UserRenamed
    include Shomen::Event
    event_type "user_renamed"

    getter user_id : String
    getter name : String
    getter at : Time

    def initialize(@user_id : String, @name : String, @at : Time)
    end
  end

  struct RenameUser
    include Shomen::Command

    getter user_id : String
    getter name : String

    def initialize(@user_id : String, @name : String)
    end

    def call : Array(Shomen::Event) | Shomen::Rejected
      trimmed = name.strip
      return Shomen::Rejected.new(["Name must be at least 2 characters"]) if trimmed.size < 2
      [UserRenamed.new(user_id, trimmed, Time.utc)] of Shomen::Event
    end
  end

  # The version is the stream's, not the last rename's, so a form opened
  # after any event on the stream expects the version the store checks.
  class Names < Shomen::Projection
    record Entry, name : String, version : Int64

    @names = {} of String => String
    @versions = {} of String => Int64

    def find(user_id : String) : Entry?
      if name = @names[user_id]?
        Entry.new(name, version(user_id))
      end
    end

    def version(user_id : String) : Int64
      @versions[user_id]? || 0_i64
    end

    def apply(recorded : Shomen::Recorded) : Nil
      user_id = recorded.stream.lchop?("user-")
      return unless user_id
      @versions[user_id] = recorded.version
      case event = recorded.event
      when UserRenamed
        @names[user_id] = event.name
      end
    end
  end

  STORE = Shomen::Store.new(ENV["HELLO_DATABASE_URL"]? || "sqlite3://./var/shomen.sqlite3")
  NAMES = Names.new(STORE)

  def self.stream(user_id : String) : String
    "user-#{user_id}"
  end

  class EditView < Shomen::View
    def initialize(@user_id : Int64, @name : String, @version : Int64, @token : String, @error : String?)
    end

    def to_html : String
      user_id = @user_id
      name = @name
      version = @version
      token = @token
      error = @error
      html lang: "en" do
        head do
          title "Rename user"
        end
        body do
          main do
            h1 "Rename user #{user_id}"
            if message = error
              p message
            end
            form(action: Users::Rename.path(id: user_id), method: "post") do
              csrf_field(token)
              input(type: "hidden", name: "version", value: version.to_s)
              label("Name", for: "name")
              input(id: "name", name: "name", type: "text", value: name)
              button "Save", type: "submit"
            end
          end
        end
      end
    end
  end

  class ShowView < Shomen::View
    def initialize(@user_id : Int64, @name : String)
    end

    def to_html : String
      user_id = @user_id
      name = @name
      html lang: "en" do
        head do
          title "User"
        end
        body do
          main do
            h1 name
            a "Rename", href: Users::Edit.path(id: user_id)
          end
        end
      end
    end
  end

  class Edit < Shomen::Route
    method GET
    path "/users/:id/edit"

    struct Input
      getter id : Int64

      def initialize(@id : Int64)
      end
    end

    def call(input : Input) : Shomen::Response
      user_id = input.id.to_s
      NAMES.catch_up
      render EditView.new(input.id, NAMES.find(user_id).try(&.name) || "", NAMES.version(user_id), csrf_token, nil)
    end
  end

  class Rename < Shomen::Route
    method POST
    path "/users/:id"

    struct Input
      getter id : Int64
      getter name : String
      getter version : Int64

      def initialize(@id : Int64, @name : String, @version : Int64)
      end
    end

    def call(input : Input) : Shomen::Response
      raise Shomen::BadInput.new("invalid version") if input.version < 0
      result = RenameUser.new(input.id.to_s, input.name).call
      if result.is_a?(Shomen::Rejected)
        return render EditView.new(input.id, input.name, input.version, csrf_token, result.messages.join(" ")), status: 422
      end
      STORE.append(Users.stream(input.id.to_s), input.version, result)
      redirect Show.path(id: input.id)
    end
  end

  class Show < Shomen::Route
    method GET
    path "/users/:id"

    struct Input
      getter id : Int64

      def initialize(@id : Int64)
      end
    end

    def call(input : Input) : Shomen::Response
      entry = NAMES.catch_up.find(input.id.to_s)
      raise Shomen::NotFound.new unless entry
      render ShowView.new(input.id, entry.name)
    end
  end
end
```

`examples/hello/src/hello.cr` の 1 行目 `require "shomen"` の次に足す:

```crystal
require "./users"
```

最後の行 `Shomen::Server.start unless ENV["SHOMEN_SPEC"]?` を次にする:

```crystal
unless ENV["SHOMEN_SPEC"]?
  Users::NAMES.catch_up
  Shomen::Server.start
end
```

- [ ] **Step 5: 通ることを確かめる**

Run: `cd examples/hello && crystal spec`
Expected: PASS（既存の 10 examples に 8 を足した 18 examples, 0 failures。うち 2 つは最終レビュー後に追加）。`value=" A"` の検査が落ちたら、422 の描き直しで入力をどう出しているかを `greeting_spec.cr` の `value="&lt;"` と見比べる。名前はコマンドが `strip` するが、描き直しは送られた値のまま出す。

- [ ] **Step 6: 手動で確かめる（再起動後の復元を含む）**

Run（1 つ目の端末）: `cd examples/hello && rm -rf var && crystal run src/hello.cr`

Run（2 つ目の端末）:

```sh
jar=$(mktemp)
form=$(curl -s -c "$jar" http://127.0.0.1:3000/users/1/edit)
token=$(printf '%s' "$form" | sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p')
curl -s -o /dev/null -w '%{http_code}\n' -b "$jar" --data-urlencode "_csrf=$token" -d version=0 -d name=Ada http://127.0.0.1:3000/users/1
curl -s http://127.0.0.1:3000/users/1 | grep -o '<h1>[^<]*</h1>'
curl -s -o /dev/null -w '%{http_code}\n' -b "$jar" --data-urlencode "_csrf=$token" -d version=0 -d name=Grace http://127.0.0.1:3000/users/1
sqlite3 examples/hello/var/shomen.sqlite3 'SELECT id, stream, version, type FROM events'
```

Expected: `303`、`<h1>Ada</h1>`、`409`、行は `1|user-1|1|user_renamed` の 1 つだけ。1 つ目の端末を Ctrl-C で止めて同じコマンドで起動し直し、`curl -s http://127.0.0.1:3000/users/1 | grep -o '<h1>[^<]*</h1>'` が `<h1>Ada</h1>` を返すことを見る。確認後にサーバを止め、`rm -rf examples/hello/var` と `rm -f "$jar"` で片付ける。

- [ ] **Step 7: 全体を確かめる**

Run: `crystal spec && crystal tool format --check && crystal build src/shomen.cr --error-trace && rm -f shomen && (cd examples/hello && shards install && crystal spec && crystal tool format --check)`
Expected: すべて 0 failures、整形の差分なし。

---

### Task 8: README と最終確認

**Files:**
- Modify: `README.md:7`、`README.md:9-14`（Requirements と依存）、`README.md:76-96`
- Modify: `README.ja.md` の対応する箇所（7 行目、要件と依存、76〜96 行目）

**Interfaces:**
- Consumes: Task 2〜7 の公開 API の名前
- Produces: 文書だけ。コードは変えない

- [ ] **Step 1: README.md を直す**

7 行目を次にする:

```markdown
Version 0.0.0. Phases 1 to 3 are in the tree: typed routes, a typed HTML DSL, an HTTP server, form binding, a signed session cookie, CSRF protection, commands and events, an append-only SQLite event store, and in-memory projections. Later phases are specified and not implemented. There is no release tag yet.
```

Requirements の箇条書きの末尾に足す:

```markdown
- The SQLite 3 library (`libsqlite3`)
```

その下の「The framework shard has no dependencies.」を次にする:

```markdown
The framework shard depends on `sqlite3` and `db` from crystal-lang.
```

「## Phases 1 and 2 are what run」を「## Phases 1 to 3 are what run」にし、「Phase 2 adds these:」の箇条書きの後に足す:

```markdown
Phase 3 adds these:

- `Shomen::Event`: a struct that declares `event_type "name"`. The name goes into the `type` column, so renaming the Crystal type keeps old rows readable. A missing or duplicate name fails at compile time
- `Shomen::Command`: `call` returns `Array(Shomen::Event)` or `Shomen::Rejected` with messages for a 422 form
- `Shomen::Store.new("sqlite3://./var/shomen.sqlite3")`: `append(stream, expected_version, events)` and `read(after:, limit:)`. The file uses WAL. An append at any version other than the stream's current one raises `Shomen::Conflict` and writes nothing. An unhandled conflict is a 409 HTML document
- `Shomen::Projection`: `apply` each event; `catch_up` applies the events after the checkpoint, including events another process appended. Call it before a view reads, and once before `Shomen::Server.start` to rebuild at startup
- `GET /users/:id/edit`, `POST /users/:id`, and `GET /users/:id` in `examples/hello`
```

「These are specified for later phases …」の行を次にする:

```markdown
These are specified for later phases and are not in the code: HTML fragments, JSON responses, the official JavaScript file, SSE, islands, Postgres, and running many identical processes on one database.
```

- [ ] **Step 2: README.ja.md を同じ内容で直す**

7 行目:

```markdown
バージョンは 0.0.0 です。リポジトリに入っているのはフェーズ 3 までで、型付きルート、型付き HTML、HTTP サーバ、フォームの束縛、署名付きセッション Cookie、CSRF 対策、コマンドとイベント、追記のみの SQLite イベントストア、メモリ上のプロジェクションが動きます。それより後のフェーズは仕様にあり、実装はまだありません。リリースタグもまだありません。
```

要件の箇条書きの末尾に足す:

```markdown
- SQLite 3 のライブラリ（`libsqlite3`）
```

その下の「フレームワーク本体の shard に依存パッケージはありません。」を次にする:

```markdown
フレームワーク本体の shard は crystal-lang の `sqlite3` と `db` に依存します。
```

「## いま動くのはフェーズ 1 と 2」を「## いま動くのはフェーズ 1 から 3」にし、「フェーズ 2 で足したもの:」の箇条書きの後に足す:

```markdown
フェーズ 3 で足したもの:

- `Shomen::Event`: `event_type "name"` を宣言する struct。名前は `type` 列に入るので、Crystal の型名を変えても古い行を読めます。名前の書き忘れと重複はコンパイルエラーです
- `Shomen::Command`: `call` は `Array(Shomen::Event)` か、422 のフォームに出すメッセージを持つ `Shomen::Rejected` を返します
- `Shomen::Store.new("sqlite3://./var/shomen.sqlite3")`: `append(stream, expected_version, events)` と `read(after:, limit:)`。ファイルは WAL です。ストリームの現在の版と違う版での追記は、何も書かずに `Shomen::Conflict` を投げます。捕まえなかった衝突は 409 の HTML 文書になります
- `Shomen::Projection`: 各イベントを `apply` します。`catch_up` はチェックポイントより後のイベントを、別のプロセスが追記したものも含めて適用します。ビューが読む前に呼び、起動時の再構築には `Shomen::Server.start` の前に 1 回呼びます
- `examples/hello` の `GET /users/:id/edit`、`POST /users/:id`、`GET /users/:id`
```

96 行目:

```markdown
HTML 断片、JSON 応答、公式 JavaScript、SSE、島、Postgres、1 つの DB の上で同じプロセスを多数動かすことは、後のフェーズの仕様であり、コードにはありません。
```

- [ ] **Step 3: 受入を 1 つずつ確かめる**

Run: `crystal spec && crystal tool format --check && crystal build src/shomen.cr --error-trace && rm -f shomen && (cd examples/hello && shards install && crystal spec) && git status --short`
Expected: 0 failures、警告なし、`git status` に `shomen` や `var/`、`.sqlite3` のファイルが無い。

受入との対応:

| 受入 | 確かめる spec |
|---|---|
| 同じコマンドを 2 回処理すると行が 2 つ | `store_spec.cr` の "appends two rows…"、`users_spec.cr` の "appends a second row…" |
| 再起動後にリードモデルが戻る | `projection_spec.cr` の "rebuilds the read model after a restart"、Task 7 Step 6 |
| 同じ版を期待した 2 つの追記: 片方だけ成功し、片方は `Conflict` で行を足さない | `store_spec.cr` の "…expect the same version" |
| 先走った版の追記は `Conflict` で行を足さない | `store_spec.cr` の "…expected version is ahead" |
| 2 プロセスが 1 つの SQLite に追記でき、片方のプロジェクションがもう片方の追記を見る | `store_concurrency_spec.cr` の "two processes…" |
| 1 プロセスの多数のファイバーが同時に追記できる | `store_concurrency_spec.cr` の "many fibers…" |
| Store は HTML を import しない | `boundary_spec.cr`、`store_worker.cr` のビルド |
| Command、Event、Projection は SQLite を名指ししない | `boundary_spec.cr` |
| 捕まえなかった `Conflict` は 409 HTML | `conflict_spec.cr`、`users_spec.cr` の "stale form" |

- [ ] **Step 4: 停止する**

フェーズ 3 の受入を満たしたら、AGENTS.md と `docs/en/02-PHASES.md` のとおり停止し、ユーザーの次の指示を待つ。commit はユーザーが頼んだときだけ行う。
