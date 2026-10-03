# Phase 8b examples/records on SQLite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** フェーズ 8 の 3 本のサブ計画の 2 本目。備品台帳（登録、貸出、返却）の `examples/records` を SQLite で動かし、フェーズ 8 が挙げる部品ごとに spec を置く。受入「The specs of `examples/records` pass on SQLite … Each part listed above for it has at least one spec」の SQLite の側と「`examples/hello` passes」を満たす。Postgres、2 プロセス、手順書は 8c。

**Architecture:** 備品 1 つが 1 ストリーム `item-<tag>`。コマンドが入力と今の状態を見てイベントを返し、ルートが `Shomen::Store#append` に版を渡して書く。コンシューマ `Items::Ledger` が表 `records_items`（備品 1 行）と `records_loans`（貸出 1 行）を保ち、ページはすべて `Records::LEDGER.read(must_see)` で表を読む。追記したルートは `remember` し、同じセッションの次のページは自分の追記を見る。一覧は検証子つきの GET と SSE、詳細は断片の貸出フォームとキャッシュした貸出履歴、登録フォームは島を持つ。DB の URL、replica の URL、ポートだけを環境変数で読み、8c はソースを変えずに 2 プロセスにする。

**Tech Stack:** Crystal `>= 1.20.0`（開発機は 1.21.1）、`shomen`（`path: ../..`）だけ。標準ライブラリの `spec`、`http`。SQL は `crystal-db` の `DB::Connection` に直接書く。

**Spec:** `docs/en/02-PHASES.md` のフェーズ 8、骨子 `2026-10-01-phase8-overview.md`、API 一覧 `docs/en/04-API.md`。この計画の Task 1 で足す決定:

- `docs/decisions/20261003-phase8-records.md`（D1）

## Global Constraints

- フレームワークに機能を足さない。`src/` は変えない。作業で不具合か仕様との食い違いが見つかったら、直さずにユーザーに報告して止める
- shard を足さない。`examples/records/shard.yml` の依存は `shomen`（`path: ../..`）だけ
- アプリは `docs/en/04-API.md` の Application API に載った型とメソッドだけを呼ぶ。Internal の型と、一覧に無い公開メソッド（`Shomen::Store#using_connection`、`#checkpoint(name)`、`#consume` など）は呼ばない。spec も同じ
- SQL は SQLite と Postgres の両方で動く文だけを書く。パラメータは `$1`、`$2`、… を初出の順に番号付けし、型は `BIGINT` と `TEXT`（`docs/en/00-INSTRUCTION.md` の consumer の節）
- 名前は `docs/en/03-CONVENTIONS.md` に従う。ルートは `Resource::Verb`、ビューは `…View`、コマンドは現在形、イベントは過去形
- テストは固定ポートを bind しない。sleep で同期しない
- コード、識別子、画面の文言は英語。決定ファイルと計画は日本語
- サンプルの部品をフレームワークに置かない。`examples/records` の外で変えてよいのは、Task 1 の文書と Task 8 の CI だけ
- commit しない。タグを作らない（ユーザーが指示したときだけ）

## Review Focus

- 同じタグを 2 回登録する → 2 回目は 422 で「already registered」、イベントは 1 つのまま（Task 4）
- パスに使えないタグ（小文字、`/`、`..`、先頭の `-`）→ path helper の `ArgumentError`（500）ではなく 422 で再表示（Task 4）
- 別の人が貸した後に、前に開いていたフォームで貸す → 409、追記しない、今の状態を見せる（Task 5）
- 台帳に無いタグの詳細と貸出 → 404（Task 4、Task 5）
- 名前と借り手の HTML 特殊文字 → ページでも SSE の断片でもエスケープされる（Task 4、Task 5、Task 6）

## 部品と spec の対応

フェーズ 8 の build 項目が挙げる部品ごとに、少なくとも 1 つの spec を置く。

| 部品 | 使う画面・型 | spec | Task |
|---|---|---|---|
| 型付きルートとパスヘルパ | `Items::Index`、`New`、`Create`、`Show`、`Lend`、`Return`、`Live` | `spec/items_spec.cr` `builds paths from the route declarations` | 4 |
| CSRF 付きのフォーム | 登録、貸出、返却 | `spec/items_spec.cr` `refuses a form without the CSRF token` | 4 |
| コマンドとイベント | `RegisterItem`、`LendItem`、`ReturnItem` / `ItemRegistered`、`ItemLent`、`ItemReturned` | `spec/commands_spec.cr`、`spec/items_spec.cr` `records one item_registered event` | 3、4 |
| コンシューマが表に保つプロジェクション | `Items::Ledger` | `spec/ledger_spec.cr` | 2 |
| `remember` | 登録、貸出、返却の POST | `spec/items_spec.cr` `registers an item and shows it on the next page of the session` | 4 |
| 断片 | 詳細の `div#loan-form` | `spec/loans_spec.cr` `answers a fragment of the loan form with 422` | 5 |
| SSE | 一覧の `div#items-live` → `Items::Live` | `spec/live_spec.cr` | 6 |
| 島 | 登録フォームの `name-length` | `spec/island_spec.cr` | 7 |
| 検証子のある GET ルート | `Items::Index#validator` | `spec/index_spec.cr` | 6 |
| キャッシュした断片 | 詳細の貸出履歴 `div#history` | `spec/loans_spec.cr` `The loan history` | 5 |

## File Map

| ファイル | 役割 | Task |
|---|---|---|
| `docs/decisions/20261003-phase8-records.md`（新規） | D1 | 1 |
| `docs/en/00-INSTRUCTION.md`、`docs/00-INSTRUCTION.md` | 構成に `examples/records/` を足す | 1 |
| `docs/superpowers/plans/2026-10-01-phase8-overview.md` | 8b の行にこの計画のファイル名 | 1 |
| `examples/records/shard.yml`、`shard.lock`、`.gitignore`（新規） | shard | 2 |
| `examples/records/src/records.cr`（新規） | 設定（`Records::STORE`、`LEDGER`、`CACHE`、`port`）と起動 | 2、5、8 |
| `examples/records/src/records/events.cr`（新規） | 3 つのイベント | 2 |
| `examples/records/src/records/ledger.cr`（新規） | `Item`、`Loan`、`Items::Ledger`、表を読む関数 | 2 |
| `examples/records/src/records/commands.cr`（新規） | 3 つのコマンド | 3 |
| `examples/records/src/records/views.cr`（新規） | ビューと断片、島の宣言 | 4、5、6、7 |
| `examples/records/src/records/routes.cr`（新規） | ルート | 4、5、6 |
| `examples/records/src/records/name_length.js`（新規） | 島のモジュール | 7 |
| `examples/records/spec/spec_helper.cr`（新規） | 一時 SQLite、コンシューマの起動と停止、`Visitor`、操作の関数 | 2、4、5 |
| `examples/records/spec/*_spec.cr`（新規） | 上の表のとおり | 2–7 |
| `.github/workflows/ci.yml` | `examples/records` の spec を SQLite で走らせる | 8 |

---

### Task 1: 決定ファイルと文書

**Files:** `docs/decisions/20261003-phase8-records.md`（新規）、`docs/en/00-INSTRUCTION.md`、`docs/00-INSTRUCTION.md`、`docs/superpowers/plans/2026-10-01-phase8-overview.md`

- [ ] **Step 1: D1 を書く**

`docs/decisions/20261003-phase8-records.md`（既存の決定ファイルと同じ 4 節）:

```markdown
# 状況

フェーズ 8 は、業務画面の `examples/records` を作り、フェーズ 1–7 のうちアプリケーションが呼ぶ部品（型付きルートとパスヘルパ、CSRF 付きのフォーム、コマンドとイベント、コンシューマが表に保つプロジェクション、`remember`、断片、SSE、島、検証子のある GET ルート、キャッシュした断片）を使うとした。題材は備品台帳（2026-10-01 にユーザーが選んだ）。イベント、ストリーム、拒否の条件、画面とルート、部品の置き場所、設定を読む環境変数、spec の書き方は決めていない。

# 決定

- 備品はタグで呼ぶ。タグは英大文字か数字で始まり、英大文字、数字、`-` だけからなる 1–20 文字。名前と借り手は前後の空白を除いて 1–80 文字
- 備品 1 つが 1 ストリーム `item-<tag>`。イベントは `ItemRegistered`（`item_registered`、タグ、名前）、`ItemLent`（`item_lent`、タグ、借り手）、`ItemReturned`（`item_returned`、タグ）。どれも `at` を持つ
- コマンドは `RegisterItem`、`LendItem`、`ReturnItem`。`RegisterItem` は形の合わないタグ、名前、登録済みのタグを拒む。`LendItem` は貸出中の備品と形の合わない借り手を、`ReturnItem` は貸出中でない備品を拒む。今の状態はルートが表から読んで渡す
- コンシューマ `Items::Ledger`（名前 `records_ledger`）が表 `records_items`（`tag`、`name`、`borrower`、`version`、`event_id`）と `records_loans`（`event_id`、`tag`、`borrower`、`lent_at`、`returned_at`）を保つ。`version` はストリームの版、`event_id` は備品を最後に変えたイベントの `id`。ページはすべて `read(must_see)` で表を読む
- 登録は版 0 で追記する。貸出と返却は、フォームが運んだ版で追記する。表の版がフォームの版と違えば、コマンドを呼ばず、今の状態のフォームを 409 で返す。表を読んでから追記するまでに別の追記が入れば、`append` の `Shomen::Conflict` が 409 にする
- 追記したルートは `remember` し、303 で詳細に移る
- ルート: `GET /items`（一覧、検証子は表の `MAX(event_id)`）、`GET /items/live`（一覧の SSE）、`GET /items/new`（登録フォーム、島 `name-length`）、`POST /items`（登録）、`GET /items/:tag`（詳細、断片 `div#loan-form`、キャッシュした断片 `div#history`）、`POST /items/:tag/loans`（貸出）、`POST /items/:tag/return`（返却）
- 貸出履歴の断片は、`cached(Records::CACHE, "history", tag, event_id)` で置く。備品が変わると `event_id` が変わり、キーが変わる
- 島 `name-length` は、名前の欄の残りの文字数を見せる。JavaScript が無ければ、数えた行は隠れたまま
- 設定は環境変数 `RECORDS_DATABASE_URL`（既定 `sqlite3://./var/records.sqlite3`）、`RECORDS_REPLICA_URL`（無いか空なら replica なし）、`RECORDS_PORT`（既定 3000）。秘密と本番の設定はフレームワークの `SHOMEN_SECRET`、`SHOMEN_SECRET_VERIFY`、`SHOMEN_ENV`
- 起動は `Records::LEDGER.start`、`Shomen::Server.start(port: Records.port)`、戻ったら `Records::LEDGER.stop`、`Records::STORE.close` の順
- spec は `examples/hello` に合わせ、`Shomen::Server#call` を直接呼ぶ。クッキーを持ち回る `Visitor` を spec に置く。SSE はリポジトリの `spec/support/sse_client.cr`、ブラウザは `spec/support/browser.cr` を使う。spec の DB は一時ファイルの SQLite で、コンシューマは spec の間ずっと動かす

# 理由

台帳は、状態で拒否の条件が変わる（貸出中の備品は貸せない）ので、コマンドとイベントと版の衝突を 1 つの題材で見せられる。一覧と詳細を表から読めば、2 プロセスになっても読み方は変わらない。どのページも `must_see` で読むので、自分の追記は必ず見え、別のプロセスのページでも、クッキーが運んだ `id` まで待つ。

貸出と返却をフォームの版で追記するのは、開いていた画面と違う状態を上書きしないためである。返却のフォームを開いている間に、返却と別の人への貸出が入ったとき、表の版で追記すると、別の人の貸出を返却してしまう。表の版とフォームの版を比べれば、コマンドが見る状態とフォームが見せた状態が同じときだけ追記する。replica が遅れて表の版がフォームより古いときも、409 になり、古い状態で決めない。

一覧の検証子を表の `MAX(event_id)` にすれば、どの備品が変わっても値が変わり、`must_see` まで待った同じ表から読むので、自分の追記の前の一覧を 304 で見せない。

タグをパスに置くので、path helper が拒む文字（`/`、`?`、`#`、`.`、`..`）をタグの形で先に拒む。

島を SSE で置き換える要素の中に置かない（`20260929-phase5-sse-script.md` の既知の制限）ので、島は登録フォームに、SSE は一覧に置く。

# 破棄した案

- 備品の `id` をサーバで連番にする（連番を配る仕組みが要り、2 プロセスで重ならないことを別に保証することになる）
- 登録済みのタグを `Shomen::Conflict` の 409 だけで知らせる（予期した入力の誤りを例外の画面で返すことになる。表で先に確かめ、競合したときだけ 409 にする）
- 貸出と返却を表の版で追記する（開いていたフォームと違う状態を上書きする）
- メモリの `Shomen::Projection` で読む（フェーズ 8 が求めるのは表に保つプロジェクション。2 種類の読み方を混ぜると、どちらがどの画面を支えるかが読みにくくなる）
- SSE の対象を詳細の貸出状態にする（フォームを含む要素は置き換えると入力が消える。8c の 2 プロセスの確認は、別のプロセスで登録した備品が一覧に届くことで見る）
```

- [ ] **Step 2: 構成に `examples/records/` を足す**

`docs/en/00-INSTRUCTION.md` の 81 行目の後に:

```
examples/records/             # business screens, phase 8. Features do not live in the framework
```

`docs/00-INSTRUCTION.md` の 81 行目の後に:

```
examples/records/             # 業務画面（フェーズ 8）。本体に機能を置かない
```

- [ ] **Step 3: 骨子の 8b の行を直す**

`docs/superpowers/plans/2026-10-01-phase8-overview.md` の表の 8b の「サブ計画」列を `` `examples/records` を SQLite で（`2026-10-03-phase8b-records.md`） `` にする。

- [ ] **Step 4: リンクと API 一覧の spec が通ることを確かめる**

Run: `crystal spec spec/shomen/api_list_spec.cr`
Expected: 0 failures

### Task 2: shard、イベント、コンシューマ

**Files:** `examples/records/shard.yml`、`.gitignore`、`shard.lock`（`shards install` が作る）、`src/records.cr`、`src/records/events.cr`、`src/records/ledger.cr`、`spec/spec_helper.cr`、`spec/ledger_spec.cr`（すべて新規、`examples/records/` の下）

**Interfaces:**
- Produces:
  - `Items::ItemRegistered.new(tag : String, name : String, at : Time)`、`Items::ItemLent.new(tag : String, borrower : String, at : Time)`、`Items::ItemReturned.new(tag : String, at : Time)`
  - `record Items::Item, tag : String, name : String, borrower : String?, version : Int64, event_id : Int64`、`#lent? : Bool`
  - `record Items::Loan, borrower : String, lent_at : String, returned_at : String?`
  - `Items.stream(tag : String) : String`、`Items.find(tag : String, seen : Int64) : Item?`、`Items.all(seen : Int64) : Array(Item)`、`Items.loans(tag : String, seen : Int64) : Array(Loan)`、`Items.last_change(seen : Int64) : Int64`
  - `Records::STORE : Shomen::Store`、`Records::LEDGER : Items::Ledger`
  - spec: `RECORDS_DATABASE`、`Records::LEDGER` は spec の間ずっと動く

- [ ] **Step 1: shard を置く**

`examples/records/shard.yml`:

```yaml
name: records
version: 0.0.1
license: MIT
crystal: ">= 1.20.0"

dependencies:
  shomen:
    path: ../..
```

`examples/records/.gitignore`:

```
/lib/
```

Run: `cd examples/records && shards install`
Expected: `shard.lock` ができ、`db`、`pg`、`shomen`、`sqlite3` が入る（`examples/hello/shard.lock` と同じ版）

- [ ] **Step 2: spec を先に書く**

`examples/records/spec/spec_helper.cr`:

```crystal
require "spec"
require "http/client"
ENV["SHOMEN_SPEC"] = "1"
ENV["SHOMEN_SECRET"] = "spec-secret"
RECORDS_DATABASE = File.tempname("records", ".sqlite3")
ENV["RECORDS_DATABASE_URL"] = "sqlite3://#{RECORDS_DATABASE}"
require "../src/records"

# The ledger runs for the whole suite, as it does beside the server.
Records::LEDGER.start

Spec.after_suite do
  Records::LEDGER.stop
  Records::STORE.close
  [RECORDS_DATABASE, "#{RECORDS_DATABASE}-wal", "#{RECORDS_DATABASE}-shm"].each do |file|
    File.delete(file) if File.exists?(file)
  end
end
```

`examples/records/spec/ledger_spec.cr`:

```crystal
require "./spec_helper"

private AT = Time.utc(2026, 10, 3, 9, 0, 0)

private def append(tag : String, version : Int64, event : Shomen::Event) : Int64
  Records::STORE.append(Items.stream(tag), version, [event] of Shomen::Event)
end

describe Items::Ledger do
  it "keeps a row for a registered item" do
    seen = append("C-1", 0_i64, Items::ItemRegistered.new("C-1", "Laptop", AT))
    Items.find("C-1", seen).should eq(Items::Item.new("C-1", "Laptop", nil, 1_i64, seen))
    Items.loans("C-1", seen).should be_empty
  end

  it "keeps the borrower and a loan row for a lend" do
    append("C-2", 0_i64, Items::ItemRegistered.new("C-2", "Laptop", AT))
    seen = append("C-2", 1_i64, Items::ItemLent.new("C-2", "Ada", AT))
    item = Items.find("C-2", seen)
    item.should eq(Items::Item.new("C-2", "Laptop", "Ada", 2_i64, seen))
    item.try(&.lent?).should be_true
    Items.loans("C-2", seen).should eq([Items::Loan.new("Ada", "2026-10-03T09:00:00Z", nil)])
  end

  it "frees the item and closes its loan on a return" do
    append("C-3", 0_i64, Items::ItemRegistered.new("C-3", "Laptop", AT))
    append("C-3", 1_i64, Items::ItemLent.new("C-3", "Ada", AT))
    seen = append("C-3", 2_i64, Items::ItemReturned.new("C-3", AT + 1.hour))
    Items.find("C-3", seen).should eq(Items::Item.new("C-3", "Laptop", nil, 3_i64, seen))
    Items.loans("C-3", seen).should eq([Items::Loan.new("Ada", "2026-10-03T09:00:00Z", "2026-10-03T10:00:00Z")])
  end

  it "lists the items in tag order and changes last_change with each event" do
    first = append("C-5", 0_i64, Items::ItemRegistered.new("C-5", "Camera", AT))
    Items.last_change(first).should eq(first)
    seen = append("C-4", 0_i64, Items::ItemRegistered.new("C-4", "Tripod", AT))
    tags = Items.all(seen).map(&.tag).select(&.in?("C-4", "C-5"))
    tags.should eq(["C-4", "C-5"])
    Items.last_change(seen).should eq(seen)
  end

  it "has a checkpoint at least the id a read waited for" do
    seen = append("C-6", 0_i64, Items::ItemRegistered.new("C-6", "Laptop", AT))
    Items.find("C-6", seen)
    Records::LEDGER.checkpoint.should be >= seen
  end

  it "finds nothing for a tag it has no row for" do
    Items.find("NONE", 0_i64).should be_nil
  end
end
```

- [ ] **Step 3: spec が落ちることを確かめる**

Run: `cd examples/records && crystal spec spec/ledger_spec.cr`
Expected: コンパイルエラー（`can't find file '../src/records'`）

- [ ] **Step 4: イベントを書く**

`examples/records/src/records/events.cr`:

```crystal
module Items
  struct ItemRegistered
    include Shomen::Event
    event_type "item_registered"

    getter tag : String
    getter name : String
    getter at : Time

    def initialize(@tag : String, @name : String, @at : Time)
    end
  end

  struct ItemLent
    include Shomen::Event
    event_type "item_lent"

    getter tag : String
    getter borrower : String
    getter at : Time

    def initialize(@tag : String, @borrower : String, @at : Time)
    end
  end

  struct ItemReturned
    include Shomen::Event
    event_type "item_returned"

    getter tag : String
    getter at : Time

    def initialize(@tag : String, @at : Time)
    end
  end
end
```

- [ ] **Step 5: コンシューマと読む関数を書く**

`examples/records/src/records/ledger.cr`:

```crystal
module Items
  # An item as the ledger keeps it. version is its stream's, and event_id
  # the id of the last event that changed it.
  record Item, tag : String, name : String, borrower : String?, version : Int64, event_id : Int64 do
    def lent? : Bool
      !borrower.nil?
    end
  end

  # One loan, newest first in a history. The times are RFC 3339.
  record Loan, borrower : String, lent_at : String, returned_at : String?

  def self.stream(tag : String) : String
    "item-#{tag}"
  end

  # Keeps records_items, a row per item, and records_loans, a row per
  # loan (docs/decisions/20261003-phase8-records.md).
  class Ledger < Shomen::Consumer
    def name : String
      "records_ledger"
    end

    def create_tables(connection : DB::Connection) : Nil
      connection.exec("CREATE TABLE IF NOT EXISTS records_items (tag TEXT PRIMARY KEY, name TEXT NOT NULL, borrower TEXT, version BIGINT NOT NULL, event_id BIGINT NOT NULL)")
      connection.exec("CREATE TABLE IF NOT EXISTS records_loans (event_id BIGINT PRIMARY KEY, tag TEXT NOT NULL, borrower TEXT NOT NULL, lent_at TEXT NOT NULL, returned_at TEXT)")
    end

    def write(recorded : Shomen::Recorded, connection : DB::Connection) : Nil
      case event = recorded.event
      when ItemRegistered
        connection.exec("INSERT INTO records_items (tag, name, borrower, version, event_id) VALUES ($1, $2, NULL, $3, $4)", event.tag, event.name, recorded.version, recorded.id)
      when ItemLent
        connection.exec("UPDATE records_items SET borrower = $1, version = $2, event_id = $3 WHERE tag = $4", event.borrower, recorded.version, recorded.id, event.tag)
        connection.exec("INSERT INTO records_loans (event_id, tag, borrower, lent_at, returned_at) VALUES ($1, $2, $3, $4, NULL)", recorded.id, event.tag, event.borrower, event.at.to_rfc3339)
      when ItemReturned
        connection.exec("UPDATE records_items SET borrower = NULL, version = $1, event_id = $2 WHERE tag = $3", recorded.version, recorded.id, event.tag)
        connection.exec("UPDATE records_loans SET returned_at = $1 WHERE tag = $2 AND returned_at IS NULL", event.at.to_rfc3339, event.tag)
      end
    end
  end

  # The item once the ledger reached seen, or nil when it has no such tag.
  def self.find(tag : String, seen : Int64) : Item?
    row = Records::LEDGER.read(seen) do |connection|
      connection.query_one?("SELECT tag, name, borrower, version, event_id FROM records_items WHERE tag = $1", tag, as: {String, String, String?, Int64, Int64})
    end
    row.try { |values| Item.new(*values) }
  end

  def self.all(seen : Int64) : Array(Item)
    rows = Records::LEDGER.read(seen) do |connection|
      connection.query_all("SELECT tag, name, borrower, version, event_id FROM records_items ORDER BY tag", as: {String, String, String?, Int64, Int64})
    end
    rows.map { |values| Item.new(*values) }
  end

  def self.loans(tag : String, seen : Int64) : Array(Loan)
    rows = Records::LEDGER.read(seen) do |connection|
      connection.query_all("SELECT borrower, lent_at, returned_at FROM records_loans WHERE tag = $1 ORDER BY event_id DESC", tag, as: {String, String, String?})
    end
    rows.map { |values| Loan.new(*values) }
  end

  # The id of the last event the ledger applied to any item, so it changes
  # with every append the list shows.
  def self.last_change(seen : Int64) : Int64
    Records::LEDGER.read(seen) do |connection|
      connection.scalar("SELECT COALESCE(MAX(event_id), 0) FROM records_items").as(Int64)
    end
  end
end
```

- [ ] **Step 6: 設定を書く**

`examples/records/src/records.cr`（Task 5 と Task 8 で書き足す）:

```crystal
require "shomen"
require "./records/events"
require "./records/ledger"

# Where the application keeps its events and tables. Only these variables
# differ between one process on SQLite and many on Postgres
# (docs/decisions/20261003-phase8-records.md).
module Records
  STORE  = Shomen::Store.new(ENV["RECORDS_DATABASE_URL"]? || "sqlite3://./var/records.sqlite3", replica: ENV["RECORDS_REPLICA_URL"]?.presence)
  LEDGER = Items::Ledger.new(STORE)
end
```

- [ ] **Step 7: spec が通ることを確かめる**

Run: `cd examples/records && crystal spec spec/ledger_spec.cr`
Expected: 6 examples, 0 failures

### Task 3: コマンド

**Files:** `examples/records/src/records/commands.cr`（新規）、`examples/records/src/records.cr`、`examples/records/spec/commands_spec.cr`（新規）

**Interfaces:**
- Consumes: `Items::Item`、3 つのイベント（Task 2）
- Produces:
  - `Items::RegisterItem.new(tag : String, name : String, registered : Bool)`、`TAG_MESSAGE`、`NAME_MESSAGE`、`NAME_LIMIT = 80`
  - `Items::LendItem.new(item : Item, borrower : String)`、`BORROWER_MESSAGE`
  - `Items::ReturnItem.new(item : Item)`
  - どれも `#call : Array(Shomen::Event) | Shomen::Rejected`

- [ ] **Step 1: spec を先に書く**

`examples/records/spec/commands_spec.cr`:

```crystal
require "./spec_helper"

private def available(tag : String) : Items::Item
  Items::Item.new(tag, "Laptop", nil, 1_i64, 1_i64)
end

private def lent(tag : String, borrower : String) : Items::Item
  Items::Item.new(tag, "Laptop", borrower, 2_i64, 2_i64)
end

describe Items::RegisterItem do
  it "registers a trimmed name" do
    events = Items::RegisterItem.new("PC-1", "  Laptop ", false).call.as(Array(Shomen::Event))
    events.size.should eq(1)
    event = events[0].as(Items::ItemRegistered)
    event.tag.should eq("PC-1")
    event.name.should eq("Laptop")
  end

  it "rejects a tag a path cannot carry or that is not capitals, digits, and hyphens" do
    ["", "pc-1", "PC/1", "PC?1", "PC#1", ".", "..", "-PC", "P" * 21].each do |tag|
      Items::RegisterItem.new(tag, "Laptop", false).call.as(Shomen::Rejected).messages.should eq([Items::RegisterItem::TAG_MESSAGE])
    end
    Items::RegisterItem.new("P" * 20, "Laptop", false).call.should be_a(Array(Shomen::Event))
  end

  it "rejects an empty or long name" do
    ["", "   ", "N" * 81].each do |name|
      Items::RegisterItem.new("PC-2", name, false).call.as(Shomen::Rejected).messages.should eq([Items::RegisterItem::NAME_MESSAGE])
    end
  end

  it "rejects a tag the ledger has" do
    Items::RegisterItem.new("PC-3", "Laptop", true).call.as(Shomen::Rejected).messages.should eq(["PC-3 is already registered"])
  end
end

describe Items::LendItem do
  it "lends an available item to a trimmed borrower" do
    event = Items::LendItem.new(available("PC-4"), " Ada ").call.as(Array(Shomen::Event))[0].as(Items::ItemLent)
    event.tag.should eq("PC-4")
    event.borrower.should eq("Ada")
  end

  it "rejects an item that is lent" do
    Items::LendItem.new(lent("PC-5", "Ada"), "Grace").call.as(Shomen::Rejected).messages.should eq(["PC-5 is lent to Ada. Record its return first"])
  end

  it "rejects an empty or long borrower" do
    ["", "  ", "B" * 81].each do |borrower|
      Items::LendItem.new(available("PC-6"), borrower).call.as(Shomen::Rejected).messages.should eq([Items::LendItem::BORROWER_MESSAGE])
    end
  end
end

describe Items::ReturnItem do
  it "returns a lent item" do
    Items::ReturnItem.new(lent("PC-7", "Ada")).call.as(Array(Shomen::Event))[0].as(Items::ItemReturned).tag.should eq("PC-7")
  end

  it "rejects an item that is not lent" do
    Items::ReturnItem.new(available("PC-8")).call.as(Shomen::Rejected).messages.should eq(["PC-8 is not lent"])
  end
end
```

- [ ] **Step 2: spec が落ちることを確かめる**

Run: `cd examples/records && crystal spec spec/commands_spec.cr`
Expected: コンパイルエラー（`undefined constant Items::RegisterItem`）

- [ ] **Step 3: コマンドを書く**

`examples/records/src/records/commands.cr`:

```crystal
module Items
  struct RegisterItem
    include Shomen::Command

    # A path helper refuses /, ?, #, . and .., so a tag cannot hold them.
    TAG          = /\A[A-Z0-9][A-Z0-9-]{0,19}\z/
    TAG_MESSAGE  = "Tag must be 1 to 20 capital letters, digits, or hyphens, and start with a letter or digit"
    NAME_LIMIT   = 80
    NAME_MESSAGE = "Name must be 1 to #{NAME_LIMIT} characters"

    getter tag : String
    getter name : String

    # registered tells whether the ledger has the tag.
    def initialize(@tag : String, @name : String, @registered : Bool)
    end

    def call : Array(Shomen::Event) | Shomen::Rejected
      trimmed = name.strip
      messages = [] of String
      messages << TAG_MESSAGE unless TAG.matches?(tag)
      messages << NAME_MESSAGE unless (1..NAME_LIMIT).includes?(trimmed.size)
      messages << "#{tag} is already registered" if @registered
      return Shomen::Rejected.new(messages) unless messages.empty?
      [ItemRegistered.new(tag, trimmed, Time.utc)] of Shomen::Event
    end
  end

  struct LendItem
    include Shomen::Command

    BORROWER_MESSAGE = "Borrower must be 1 to #{RegisterItem::NAME_LIMIT} characters"

    def initialize(@item : Item, @borrower : String)
    end

    def call : Array(Shomen::Event) | Shomen::Rejected
      if holder = @item.borrower
        return Shomen::Rejected.new(["#{@item.tag} is lent to #{holder}. Record its return first"])
      end
      borrower = @borrower.strip
      return Shomen::Rejected.new([BORROWER_MESSAGE]) unless (1..RegisterItem::NAME_LIMIT).includes?(borrower.size)
      [ItemLent.new(@item.tag, borrower, Time.utc)] of Shomen::Event
    end
  end

  struct ReturnItem
    include Shomen::Command

    def initialize(@item : Item)
    end

    def call : Array(Shomen::Event) | Shomen::Rejected
      return Shomen::Rejected.new(["#{@item.tag} is not lent"]) unless @item.lent?
      [ItemReturned.new(@item.tag, Time.utc)] of Shomen::Event
    end
  end
end
```

`examples/records/src/records.cr` の `require "./records/ledger"` の後に `require "./records/commands"` を足す。

- [ ] **Step 4: spec が通ることを確かめる**

Run: `cd examples/records && crystal spec spec/commands_spec.cr`
Expected: 9 examples, 0 failures

### Task 4: 一覧、登録、詳細

**Files:** `examples/records/src/records/views.cr`（新規）、`examples/records/src/records/routes.cr`（新規）、`examples/records/src/records.cr`、`examples/records/spec/spec_helper.cr`、`examples/records/spec/items_spec.cr`（新規）

**Interfaces:**
- Consumes: `Items.find`、`Items.all`、`Items.stream`、`Records::STORE`（Task 2）、`Items::RegisterItem`（Task 3）
- Produces:
  - ルート `Items::Index`（`GET /items`）、`Items::New`（`GET /items/new`）、`Items::Create`（`POST /items`、入力 `tag`、`name`）、`Items::Show`（`GET /items/:tag`）
  - `Items::ListFragment.new(items : Array(Item))`。根は `div#item-list`、行は `<li><a href="/items/TAG">TAG</a> NAME: available</li>` か `…: lent to BORROWER</li>`
  - `Items::IndexView.new(list : ListFragment)`、`Items::NewView.new(tag : String, name : String, token : String, messages : Array(String))`
  - spec: `Visitor`（`#get(path, headers = HTTP::Headers.new)`、`#post(path, form : Hash(String, String), target : String? = nil)`、`#cookies`、`.token(body)`、`.version(body)`）、`register(visitor, tag, name)`

