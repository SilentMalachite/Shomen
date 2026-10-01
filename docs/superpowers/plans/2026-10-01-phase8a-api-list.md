# Phase 8a API List and Version Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** フェーズ 8 の 3 本のサブ計画の最初。`Shomen::` の公開の型とメソッドを `docs/en/04-API.md` と訳に一覧にし、コンパイル時に列挙した公開の型と照合する spec を置き、`shard.yml` と `Shomen::VERSION` を `0.1.0` にする。受入「A spec lists the public types under `Shomen::` at compile time, and fails when one is missing from `04-API.md` or when `04-API.md` names a type that does not exist」を満たす。

**Architecture:** spec がマクロで `Shomen` から定数をたどり、`TypeNode` で `private?` でないものの名前を集める（D1）。`04-API.md` の `### \`Shomen::…\`` 見出しを読み、集めた名前の集合と比べる。英語版と訳は同じ見出しの集合を持つ。一覧は「Application API」と「Internal」に分け、アプリケーションが呼ばない型も Internal に名前と 1 行の役割を載せる。版は `shard.yml` を正本にし、spec が `Shomen::VERSION` と一致することを確かめる（D2）。

**Tech Stack:** Crystal `>= 1.20.0`（開発機は 1.21.1）、標準ライブラリ（`yaml` を含む）だけ。shard は増やさない。

**Spec:** `docs/en/02-PHASES.md` のフェーズ 8、骨子 `2026-10-01-phase8-overview.md`。この計画の Task 1 で足す決定:

- `docs/decisions/20261001-phase8-api-list.md`（D1）
- `docs/decisions/20261001-phase8-version.md`（D2）

## Global Constraints

- フレームワークの機能を足さない。`src/` で変えてよいのは `src/shomen/version.cr` の版だけ。照合で仕様との食い違いが見つかったら、直さずにユーザーに報告する
- shard を足さない
- 型名、メソッド名、コードは英語。`docs/04-API.md` は訳で、見出し（型名）は英語版と同じ文字列
- 仕様を再発明しない。各項目は仕様の節か決定ファイルへのリンクで根拠を示し、そこに無いことを書かない
- テストは固定ポートを bind しない
- タグは作らない。ユーザーが指示するまで commit しない

## Review Focus

- `private` な型（`Shomen::Connections::Entry`）は一覧に載せなくても spec が通る。載せたら失敗する（Task 2）
- 見出しの書式の揺れ（バッククォート無し、`####`、末尾の空白）は型として数えない。数えない見出しで型が欠けたことは、照合の失敗として出る（Task 2）
- 英語版にあって訳に無い型、その逆で失敗する（Task 2）
- リンク先のファイル（`../decisions/…`、`00-INSTRUCTION.md`）が無ければ失敗する（Task 2）
- `shard.yml` の版と `Shomen::VERSION` がずれたら失敗する（Task 3）

## File Map

| ファイル | 役割 | Task |
|---|---|---|
| `docs/decisions/20261001-phase8-api-list.md`、`docs/decisions/20261001-phase8-version.md` | D1、D2 | 1 |
| `docs/en/README.md` | 仕様の目次に `04-API.md` を足す | 1 |
| `spec/shomen/api_list_spec.cr`（新規） | 公開の型と一覧の照合 | 2 |
| `docs/en/04-API.md`、`docs/04-API.md`（新規） | API 一覧と訳 | 2 |
| `shard.yml`、`src/shomen/version.cr`、`spec/shomen_spec.cr` | 版 `0.1.0` | 3 |

---

### Task 1: 決定ファイルと目次

**Files:** `docs/decisions/20261001-phase8-api-list.md`（新規）、`docs/decisions/20261001-phase8-version.md`（新規）、`docs/en/README.md`

- [x] D1 を書く（`# 状況` / `# 決定` / `# 理由` / `# 破棄した案`、既存の決定ファイルと同じ形）。決めること:
  - 照合の対象は、`Shomen` から定数をたどって見つかる `TypeNode` のうち `private?` でないもの全部と、`Shomen` 自身。`lib`（`Shomen::LibSQLite`）、`alias`（`Shomen::StoreAdapter::Row` など）、`enum`（`Shomen::Connections::State`）も型として数える。型でない定数（`VERSION`、`BUILD_ID`、`MAX_BYTES` など）は、それを持つ型の項目に書くが、照合しない
  - 一覧は `## Application API` と `## Internal` の 2 節。型は `### \`Shomen::Name\`` の見出しで 1 つずつ。Application API の型は、アプリケーションが呼ぶ公開のメソッドとマクロを箇条書きにし、各行に仕様の節か決定ファイルへのリンクを付ける。Internal の型は 1 行の役割だけを書き、「アプリケーションは呼ばない。どの版でも変わりうる」と節の冒頭で断る
  - Application API に置く型: `Shomen`、`Shomen::HTML`、`Shomen::View`、`Shomen::Fragment`、`Shomen::FragmentCache`、`Shomen::Route`、`Shomen::Response`、`Shomen::SSE`、`Shomen::Island`、`Shomen::Server`、`Shomen::Store`、`Shomen::Event`、`Shomen::Command`、`Shomen::Recorded`、`Shomen::Rejected`、`Shomen::Projection`、`Shomen::Consumer`、`Shomen::NotFound`、`Shomen::BadInput`、`Shomen::Forbidden`、`Shomen::Conflict`、`Shomen::Unavailable`
  - Internal に置く型: `Shomen::CachedFragment`、`Shomen::ETag`、`Shomen::AppendSignal`、`Shomen::AppendWatcher`、`Shomen::StoreAdapter`、`Shomen::StoreAdapter::Row`、`Shomen::StoreAdapter::Stored`、`Shomen::LibSQLite`、`Shomen::SQLiteAdapter`、`Shomen::PostgresAdapter`、`Shomen::ErrorView`、`Shomen::Session`、`Shomen::SessionStore`、`Shomen::Router`、`Shomen::Router::Entry`、`Shomen::Route::Hooks`、`Shomen::Island::Script`、`Shomen::Island::Script::Input`、`Shomen::Connections`、`Shomen::Connections::State`、`Shomen::Listener`
  - 照合する spec は `spec/shomen/api_list_spec.cr`。英語版と訳の両方を読み、見出しの集合が公開の型の集合と等しいこと、英語版と訳の集合が等しいこと、相対リンクの先のファイルがあることを確かめる。メソッドは照合しない
  - 破棄した案: 公開の型を `:nodoc:` で分ける（マクロから doc コメントを読めない）/ Internal を一覧から外す（受入が「公開の型が一覧に無ければ失敗」なので、外すには型を `private` にする必要があり、別ファイルから使えなくなる）/ `crystal docs` の出力を一覧にする（生成物をリポジトリに置かない）
- [x] D2 を書く。決めること: 版の正本は `shard.yml` の `version`。`Shomen::VERSION` は同じ文字列で、spec が一致を確かめる。フェーズ 8 で `0.1.0` にする。`0.x` の間は、マイナー版で公開 API が変わりうる。タグ（`v0.1.0`）はユーザーが指示したときだけ作る。破棄した案: `Shomen::VERSION` をマクロで `shard.yml` から読む（`src/` に新しい仕組みを足すことになる）
- [x] `docs/en/README.md` の目次に `5. [04-API.md](04-API.md) — the public types and methods, and where each is specified` を足す
- [x] 骨子の 8a の行にこの計画のファイル名が入っていることを確かめる

### Task 2: API 一覧と照合の spec

**Files:** `spec/shomen/api_list_spec.cr`（新規）、`docs/en/04-API.md`（新規）、`docs/04-API.md`（新規）

**Interfaces:**
- Produces: `docs/en/04-API.md` の見出し `### \`Shomen::…\``。8b はこの一覧の Application API に載った型とメソッドだけを `examples/records` で使う

- [x] **Step 1: spec を先に書く**

`spec/shomen/api_list_spec.cr`:

```crystal
require "../spec_helper"

# The public types under Shomen, found at compile time
# (docs/decisions/20261001-phase8-api-list.md).
private def public_types : Set(String)
  {% begin %}
    {% names = ["Shomen"] %}
    {% queue = [Shomen] %}
    {% for type in queue %}
      {% for name in type.constants %}
        {% found = type.constant(name) %}
        {% if found.is_a?(TypeNode) && !found.private? %}
          {% names << found.stringify %}
          {% queue << found %}
        {% end %}
      {% end %}
    {% end %}
    {{names}}.to_set
  {% end %}
end

private HEADING = /\A### `(Shomen(?:::[A-Za-z0-9_]+)*)`\z/

private def listed(path : String) : Set(String)
  File.read_lines(path).compact_map { |line| HEADING.match(line).try(&.[1]) }.to_set
end

private def links(path : String) : Array(String)
  File.read(path).scan(/\]\(([^)#:]+)(?:#[^)]*)?\)/).map(&.[1])
end

describe "docs/en/04-API.md" do
  it "lists every public type under Shomen, and no other" do
    listed("docs/en/04-API.md").should eq(public_types)
  end

  it "has the same types as its Japanese translation" do
    listed("docs/04-API.md").should eq(listed("docs/en/04-API.md"))
  end

  it "links only to files that exist" do
    {"docs/en/04-API.md", "docs/04-API.md"}.each do |path|
      links(path).each do |link|
        File.exists?(File.join(File.dirname(path), link)).should be_true, "#{path} links to #{link}, which does not exist"
      end
    end
  end

  it "does not list a private type" do
    public_types.should_not contain("Shomen::Connections::Entry")
  end
end
```