- [ ] **Step 1: spec の道具を書く**

`examples/records/spec/spec_helper.cr` の末尾に:

```crystal
# A browser without JavaScript: it sends back the cookies the server set,
# so the CSRF token and remember carry from one request to the next.
class Visitor
  getter cookies = HTTP::Cookies.new

  def initialize(@server : Shomen::Server = Shomen::Server.new)
  end

  def get(path : String, headers : HTTP::Headers = HTTP::Headers.new) : HTTP::Client::Response
    request("GET", path, headers, nil)
  end

  # Posts a urlencoded form, with Shomen-Target as shomen.js sends it when
  # target is given.
  def post(path : String, form : Hash(String, String), target : String? = nil) : HTTP::Client::Response
    headers = HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
    headers["Shomen-Target"] = target if target
    request("POST", path, headers, URI::Params.encode(form))
  end

  def self.token(body : String) : String
    match = body.match(/name="_csrf" value="([^"]+)"/) || raise "no _csrf field in #{body}"
    match[1]
  end

  def self.version(body : String) : String
    match = body.match(/name="version" value="(\d+)"/) || raise "no version field in #{body}"
    match[1]
  end

  private def request(method : String, path : String, headers : HTTP::Headers, body : String?) : HTTP::Client::Response
    @cookies.add_request_headers(headers)
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    @server.call(HTTP::Server::Context.new(HTTP::Request.new(method, path, headers, body), response))
    response.close
    result = HTTP::Client::Response.from_io(IO::Memory.new(io.to_s))
    result.cookies.each { |cookie| @cookies << cookie }
    result
  end
end

# Opens the registration form and sends it.
def register(visitor : Visitor, tag : String, name : String) : HTTP::Client::Response
  page = visitor.get(Items::New.path)
  visitor.post(Items::Create.path, {"_csrf" => Visitor.token(page.body), "tag" => tag, "name" => name})
end

def events_of(tag : String) : Array(Shomen::Recorded)
  Records::STORE.read(after: 0_i64, limit: 10_000).select { |recorded| recorded.stream == Items.stream(tag) }
end
```

- [ ] **Step 2: spec を先に書く**

`examples/records/spec/items_spec.cr`:

```crystal
require "./spec_helper"

describe "Registering an item" do
  it "builds paths from the route declarations" do
    Items::Index.path.should eq("/items")
    Items::New.path.should eq("/items/new")
    Items::Create.path.should eq("/items")
    Items::Show.path(tag: "PC-1").should eq("/items/PC-1")
  end

  it "registers an item and shows it on the next page of the session" do
    visitor = Visitor.new
    response = register(visitor, "A-1", " Laptop ")
    response.status_code.should eq(303)
    response.headers["Location"].should eq("/items/A-1")
    visitor.cookies["shomen_append"]?.should_not be_nil
    page = visitor.get("/items/A-1")
    page.status_code.should eq(200)
    page.body.should contain("<h1>A-1 Laptop</h1>")
    page.body.should contain(%(<p id="status">Available</p>))
    visitor.get("/items").body.should contain(%(<li><a href="/items/A-1">A-1</a> Laptop: available</li>))
  end

  it "records one item_registered event at version 1" do
    register(Visitor.new, "A-2", "Projector").status_code.should eq(303)
    events = events_of("A-2")
    events.map(&.event.event_type).should eq(["item_registered"])
    events.map(&.version).should eq([1_i64])
  end

  it "refuses a form without the CSRF token" do
    visitor = Visitor.new
    visitor.get(Items::New.path)
    visitor.post(Items::Create.path, {"tag" => "A-3", "name" => "Laptop"}).status_code.should eq(403)
    events_of("A-3").should be_empty
  end

  it "redisplays a tag a path cannot carry with 422" do
    ["a-4", "A/4", "A?4", "..", "-A4"].each do |tag|
      response = register(Visitor.new, tag, "Laptop")
      response.status_code.should eq(422)
      response.body.should contain(Items::RegisterItem::TAG_MESSAGE)
      response.body.should contain(%(value="#{Shomen::HTML.escape(tag)}"))
    end
  end

  it "redisplays a tag registered before with 422 and records nothing more" do
    visitor = Visitor.new
    register(visitor, "A-5", "Laptop").status_code.should eq(303)
    response = register(visitor, "A-5", "Camera")
    response.status_code.should eq(422)
    response.body.should contain("A-5 is already registered")
    events_of("A-5").size.should eq(1)
  end

  it "escapes the name it shows" do
    visitor = Visitor.new
    register(visitor, "A-6", "<b>Lamp</b>")
    visitor.get("/items/A-6").body.should contain("<h1>A-6 &lt;b&gt;Lamp&lt;/b&gt;</h1>")
  end

  it "answers 404 for a tag the ledger does not have" do
    Visitor.new.get("/items/NONE").status_code.should eq(404)
  end
end
```

- [ ] **Step 3: spec が落ちることを確かめる**

Run: `cd examples/records && crystal spec spec/items_spec.cr`
Expected: コンパイルエラー（`undefined constant Items::New`）

- [ ] **Step 4: ビューを書く**

`examples/records/src/records/views.cr`:

```crystal
module Items
  # The list the index shows, and the stream sends again after an append.
  class ListFragment < Shomen::Fragment
    def initialize(@items : Array(Item))
    end

    def content : Nil
      items = @items
      div(id: "item-list") do
        if items.empty?
          p "No items yet"
        else
          ul do
            items.each do |item|
              li do
                a item.tag, href: Items::Show.path(tag: item.tag)
                text " #{item.name}: "
                text(item.borrower.try { |borrower| "lent to #{borrower}" } || "available")
              end
            end
          end
        end
      end
    end
  end

  class IndexView < Shomen::View
    def initialize(@list : ListFragment)
    end

    def to_html : String
      list = @list
      html lang: "en" do
        head do
          title "Equipment"
          shomen_script
        end
        body do
          main do
            h1 "Equipment"
            a "Register an item", href: Items::New.path
            embed list
          end
        end
      end
    end
  end

  class NewView < Shomen::View
    def initialize(@tag : String, @name : String, @token : String, @messages : Array(String))
    end

    def to_html : String
      tag = @tag
      name = @name
      token = @token
      messages = @messages
      html lang: "en" do
        head do
          title "Register an item"
          shomen_script
        end
        body do
          main do
            h1 "Register an item"
            unless messages.empty?
              div(role: "alert") do
                messages.each { |message| p message }
              end
            end
            form(action: Items::Create.path, method: "post") do
              csrf_field(token)
              label("Tag", for: "tag")
              input(id: "tag", name: "tag", type: "text", value: tag, maxlength: "20")
              label("Name", for: "name")
              input(id: "name", name: "name", type: "text", value: name, maxlength: "80")
              button "Register", type: "submit"
            end
            a "Back to the list", href: Items::Index.path
          end
        end
      end
    end
  end

  class ShowView < Shomen::View
    def initialize(@item : Item)
    end

    def to_html : String
      item = @item
      html lang: "en" do
        head do
          title "Item"
          shomen_script
        end
        body do
          main do
            h1 "#{item.tag} #{item.name}"
            p(item.borrower.try { |borrower| "Lent to #{borrower}" } || "Available", id: "status")
            a "Back to the list", href: Items::Index.path
          end
        end
      end
    end
  end
end
```

- [ ] **Step 5: ルートを書く**

`examples/records/src/records/routes.cr`:

```crystal
module Items
  class Index < Shomen::Route
    method GET
    path "/items"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render IndexView.new(ListFragment.new(Items.all(must_see)))
    end
  end

  class New < Shomen::Route
    method GET
    path "/items/new"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render NewView.new("", "", csrf_token, [] of String)
    end
  end

  class Create < Shomen::Route
    method POST
    path "/items"

    struct Input
      getter tag : String
      getter name : String

      def initialize(@tag : String, @name : String)
      end
    end

    # The ledger tells whether the tag is taken; an append that races
    # another registration of it raises Shomen::Conflict, a 409.
    def call(input : Input) : Shomen::Response
      tag = input.tag.strip
      result = RegisterItem.new(tag, input.name, !Items.find(tag, must_see).nil?).call
      if result.is_a?(Shomen::Rejected)
        return render NewView.new(input.tag, input.name, csrf_token, result.messages), status: 422
      end
      remember Records::STORE.append(Items.stream(tag), 0_i64, result)
      redirect Show.path(tag: tag)
    end
  end

  class Show < Shomen::Route
    method GET
    path "/items/:tag"

    struct Input
      getter tag : String

      def initialize(@tag : String)
      end
    end

    def call(input : Input) : Shomen::Response
      item = Items.find(input.tag, must_see) || raise Shomen::NotFound.new
      render ShowView.new(item)
    end
  end
end
```

`examples/records/src/records.cr` の `require "./records/commands"` の後に:

```crystal
require "./records/views"
require "./records/routes"
```

- [ ] **Step 6: spec が通ることを確かめる**

Run: `cd examples/records && crystal spec`
Expected: 23 examples, 0 failures（ledger 6、commands 9、items 8）

### Task 5: 貸出と返却、断片、キャッシュした履歴

**Files:** `examples/records/src/records/views.cr`、`examples/records/src/records/routes.cr`、`examples/records/src/records.cr`、`examples/records/spec/spec_helper.cr`、`examples/records/spec/loans_spec.cr`（新規）

**Interfaces:**
- Consumes: `Items.find`、`Items.loans`（Task 2）、`Items::LendItem`、`Items::ReturnItem`（Task 3）、`Items::Show`、`Visitor`、`register`、`events_of`（Task 4）
- Produces:
  - ルート `Items::Lend`（`POST /items/:tag/loans`、入力 `tag`、`borrower`、`version`）、`Items::Return`（`POST /items/:tag/return`、入力 `tag`、`version`）
  - `Items::LoanFormFragment.new(item : Item, token : String, borrower : String, error : String?)`。根は `div#loan-form`。状態の行は `p#status`
  - `Items::HistoryFragment.new(loans : Array(Loan))`。根は `div#history`、行は `<li>BORROWER, lent LENT_AT, not returned</li>` か `…, returned RETURNED_AT</li>`
  - `Items::ShowView.new(item : Item, form : LoanFormFragment, history : Shomen::Fragment)`
  - `Records::CACHE : Shomen::FragmentCache`
  - spec: `lend(visitor, tag, borrower, target = nil)`、`give_back(visitor, tag, target = nil)`

- [ ] **Step 1: spec の道具を書く**

`examples/records/spec/spec_helper.cr` の末尾に:

```crystal
# Opens the item page and sends its lend form.
def lend(visitor : Visitor, tag : String, borrower : String, target : String? = nil) : HTTP::Client::Response
  page = visitor.get(Items::Show.path(tag: tag)).body
  form = {"_csrf" => Visitor.token(page), "version" => Visitor.version(page), "borrower" => borrower}
  visitor.post(Items::Lend.path(tag: tag), form, target)
end

# Opens the item page and sends its return form.
def give_back(visitor : Visitor, tag : String, target : String? = nil) : HTTP::Client::Response
  page = visitor.get(Items::Show.path(tag: tag)).body
  form = {"_csrf" => Visitor.token(page), "version" => Visitor.version(page)}
  visitor.post(Items::Return.path(tag: tag), form, target)
end
```

- [ ] **Step 2: spec を先に書く**

`examples/records/spec/loans_spec.cr`:

```crystal
require "./spec_helper"

describe "Lending and returning" do
  it "lends an available item and shows the loan" do
    visitor = Visitor.new
    register(visitor, "L-1", "Laptop")
    response = lend(visitor, "L-1", " Ada ")
    response.status_code.should eq(303)
    response.headers["Location"].should eq("/items/L-1")
    page = visitor.get("/items/L-1").body
    page.should contain(%(<p id="status">Lent to Ada</p>))
    page.should contain(%(<button type="submit" id="return-submit">Record the return</button>))
    page.should match(/<li>Ada, lent [^,<]+, not returned<\/li>/)
    events_of("L-1").map(&.event.event_type).should eq(["item_registered", "item_lent"])
  end

  it "records the return and offers the item again" do
    visitor = Visitor.new
    register(visitor, "L-2", "Laptop")
    lend(visitor, "L-2", "Ada")
    give_back(visitor, "L-2").status_code.should eq(303)
    page = visitor.get("/items/L-2").body
    page.should contain(%(<p id="status">Available</p>))
    page.should match(/<li>Ada, lent [^,<]+, returned [^<]+<\/li>/)
    events_of("L-2").map(&.version).should eq([1_i64, 2_i64, 3_i64])
  end

  it "answers a fragment of the loan form with 422 when the borrower is empty" do
    visitor = Visitor.new
    register(visitor, "L-3", "Laptop")
    response = lend(visitor, "L-3", "  ", target: "loan-form")
    response.status_code.should eq(422)
    response.body.should start_with(%(<div id="loan-form"><p role="alert">#{Items::LendItem::BORROWER_MESSAGE}</p>))
    response.body.should_not contain("<html")
    events_of("L-3").size.should eq(1)
  end

  it "redirects a valid lend sent with or without shomen.js" do
    visitor = Visitor.new
    register(visitor, "L-4", "Laptop")
    lend(visitor, "L-4", "Ada", target: "loan-form").headers["Location"].should eq("/items/L-4")
    give_back(visitor, "L-4").headers["Location"].should eq("/items/L-4")
  end

  it "answers a form opened before another lend with 409, shows the item now, and records nothing" do
    visitor = Visitor.new
    register(visitor, "L-5", "Laptop")
    page = visitor.get("/items/L-5").body
    lend(visitor, "L-5", "Ada").status_code.should eq(303)
    stale = {"_csrf" => Visitor.token(page), "version" => Visitor.version(page), "borrower" => "Grace"}
    response = visitor.post(Items::Lend.path(tag: "L-5"), stale)
    response.status_code.should eq(409)
    response.body.should contain("L-5 changed after this form was shown. Check it and try again.")
    response.body.should contain(%(<p id="status">Lent to Ada</p>))
    events_of("L-5").size.should eq(2)
  end

  it "answers a return sent from a form that offered the item with 409" do
    visitor = Visitor.new
    register(visitor, "L-6", "Laptop")
    lend(visitor, "L-6", "Ada")
    page = visitor.get("/items/L-6").body
    give_back(visitor, "L-6")
    lend(visitor, "L-6", "Grace")
    form = {"_csrf" => Visitor.token(page), "version" => Visitor.version(page)}
    visitor.post(Items::Return.path(tag: "L-6"), form, "loan-form").status_code.should eq(409)
    visitor.get("/items/L-6").body.should contain(%(<p id="status">Lent to Grace</p>))
  end

  it "answers 404 for a lend of a tag the ledger does not have" do
    visitor = Visitor.new
    token = Visitor.token(visitor.get(Items::New.path).body)
    form = {"_csrf" => token, "version" => "0", "borrower" => "Ada"}
    visitor.post(Items::Lend.path(tag: "NONE"), form).status_code.should eq(404)
  end

  it "escapes the borrower" do
    visitor = Visitor.new
    register(visitor, "L-7", "Laptop")
    lend(visitor, "L-7", "<i>Ada</i>")
    visitor.get("/items/L-7").body.should contain(%(<p id="status">Lent to &lt;i&gt;Ada&lt;/i&gt;</p>))
  end
end

describe "The loan history" do
  it "comes from the fragment cache until the item changes" do
    visitor = Visitor.new
    register(visitor, "H-1", "Laptop")
    lend(visitor, "H-1", "Ada")
    visitor.get("/items/H-1").body.should contain("<li>Ada, lent ")
    # A change the ledger did not make: the cached history does not show it.
    Records::LEDGER.read do |connection|
      connection.exec("UPDATE records_loans SET borrower = $1 WHERE tag = $2", "Changed", "H-1")
    end
    visitor.get("/items/H-1").body.should_not contain("<li>Changed, lent ")
    give_back(visitor, "H-1")
    visitor.get("/items/H-1").body.should contain("<li>Changed, lent ")
  end
end
```