このマクロは 2026-10-01 に試作で確かめた（Crystal 1.21.1）。集合は 43 個で、`Shomen::Island::Script::Input` のような完全な名前を持ち、`Shomen::Connections::Entry` を含まない。Task 1 の Application API（22 個）と Internal（21 個）を合わせると、この 43 個になる。

- [x] **Step 2: spec が落ちることを確かめる**

Run: `crystal spec spec/shomen/api_list_spec.cr`
Expected: `File::NotFoundError`（`docs/en/04-API.md` が無い）で 3 件が落ち、`does not list a private type` は通る

- [x] **Step 3: `docs/en/04-API.md` を書く**

形:

````markdown
# 04 API

> Canonical text. Japanese translation: [../04-API.md](../04-API.md).

The public types under `Shomen::` and where each is specified. A spec compares the headings below with the public types the compiler finds (`docs/decisions/20261001-phase8-api-list.md`).

## Application API

### `Shomen`

- `Shomen::VERSION` — the shard version ([../decisions/20261001-phase8-version.md](../decisions/20261001-phase8-version.md))
- `Shomen::BUILD_ID` — changes with every compile ([../decisions/20261001-phase7-etag.md](../decisions/20261001-phase7-etag.md))

### `Shomen::Route`

- `method GET` … — …（[00-INSTRUCTION.md](00-INSTRUCTION.md#2-route-declarations)）
…

## Internal

An application does not call these types. They are public only because other files of the framework use them, and they may change in any release.

### `Shomen::AppendSignal`

Wakes waiters in one process after an append.
…
````

- Application API の型ごとに、アプリケーションが呼ぶものを箇条書きにする。集め方: `grep -nE "^\s*(def|macro) " src/shomen/<file>.cr` から `private` と `protected` を除き、`README.md` の「Phases 1 to 7 are what run」と `docs/en/00-INSTRUCTION.md` に名前が出るものを残す。フレームワーク内でしか呼ばないもの（`Shomen::Router.find` など）は載せない
- 各行のリンクは、その名前を決めた `docs/en/00-INSTRUCTION.md` の節（`#2-route-declarations` など GitHub の見出しアンカー）か `docs/decisions/` のファイル。両方あれば決定ファイル
- Internal の型は 1 行の役割だけ。役割は各ファイルの型の上のコメントから取る

- [x] **Step 4: `docs/04-API.md`（訳）を書く**

冒頭は `> 日本語訳です。正本は [docs/en/04-API.md](en/04-API.md) です。食い違ったら英語に合わせ、このファイルを直します。`。見出しは英語版と同じ文字列。リンクは訳のファイルから見た相対パス（`decisions/…`、`00-INSTRUCTION.md`）

- [x] **Step 5: spec が通ることを確かめる**

Run: `crystal spec spec/shomen/api_list_spec.cr`
Expected: 4 examples, 0 failures

- [x] **Step 6: 照合が型の欠けを捕まえることを確かめる**

`docs/en/04-API.md` から `### \`Shomen::Listener\`` の行を一時的に消して `crystal spec spec/shomen/api_list_spec.cr` を走らせ、`lists every public type` と `has the same types` が落ちることを見てから戻す

### Task 3: 版 `0.1.0`

**Files:** `shard.yml`、`src/shomen/version.cr`、`spec/shomen_spec.cr`

- [x] **Step 1: spec を先に書く**

`spec/shomen_spec.cr` の `has a non-empty VERSION` の後に足す:

```crystal
  it "has the version shard.yml declares" do
    Shomen::VERSION.should eq(YAML.parse(File.read("shard.yml"))["version"].as_s)
  end

  it "is version 0.1.0" do
    Shomen::VERSION.should eq("0.1.0")
  end
```

ファイルの先頭で `yaml` を読んでいなければ `require "yaml"` を足す

- [x] **Step 2: spec が落ちることを確かめる**

Run: `crystal spec spec/shomen_spec.cr`
Expected: `is version 0.1.0` が `Expected: "0.1.0" got: "0.0.0"` で落ちる

- [x] **Step 3: 版を上げる**

`shard.yml` の `version: 0.0.0` を `version: 0.1.0` に、`src/shomen/version.cr` の `VERSION = "0.0.0"` を `VERSION = "0.1.0"` にする

- [x] **Step 4: spec が通ることを確かめる**

Run: `crystal spec spec/shomen_spec.cr`
Expected: 0 failures

### Task 4: 8a の確認

- [x] `crystal tool format --check src spec examples`
- [x] `crystal spec`
- [x] `SHOMEN_SPEC_POSTGRES=postgres://… crystal spec`（手元に Postgres があれば。無ければ CI で確かめる）
- [x] `crystal build src/shomen.cr --error-trace -o /tmp/shomen`
- [x] `cd examples/hello && shards install && crystal spec`
- [x] 骨子の 8a の行の状態を確かめ、8b の計画を書く前にユーザーに報告する