- [ ] **Step 3: spec が落ちることを確かめる**

Run: `cd examples/records && crystal spec spec/loans_spec.cr`
Expected: コンパイルエラー（`undefined constant Items::Lend`）

- [ ] **Step 4: 断片と詳細のビューを書く**

`examples/records/src/records/views.cr` の `ShowView` を、次の 3 つのクラスで置き換える:

```crystal
  # The status and the one form that fits it. shomen.js sends the form with
  # Shomen-Target, so a 409 or 422 replaces only this element.
  class LoanFormFragment < Shomen::Fragment
    def initialize(@item : Item, @token : String, @borrower : String, @error : String?)
    end

    def content : Nil
      item = @item
      token = @token
      borrower = @borrower
      error = @error
      div(id: "loan-form") do
        if message = error
          p message, role: "alert"
        end
        if holder = item.borrower
          p "Lent to #{holder}", id: "status"
          form(action: Items::Return.path(tag: item.tag), method: "post", "data-shomen-post": "loan-form") do
            csrf_field(token)
            input(type: "hidden", name: "version", value: item.version.to_s)
            button "Record the return", type: "submit", id: "return-submit"
          end
        else
          p "Available", id: "status"
          form(action: Items::Lend.path(tag: item.tag), method: "post", "data-shomen-post": "loan-form") do
            csrf_field(token)
            input(type: "hidden", name: "version", value: item.version.to_s)
            label("Borrower", for: "borrower")
            input(id: "borrower", name: "borrower", type: "text", value: borrower, maxlength: "80")
            button "Lend", type: "submit", id: "lend-submit"
          end
        end
      end
    end
  end

  class HistoryFragment < Shomen::Fragment
    def initialize(@loans : Array(Loan))
    end

    def content : Nil
      loans = @loans
      div(id: "history") do
        h2 "Loans"
        if loans.empty?
          p "No loans yet"
        else
          ul do
            loans.each do |loan|
              li "#{loan.borrower}, lent #{loan.lent_at}, #{loan.returned_at.try { |at| "returned #{at}" } || "not returned"}"
            end
          end
        end
      end
    end
  end

  class ShowView < Shomen::View
    def initialize(@item : Item, @form : LoanFormFragment, @history : Shomen::Fragment)
    end

    def to_html : String
      item = @item
      form_view = @form
      history = @history
      html lang: "en" do
        head do
          title "Item"
          shomen_script
        end
        body do
          main do
            h1 "#{item.tag} #{item.name}"
            embed form_view
            embed history
            a "Back to the list", href: Items::Index.path
          end
        end
      end
    end
  end
```

- [ ] **Step 5: ルートを書く**

`examples/records/src/records/routes.cr` の `Show` を、次で置き換える:

```crystal
  # The item page, which Show renders and Lend and Return send again with
  # a message. A request from shomen.js gets the loan form alone.
  module ItemPage
    private def item_page(item : Item, error : String? = nil, borrower : String = "", status : Int32 = 200) : Shomen::Response
      form_view = LoanFormFragment.new(item, csrf_token, borrower, error)
      return render_fragment(form_view, status: status) if target
      seen = must_see
      history = cached(Records::CACHE, "history", item.tag, item.event_id) { HistoryFragment.new(Items.loans(item.tag, seen)) }
      render ShowView.new(item, form_view, history), status: status
    end

    private def stale(item : Item) : Shomen::Response
      item_page(item, "#{item.tag} changed after this form was shown. Check it and try again.", status: 409)
    end
  end

  class Show < Shomen::Route
    include ItemPage

    method GET
    path "/items/:tag"

    struct Input
      getter tag : String

      def initialize(@tag : String)
      end
    end

    def call(input : Input) : Shomen::Response
      item = Items.find(input.tag, must_see) || raise Shomen::NotFound.new
      item_page(item)
    end
  end

  # Lends at the version the form showed, so it never lends an item whose
  # state changed after the form was opened.
  class Lend < Shomen::Route
    include ItemPage

    method POST
    path "/items/:tag/loans"

    struct Input
      getter tag : String
      getter borrower : String
      getter version : Int64

      def initialize(@tag : String, @borrower : String, @version : Int64)
      end
    end

    def call(input : Input) : Shomen::Response
      item = Items.find(input.tag, must_see) || raise Shomen::NotFound.new
      return stale(item) unless item.version == input.version
      result = LendItem.new(item, input.borrower).call
      if result.is_a?(Shomen::Rejected)
        return item_page(item, result.messages.join(" "), input.borrower, 422)
      end
      remember Records::STORE.append(Items.stream(item.tag), item.version, result)
      redirect Show.path(tag: item.tag)
    end
  end

  class Return < Shomen::Route
    include ItemPage

    method POST
    path "/items/:tag/return"

    struct Input
      getter tag : String
      getter version : Int64

      def initialize(@tag : String, @version : Int64)
      end
    end

    def call(input : Input) : Shomen::Response
      item = Items.find(input.tag, must_see) || raise Shomen::NotFound.new
      return stale(item) unless item.version == input.version
      result = ReturnItem.new(item).call
      return item_page(item, result.messages.join(" "), status: 422) if result.is_a?(Shomen::Rejected)
      remember Records::STORE.append(Items.stream(item.tag), item.version, result)
      redirect Show.path(tag: item.tag)
    end
  end
```

`examples/records/src/records.cr` の `module Records` の `LEDGER` の後に:

```crystal
  CACHE  = Shomen::FragmentCache.new
```

- [ ] **Step 6: spec が通ることを確かめる**

Run: `cd examples/records && crystal spec`
Expected: 32 examples, 0 failures（items の `<p id="status">Available</p>` も、断片の中の同じ行で通る）

### Task 6: 一覧の検証子と SSE

**Files:** `examples/records/src/records/views.cr`、`examples/records/src/records/routes.cr`、`examples/records/spec/index_spec.cr`（新規）、`examples/records/spec/live_spec.cr`（新規）

**Interfaces:**
- Consumes: `Items.all`、`Items.last_change`（Task 2）、`Items::ListFragment`、`Items::Index`（Task 4）、`lend`（Task 5）
- Produces: `Items::Index#validator`、ルート `Items::Live`（`GET /items/live`）。一覧のページは `<div id="items-live" data-shomen-sse="/items/live">` の中に `div#item-list` を置く

- [ ] **Step 1: spec を先に書く**

`examples/records/spec/index_spec.cr`:

```crystal
require "./spec_helper"

describe "The item list" do
  it "answers 304 to the validator it sent until an item changes" do
    visitor = Visitor.new
    # The session now remembers the latest append, so the ledger has every
    # event before it, and the list stays as it is until this spec appends.
    register(visitor, "X-1", "Laptop")
    first = visitor.get("/items")
    first.status_code.should eq(200)
    etag = first.headers["ETag"]
    etag.should start_with(%(W/"))
    first.headers["Cache-Control"].should eq("private, no-cache")

    again = visitor.get("/items", HTTP::Headers{"If-None-Match" => etag})
    again.status_code.should eq(304)
    again.body.should be_empty

    lend(visitor, "X-1", "Ada")
    changed = visitor.get("/items", HTTP::Headers{"If-None-Match" => etag})
    changed.status_code.should eq(200)
    changed.headers["ETag"].should_not eq(etag)
    changed.body.should contain(%(<a href="/items/X-1">X-1</a> Laptop: lent to Ada</li>))
  end

  it "puts the list in the element the stream replaces" do
    body = Visitor.new.get("/items").body
    body.should contain(%(<div id="items-live" data-shomen-sse="/items/live"><div id="item-list">))
    body.should contain(%(<script src="/shomen.js" defer></script>))
  end
end
```

`examples/records/spec/live_spec.cr`:

```crystal
require "./spec_helper"
require "../../../spec/support/sse_client"

describe "The live item list" do
  it "sends the list again after an item is registered" do
    client = SSEClient.new(Shomen::Server.new, Items::Live.path)
    begin
      client.status.should eq(200)
      client.headers["Content-Type"].should eq("text/event-stream")
      client.next_message.should start_with(%(<div id="item-list">))
      register(Visitor.new, "S-1", "<b>Camera</b>").status_code.should eq(303)
      message = client.next_message
      message = client.next_message until message.includes?("S-1")
      message.should contain(%(<li><a href="/items/S-1">S-1</a> &lt;b&gt;Camera&lt;/b&gt;: available</li>))
    ensure
      client.close
      # The stream ends when it next writes, and the next append makes it
      # write well before its heartbeat.
      register(Visitor.new, "S-2", "Tripod")
      client.wait_finished
    end
  end
end
```

- [ ] **Step 2: spec が落ちることを確かめる**

Run: `cd examples/records && crystal spec spec/index_spec.cr spec/live_spec.cr`
Expected: コンパイルエラー（`undefined constant Items::Live`）

- [ ] **Step 3: 一覧のページにホルダーを置く**

`examples/records/src/records/views.cr` の `IndexView#to_html` の `embed list` を:

```crystal
            # One holder per page; the stream sends the list after each append.
            div(id: "items-live", "data-shomen-sse": Items::Live.path) do
              embed list
            end
```

- [ ] **Step 4: 検証子と SSE のルートを書く**

`examples/records/src/records/routes.cr` の `Index` に、`call` の前に:

```crystal
    # Read from the same table as call, after the same wait, so a session
    # never gets a 304 for a list older than its own append.
    def validator(input : Input) : String
      Items.last_change(must_see).to_s
    end
```

`Index` の後に:

```crystal
  class Live < Shomen::Route
    method GET
    path "/items/live"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      sse(Records::STORE) { ListFragment.new(Items.all(must_see)) }
    end
  end
```

- [ ] **Step 5: spec が通ることを確かめる**

Run: `cd examples/records && crystal spec`
Expected: 35 examples, 0 failures

### Task 7: 島

**Files:** `examples/records/src/records/name_length.js`（新規）、`examples/records/src/records/views.cr`、`examples/records/spec/island_spec.cr`（新規）

**Interfaces:**
- Consumes: `Items::NewView`（Task 4）、`Visitor`（Task 4）
- Produces: `Items::NameLengthIsland`（`GET /islands/name-length.js`）。登録フォームの名前の欄は `div#name-field[data-shomen-island="name-length"]` の中にあり、`p#name-left` は JavaScript が動くまで `hidden`

- [ ] **Step 1: spec を先に書く**

`examples/records/spec/island_spec.cr`:

```crystal
require "./spec_helper"
require "../../../spec/support/browser"

describe "Name length island" do
  it "renders the name field and a hidden count inside the island" do
    body = Visitor.new.get(Items::New.path).body
    body.should contain(
      %(<div data-shomen-island="name-length" id="name-field"><label for="name">Name</label>) +
      %(<input id="name" name="name" type="text" value="" maxlength="80">) +
      %(<p id="name-left" aria-live="polite" hidden="hidden"></p></div>)
    )
  end

  it "serves the island module" do
    response = Visitor.new.get("/islands/name-length.js")
    response.status_code.should eq(200)
    response.headers["Content-Type"].should eq("text/javascript; charset=utf-8")
    response.body.should eq(File.read("src/records/name_length.js"))
    Items::NameLengthIsland.path.should eq("/islands/name-length.js")
  end

  if Browser.executable
    it "counts the characters left in the browser" do
      with_live_server do |origin|
        with_browser do |browser|
          browser.visit("#{origin}/items/new")
          result = browser.run(<<-JS)
            const left = await waitFor(() => {
              const line = document.getElementById("name-left");
              return line.hidden ? undefined : line;
            });
            const name = document.getElementById("name");
            name.value = "Laptop";
            name.dispatchEvent(new Event("input"));
            return left.textContent;
            JS
          result.as_s.should eq("74 characters left")
        end
      end
    end
  else
    pending("counts the characters left in Chrome (set SHOMEN_CHROME to a Chrome or Chromium binary)") { }
  end
end
```

- [ ] **Step 2: spec が落ちることを確かめる**

Run: `cd examples/records && crystal spec spec/island_spec.cr`
Expected: コンパイルエラー（`undefined constant Items::NameLengthIsland`）

- [ ] **Step 3: 島のモジュールを書く**

`examples/records/src/records/name_length.js`:

```js
// The name-length island: how many characters the name field has left.
// The server renders the field and a hidden line; this module fills the
// line, shows it, and keeps it current as the name changes.
export default (island) => {
  const input = island.querySelector("input");
  const left = island.querySelector("p");
  const show = () => {
    left.textContent = `${input.maxLength - input.value.length} characters left`;
  };
  input.addEventListener("input", show);
  show();
  left.hidden = false;
};
```

- [ ] **Step 4: 島を宣言し、名前の欄を島に入れる**

`examples/records/src/records/views.cr` の `module Items` の直後に:

```crystal
  Shomen::Island.script "name-length", "name_length.js"
```

`NewView#to_html` の名前の `label` と `input` を:

```crystal
              # Without JavaScript the count would never change, so it stays
              # hidden until the island runs.
              div("data-shomen-island": "name-length", id: "name-field") do
                label("Name", for: "name")
                input(id: "name", name: "name", type: "text", value: name, maxlength: "80")
                p "", id: "name-left", "aria-live": "polite", hidden: "hidden"
              end
```

- [ ] **Step 5: spec が通ることを確かめる**

Run: `cd examples/records && crystal spec`
Expected: 38 examples, 0 failures（Chrome が無ければ 1 pending）

Run: `cd examples/records && SHOMEN_CHROME=/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome crystal spec spec/island_spec.cr`（手元に Chrome があれば）
Expected: 3 examples, 0 failures

### Task 8: 起動、CI、8b の確認

**Files:** `examples/records/src/records.cr`、`.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `Records::STORE`、`Records::LEDGER`（Task 2）
- Produces: `Records.port : Int32`。8c はこの起動と環境変数だけで 2 プロセスにする

- [ ] **Step 1: 起動を書く**

`examples/records/src/records.cr` の `module Records` の `CACHE` の後に:

```crystal

  def self.port : Int32
    ENV["RECORDS_PORT"]?.try(&.to_i) || 3000
  end
```

ファイルの末尾に:

```crystal

# The ledger starts before the server and stops after it, before the store
# closes (docs/en/00-INSTRUCTION.md, the consumer section).
unless ENV["SHOMEN_SPEC"]?
  Records::LEDGER.start
  Shomen::Server.start(port: Records.port)
  Records::LEDGER.stop
  Records::STORE.close
end
```

- [ ] **Step 2: 1 プロセスで動くことを手で確かめる**

```sh
cd examples/records
out=$(mktemp -d)
crystal build src/records.cr --error-trace -o "$out/records"
RECORDS_PORT=3123 "$out/records" &
pid=$!
until curl -fs http://127.0.0.1:3123/items >/dev/null; do sleep 0.2; done
curl -s http://127.0.0.1:3123/items | grep -c "<h1>Equipment</h1>"
kill -TERM $pid
wait $pid
ls var/records.sqlite3
```

Expected: `1` が出て、プロセスが SIGTERM で終わり、`var/records.sqlite3` ができている（`var/` はリポジトリの `.gitignore` で無視される）。確かめたら `var/` を消す

- [ ] **Step 3: CI に足す**

`.github/workflows/ci.yml` の `examples/hello` のステップの後に:

```yaml
      - name: examples/records
        working-directory: examples/records
        run: |
          shards install
          crystal spec
```

- [ ] **Step 4: 8b の確認**

- [ ] `crystal tool format --check src spec examples/hello/src examples/hello/spec examples/records/src examples/records/spec`
- [ ] `crystal spec`
- [ ] `crystal build src/shomen.cr --error-trace -o /tmp/shomen`
- [ ] `cd examples/hello && shards install && crystal spec`
- [ ] `cd examples/records && shards install && crystal spec`（38 examples、0 failures）
- [ ] `git status` に `examples/records/lib/`、`var/`、バイナリが出ていない
- [ ] 「部品と spec の対応」の表の各行の spec が通っている
- [ ] 骨子の 8b の行の状態を確かめ、8c の計画を書く前にユーザーに報告する
