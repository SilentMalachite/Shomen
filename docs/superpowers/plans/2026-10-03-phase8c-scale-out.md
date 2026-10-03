# Phase 8c Scale-out and Closing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** フェーズ 8 の 3 本のサブ計画の最後。`examples/records` の spec を Postgres でも走らせ、2 つのプロセスを 1 つの Postgres DB の上で動かす確認を CI に置き、その手順書 `docs/en/05-SCALE-OUT.md` と訳を書き、README と CONTRIBUTING から指して、フェーズ 8 の受入を満たす。

**Architecture:** `examples/records` のソースは変えない。spec の DB は、`RECORDS_SPEC_POSTGRES` があれば新しい Postgres DB、無ければ一時ファイルの SQLite にする。2 プロセスの確認は、シェルスクリプト `examples/records/scripts/two_processes.sh` が 2 つのプロセス（ポート 3001 と 3002）を立て、Crystal の確認プログラム `bin/check`（`scale_out/check.cr`）が HTTP で「1 つ目で登録した備品が 2 つ目のページと SSE に届く」ことを確かめ、SIGTERM で止めて終了コード 0 を待つ。CI はこのスクリプトを replica の URL なしとあり（primary と同じ URL）で 2 回走らせ、手順書のコードブロックがスクリプトの本文と一致することを spec が照合する。

**Tech Stack:** Crystal `>= 1.20.0`、標準ライブラリの `http/client`、`spec`。POSIX `sh`。GitHub Actions の Postgres 17 サービス。shard は足さない。

**Spec:** `docs/en/02-PHASES.md` のフェーズ 8、骨子 `docs/superpowers/plans/2026-10-01-phase8-overview.md`、`docs/decisions/20261003-phase8-records.md`、`docs/decisions/20261001-phase7-replica-spec.md`。この計画の Task 1 で足す決定:

- `docs/decisions/20261003-phase8-scale-out.md`（D2）

## 2026-10-03 にユーザーが決めたこと

- CI の 2 プロセスの確認では、replica の URL に primary と同じ DB の URL を渡す。遅れは作らない。遅れはフェーズ 7 の spec が確かめている。手順書には、本番では hot standby を 1 台指すと書く
- 手順書と CI のコマンドを同じにするために、スクリプトを 1 つ置いて CI はそれを走らせ、英日の手順書のコードブロックがスクリプトと一致することを spec が照合する。HTTP の確認は Crystal の小さなプログラムが行う

## Global Constraints

- フレームワークに機能を足さない。`src/` は変えない。作業で不具合か仕様との食い違いが見つかったら、直さずにユーザーに報告して止める
- `examples/records/src/` は変えない（受入「with no change to its source. Only environment variables differ」）
- shard を足さない。確認プログラムは標準ライブラリだけを使う
- spec は固定ポートを bind しない。sleep で同期しない。固定ポート 3001 と 3002 を使うのは、spec ではないスクリプトだけ
- 確認プログラムは `examples/records` の型を `require` しない。HTTP だけで話す（別のプロセスを外から見る道具だから）
- コード、識別子、画面とプログラムの出力は英語。決定ファイルと計画は日本語。`docs/en/05-SCALE-OUT.md` が正本で、`docs/05-SCALE-OUT.md` は訳。食い違ったら英語に合わせる
- commit、push、タグはユーザーが指示したときだけ。v0.1.0 のタグと Release は、ユーザーが頼むまで作らない

## Review Focus

- 確認を始めた時点でプロセスがまだ待ち受けていない → 確認は `READY`（60 秒）まで `GET /items` を待ち、間に合わなければ何が答えなかったかを書いて失敗する（Task 3 の spec「fails when a server does not answer in time」）
- 2 つ目の URL が records のプロセスではない（ポートの書き間違い）→ 確認は空振りで通らず、失敗する（Task 3 の spec「fails when the second server is not a records process」）
- SSE を開く前に登録すると、最初のメッセージに備品が入って「届いた」と誤って判定する → 確認は最初のメッセージを読み切ってから登録する（Task 3 の spec「passes when the second server shows what the first registered」で、登録は最初のメッセージの後）
- 手順書だけ、またはスクリプトだけを直す → 照合の spec が落ちる（Task 4 の spec「shows the commands CI runs for two processes, in both languages」）
- `RECORDS_SPEC_POSTGRES` を渡したのに、spec が黙って SQLite で走る → spec が DB の URL の scheme を確かめる（Task 2 の spec「runs on the database the suite made」）

## 受入との対応

| フェーズ 8 の受入 | 満たすもの | Task |
|---|---|---|
| The specs of `examples/records` pass on SQLite, and on Postgres in CI | `RECORDS_SPEC_POSTGRES` と CI の 2 回の `crystal spec` | 2 |
| runs as one process on SQLite and as two processes on Postgres, with and without a replica URL, with no change to its source | 手順書の SQLite の節、CI の 2 プロセスの確認 2 回 | 4 |
| In CI, two processes on one Postgres database: a record posted to one appears on a page served by the other, and reaches an SSE client connected to the other | `TwoProcesses.run` と CI | 3、4 |
| The commands in `05-SCALE-OUT.md` are the ones CI runs for the two-process check | `spec/scale_out_spec.cr` | 4 |
| `examples/hello` passes | 既存の CI の手順 | 6 |
| README and CONTRIBUTING, in English and Japanese, point at `04-API.md`, `05-SCALE-OUT.md`, and `examples/records` | `spec/shomen/readme_spec.cr` | 5 |

8a で満たした受入（API 一覧の spec、版 0.1.0）は Task 6 で緑のままであることを確かめる。

## File Map

| ファイル | 役割 | Task |
|---|---|---|
| `docs/decisions/20261003-phase8-scale-out.md`（新規） | D2 | 1 |
| `docs/superpowers/plans/2026-10-01-phase8-overview.md` | 8c の行にこの計画のファイル名 | 1 |
| `examples/records/spec/spec_helper.cr` | spec の DB を SQLite か Postgres に | 2 |
| `examples/records/spec/database_spec.cr`（新規） | DB の選び方の spec | 2 |
| `.github/workflows/ci.yml` | records の spec を Postgres でも、2 プロセスの確認を 2 回 | 2、4 |
| `examples/records/scale_out/two_processes.cr`（新規） | 確認の本体 `TwoProcesses.run` | 3 |
| `examples/records/scale_out/check.cr`（新規） | `bin/check` の入口 | 3 |
| `examples/records/spec/two_processes_spec.cr`（新規） | 確認の spec | 3 |
| `examples/records/scripts/two_processes.sh`（新規） | 手順書と CI が共有するコマンド | 4 |
| `examples/records/.gitignore` | `/bin/` | 4 |
| `docs/en/05-SCALE-OUT.md`、`docs/05-SCALE-OUT.md`（新規） | 手順書と訳 | 4 |
| `examples/records/spec/scale_out_spec.cr`（新規） | 手順書、スクリプト、CI の照合 | 4 |
| `README.md`、`README.ja.md`、`CONTRIBUTING.md`、`CONTRIBUTING.ja.md` | 3 つを指す。版とフェーズ 8 の記述 | 5 |
| `spec/shomen/readme_spec.cr`（新規） | README と CONTRIBUTING のリンクの spec | 5 |
| `docs/en/02-PHASES.md`、`docs/02-PHASES.md` | 現行フェーズの表示を「受入を満たした」に | 6 |

---

### Task 1: 決定ファイルと骨子

**Files:** `docs/decisions/20261003-phase8-scale-out.md`（新規）、`docs/superpowers/plans/2026-10-01-phase8-overview.md`

**Interfaces:**
- Produces: 後の Task が使う名前。環境変数 `RECORDS_SPEC_POSTGRES`、スクリプト `examples/records/scripts/two_processes.sh`、確認 `bin/check`、モジュール `TwoProcesses`、ポート 3001 と 3002

- [ ] **Step 1: D2 を書く**

`docs/decisions/20261003-phase8-scale-out.md`:

```markdown
# 状況

フェーズ 8 の受入は、`examples/records` の spec が Postgres でも通ること、ソースを変えずに環境変数だけで 1 プロセスの SQLite にも 2 プロセスの Postgres（replica の URL なしとあり）にもなること、CI で 2 プロセスの一方に POST した記録がもう一方のページと SSE に届くこと、`05-SCALE-OUT.md` のコマンドが CI の 2 プロセスの確認と同じであることを求める。spec の DB の選び方、2 プロセスの立て方と確かめ方、手順書と CI を同じに保つ仕組み、replica の URL ありを CI でどう確かめるかは決めていない。2026-10-03 にユーザーは、replica の URL に primary と同じ DB を渡すこと、スクリプトと照合 spec で手順書と CI を同じに保つことを選んだ。

# 決定

- `examples/records` の spec は、`RECORDS_SPEC_POSTGRES` が DB を作れるユーザーの Postgres の URL なら、`records_spec_<16 桁の hex>` という DB を作って走り、終わったら消す。無ければ一時ファイルの SQLite で走る。`SHOMEN_SPEC_POSTGRES` とは別の名前にし、CI は同じ URL を渡して SQLite と Postgres で 1 回ずつ走らせる
- 2 プロセスのコマンドは `examples/records/scripts/two_processes.sh` に置く。`bin/records` と `bin/check` をビルドし、`RECORDS_PORT=3001` と `3002` で 2 つのプロセスを裏で起動し、`bin/check http://127.0.0.1:3001 http://127.0.0.1:3002` を走らせ、両方に SIGTERM を送って終了コード 0 を待つ。DB、replica、鍵は呼ぶ側の環境変数で渡す
- 確認 `bin/check`（`scale_out/check.cr`、本体は `scale_out/two_processes.cr` の `TwoProcesses.run`）は標準ライブラリの HTTP だけで話す。両方の `GET /items` が 200 になるまで最大 60 秒待つ。2 つ目の `/items/live` を開いて最初のメッセージを読み、1 つ目で `TP-<8 桁の hex>` の備品を登録し、1 つ目が付けたクッキーで 2 つ目の詳細と一覧に備品が出ること、開いたストリームに備品が届くことを確かめる。待ちはどれも最大 10 秒。失敗は理由を標準エラーに書いて終了コード 1
- CI は、records の spec の後に、`SHOMEN_ENV=production`、32 バイト以上の `SHOMEN_SECRET`、`RECORDS_DATABASE_URL` をサービスの DB にして、スクリプトを `sh scripts/two_processes.sh` で 2 回走らせる。2 回目は `RECORDS_REPLICA_URL` に primary と同じ URL を渡す
- `docs/en/05-SCALE-OUT.md` と訳は、スクリプトの本文と 1 文字も違わない ` ```sh ` のコードブロックを持つ。`examples/records/spec/scale_out_spec.cr` が、英日の手順書のブロック、スクリプト、`ci.yml` の `run: sh scripts/two_processes.sh` の 2 行を照合する

# 理由

スクリプトを 1 つにすれば、CI が走らせるのは手順書のコマンドそのものになる。照合を spec にすれば、手順書かスクリプトの片方だけを直したときに `crystal spec` が落ちる。Markdown を CI が抜き出して実行する案より、CI の動きが Markdown の書き方に左右されない。

確認を Crystal で書けば、CSRF のトークン、クッキー、SSE を curl と sed で扱うより短く確かで、2 つの HTTP サーバを同じプロセスに立てる spec で確認そのものを試せる。ストリームの最初のメッセージを読み切ってから登録するので、登録前の一覧で「届いた」と判定しない。2 つ目では 1 つ目が付けたクッキーで読むので、ロードバランサの後ろで同じセッションが別のプロセスに回ったときと同じく、`must_see` まで待つ読みと、鍵が両方で同じことを確かめる。

replica に primary と同じ URL を渡すと遅れは無いが、replica の接続で読み、replica のチェックポイントを待つ経路を、ソースを変えずに環境変数だけで通せる。遅れる replica での read-your-writes はフェーズ 7 の spec（`20261001-phase7-replica-spec.md`）が確かめている。本物のストリーミングレプリケーションを CI に組むと、手順書のコマンドも増える。

spec の DB を `SHOMEN_SPEC_POSTGRES` で切り替えると、CI のジョブ全体にそれが設定されているので、CI で SQLite の spec が走らなくなる。

# 破棄した案

- CI で Postgres の hot standby を docker で立てる（CI と手順書のコマンドが長くなる。遅れはフェーズ 7 で確かめた）
- 2 プロセスの確認を replica なしだけにする（受入の「with and without a replica URL」を 2 プロセスで見ない）
- CI が手順書のコードブロックを抜き出して実行する（Markdown の書き方が CI の動きに直結する）
- 確認を curl と sed で書く（CSRF のトークンとクッキーと SSE の扱いが壊れやすく、確認そのものを spec で試せない）
- 2 プロセスで `reuse_port` を使い同じポートを共有する（`examples/records` は `Shomen::Server.start(port:)` だけを呼び、ソースを変えることになる）
```

- [ ] **Step 2: 骨子の 8c の行を直す**

`docs/superpowers/plans/2026-10-01-phase8-overview.md` の表の 8c の「サブ計画」列 `Postgres の 2 プロセス、手順書、締め` を `` Postgres の 2 プロセス、手順書、締め（`2026-10-03-phase8c-scale-out.md`） `` にする。

- [ ] **Step 3: 差分を確かめる**

Run: `git diff --stat`
Expected: 上の 2 ファイルだけ

---

### Task 2: records の spec を Postgres でも走らせる

**Files:**
- Modify: `examples/records/spec/spec_helper.cr:1-18`
- Create: `examples/records/spec/database_spec.cr`
- Modify: `.github/workflows/ci.yml`（`examples/records` の手順）

**Interfaces:**
- Consumes: なし
- Produces: `RecordsSpec::ADMIN : String?`、`RecordsSpec.database_url : String`、`RecordsSpec.drop : Nil`。`ENV["RECORDS_DATABASE_URL"]` は spec の DB を指す

- [ ] **Step 1: 失敗する spec を書く**

`examples/records/spec/database_spec.cr`:

```crystal
require "./spec_helper"

describe "The spec database" do
  it "runs on the database the suite made" do
    url = ENV["RECORDS_DATABASE_URL"]
    if RecordsSpec::ADMIN
      url.should start_with("postgres://")
      url.should contain("/records_spec_")
    else
      url.should start_with("sqlite3://")
    end
  end
end
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `cd examples/records && crystal spec spec/database_spec.cr`
Expected: コンパイルエラー `undefined constant RecordsSpec`

- [ ] **Step 3: spec_helper の DB を選ぶ部分を書き換える**

`examples/records/spec/spec_helper.cr` の 1–18 行（`require "spec"` から `Spec.after_suite` のブロックの終わりまで）を次に置き換える。`Visitor` から下は変えない。

```crystal
require "spec"
require "http/client"
require "db"
require "pg"
require "random/secure"
require "uri"
ENV["SHOMEN_SPEC"] = "1"
ENV["SHOMEN_SECRET"] = "spec-secret"

# The suite runs on a new SQLite file, or, when RECORDS_SPEC_POSTGRES names
# a Postgres server whose user may create databases, on a new database
# there (docs/decisions/20261003-phase8-scale-out.md).
module RecordsSpec
  ADMIN = ENV["RECORDS_SPEC_POSTGRES"]?.presence
  NAME  = "records_spec_#{Random::Secure.hex(8)}"
  FILE  = File.tempname("records", ".sqlite3")

  def self.database_url : String
    if admin = ADMIN
      DB.open(admin) { |db| db.exec("CREATE DATABASE #{NAME}") }
      uri = URI.parse(admin)
      uri.path = "/#{NAME}"
      uri.to_s
    else
      "sqlite3://#{FILE}"
    end
  end

  def self.drop : Nil
    if admin = ADMIN
      DB.open(admin) { |db| db.exec("DROP DATABASE IF EXISTS #{NAME} WITH (FORCE)") }
    else
      [FILE, "#{FILE}-wal", "#{FILE}-shm"].each do |file|
        File.delete(file) if File.exists?(file)
      end
    end
  end
end

ENV["RECORDS_DATABASE_URL"] = RecordsSpec.database_url
require "../src/records"

# The ledger runs for the whole suite, as it does beside the server.
Records::LEDGER.start

Spec.after_suite do
  Records::LEDGER.stop
  Records::STORE.close
  RecordsSpec.drop
end
```

- [ ] **Step 4: SQLite で通ることを確かめる**

Run: `cd examples/records && crystal spec`
Expected: すべて通る（`database_spec` を含む）。終わった後に `ls $TMPDIR | grep records` で一時ファイルが残っていない

- [ ] **Step 5: Postgres で通ることを確かめる**

ローカルに Postgres があれば:

Run: `cd examples/records && RECORDS_SPEC_POSTGRES=postgres://localhost/postgres crystal spec`
Expected: すべて通る。`psql postgres://localhost/postgres -c '\l' | grep records_spec_` が何も出さない（DB が消えている）

ローカルに Postgres が無ければ、このステップは Step 6 の CI で確かめる。Postgres でだけ落ちる spec があれば、`src/` ではなく spec かサンプルの SQL の問題かを調べ、サンプルのソースを直す必要があるならユーザーに報告して止める（Global Constraints）。

- [ ] **Step 6: CI で SQLite と Postgres の両方を走らせる**

`.github/workflows/ci.yml` の `examples/records` の手順を次にする:

```yaml
      - name: examples/records
        working-directory: examples/records
        run: |
          shards install
          crystal spec
          RECORDS_SPEC_POSTGRES="$SHOMEN_SPEC_POSTGRES" crystal spec
```

- [ ] **Step 7: 書式を確かめる**

Run: `crystal tool format --check src spec examples`
Expected: 出力なし

---

### Task 3: 2 プロセスの確認プログラム

**Files:**
- Create: `examples/records/scale_out/two_processes.cr`
- Create: `examples/records/scale_out/check.cr`
- Test: `examples/records/spec/two_processes_spec.cr`

**Interfaces:**
- Consumes: 起動中の records の HTTP（`GET /items`、`GET /items/new`、`POST /items`、`GET /items/:tag`、`GET /items/live`）。`with_live_server(& : String ->)`（`spec/support/browser.cr`、origin `http://127.0.0.1:<port>` を渡す）
- Produces: `TwoProcesses.run(first : URI, second : URI, tag : String = TwoProcesses.new_tag, ready_within : Time::Span = TwoProcesses::READY) : Nil`、失敗で `TwoProcesses::Failed`。実行ファイル `bin/check FIRST_ORIGIN SECOND_ORIGIN`（成功で 0、失敗で 1）

- [ ] **Step 1: 失敗する spec を書く**

`examples/records/spec/two_processes_spec.cr`:

```crystal
require "./spec_helper"
require "socket"
require "../../../spec/support/browser"
require "../scale_out/two_processes"

# Answers every request with the same HTML page, as another application
# on the port would.
private def with_other_server(& : String ->) : Nil
  server = HTTP::Server.new do |context|
    context.response.content_type = "text/html"
    context.response.print "<p>other</p>"
  end
  address = server.bind_tcp("127.0.0.1", 0)
  spawn { server.listen }
  begin
    yield "http://127.0.0.1:#{address.port}"
  ensure
    server.close
  end
end

# A port on 127.0.0.1 that nothing listens on.
private def closed_port : Int32
  server = TCPServer.new("127.0.0.1", 0)
  port = server.local_address.port
  server.close
  port
end

describe TwoProcesses do
  it "passes when the second server shows what the first registered" do
    with_live_server do |first|
      with_live_server do |second|
        TwoProcesses.run(URI.parse(first), URI.parse(second), "TP-SPEC1")
      end
    end
    Items.find("TP-SPEC1", 0_i64).should_not be_nil
  end

  it "fails when the second server is not a records process" do
    with_live_server do |first|
      with_other_server do |second|
        expect_raises(TwoProcesses::Failed, "did not answer an event stream") do
          TwoProcesses.run(URI.parse(first), URI.parse(second), "TP-SPEC2")
        end
      end
    end
  end

  it "fails when a server does not answer in time" do
    with_live_server do |first|
      second = URI.parse("http://127.0.0.1:#{closed_port}")
      expect_raises(TwoProcesses::Failed, "did not answer GET /items with 200 within") do
        TwoProcesses.run(URI.parse(first), second, "TP-SPEC3", ready_within: 300.milliseconds)
      end
    end
  end

  it "makes tags the registration form accepts" do
    TwoProcesses.new_tag.should match(/\ATP-[0-9A-F]{8}\z/)
  end
end
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `cd examples/records && crystal spec spec/two_processes_spec.cr`
Expected: コンパイルエラー（`../scale_out/two_processes` が無い）

- [ ] **Step 3: 確認の本体を書く**

`examples/records/scale_out/two_processes.cr`:

```crystal
require "http/client"
require "random/secure"
require "uri"

# Checks two examples/records processes on one database: an item
# registered through the first appears on the pages the second serves,
# with the session the first started, and reaches an SSE client connected
# to the second (docs/en/05-SCALE-OUT.md). It speaks HTTP only.
module TwoProcesses
  READY = 60.seconds
  WAIT  = 10.seconds

  class Failed < Exception
  end

  def self.new_tag : String
    "TP-#{Random::Secure.hex(4).upcase}"
  end

  # Raises Failed with what did not hold.
  def self.run(first : URI, second : URI, tag : String = new_tag, ready_within : Time::Span = READY) : Nil
    ready(first, ready_within)
    ready(second, ready_within)
    client = HTTP::Client.new(second)
    client.read_timeout = WAIT
    client.get("/items/live") do |stream|
      unless stream.status_code == 200 && stream.headers["Content-Type"]? == "text/event-stream"
        raise Failed.new("GET #{second}/items/live did not answer an event stream")
      end
      # The list as it is now, so the stream is open before the append.
      skip_message(stream.body_io, second)
      cookies = register(first, tag)
      show(second, "/items/#{tag}", cookies, "<h1>#{tag} ")
      show(second, "/items", cookies, %(href="/items/#{tag}"))
      unless sent?(stream.body_io, %(href="/items/#{tag}"))
        raise Failed.new("the stream from #{second} did not send #{tag} within #{WAIT}")
      end
    end
  rescue error : IO::TimeoutError
    raise Failed.new("no answer within #{WAIT}: #{error.message}")
  ensure
    client.try &.close
  end

  private def self.ready(origin : URI, within : Time::Span) : Nil
    deadline = Time.instant + within
    loop do
      begin
        return if HTTP::Client.get(origin.resolve("/items")).status_code == 200
      rescue Socket::Error | IO::Error
      end
      raise Failed.new("#{origin} did not answer GET /items with 200 within #{within}") if Time.instant > deadline
      sleep 100.milliseconds
    end
  end

  private def self.skip_message(io : IO, origin : URI) : Nil
    while line = io.gets(chomp: true)
      return if line.empty?
    end
    raise Failed.new("the stream from #{origin} ended before its first message")
  end

  private def self.sent?(io : IO, text : String) : Bool
    deadline = Time.instant + WAIT
    while Time.instant < deadline && (line = io.gets(chomp: true))
      return true if line.includes?(text)
    end
    false
  end

  private def self.register(origin : URI, tag : String) : HTTP::Cookies
    cookies = HTTP::Cookies.new
    page = request(origin, "GET", "/items/new", cookies)
    token = page.body.match(/name="_csrf" value="([^"]+)"/).try(&.[1])
    raise Failed.new("GET #{origin}/items/new has no _csrf field") unless token
    form = URI::Params.encode({"_csrf" => token, "tag" => tag, "name" => "Two-process check"})
    response = request(origin, "POST", "/items", cookies, form)
    unless response.status_code == 303 && response.headers["Location"]? == "/items/#{tag}"
      raise Failed.new("POST #{origin}/items answered #{response.status_code}, not 303 to /items/#{tag}")
    end
    cookies
  end

  private def self.show(origin : URI, path : String, cookies : HTTP::Cookies, text : String) : Nil
    response = request(origin, "GET", path, cookies)
    unless response.status_code == 200 && response.body.includes?(text)
      raise Failed.new("GET #{origin}#{path} answered #{response.status_code} without #{text}")
    end
  end

  # Sends the cookies and keeps the ones the response sets.
  private def self.request(origin : URI, method : String, path : String, cookies : HTTP::Cookies, form : String? = nil) : HTTP::Client::Response
    headers = HTTP::Headers.new
    headers["Content-Type"] = "application/x-www-form-urlencoded" if form
    cookies.add_request_headers(headers)
    client = HTTP::Client.new(origin)
    client.read_timeout = WAIT
    response = client.exec(method, path, headers, form)
    response.cookies.each { |cookie| cookies << cookie }
    response
  ensure
    client.try &.close
  end
end
```

- [ ] **Step 4: 入口を書く**

`examples/records/scale_out/check.cr`:

```crystal
require "./two_processes"

# bin/check FIRST_ORIGIN SECOND_ORIGIN, as docs/en/05-SCALE-OUT.md runs it.
abort "usage: bin/check FIRST_ORIGIN SECOND_ORIGIN" unless ARGV.size == 2
first = URI.parse(ARGV[0])
second = URI.parse(ARGV[1])
begin
  TwoProcesses.run(first, second)
  puts "two processes: an item registered through #{first} reached the pages and the stream of #{second}"
rescue error : TwoProcesses::Failed
  abort "two processes: #{error.message}"
end
```

- [ ] **Step 5: spec が通ることを確かめる**

Run: `cd examples/records && crystal spec spec/two_processes_spec.cr`
Expected: 4 examples, 0 failures

Run: `cd examples/records && crystal build scale_out/check.cr -o /tmp/check && /tmp/check; echo $?`
Expected: `usage: bin/check FIRST_ORIGIN SECOND_ORIGIN` と `1`

- [ ] **Step 6: 全体と書式を確かめる**

Run: `cd examples/records && crystal spec && cd ../.. && crystal tool format --check src spec examples`
Expected: すべて通る。書式の出力なし

---

### Task 4: スクリプト、手順書、照合の spec、CI

**Files:**
- Create: `examples/records/scripts/two_processes.sh`
- Modify: `examples/records/.gitignore`
- Create: `docs/en/05-SCALE-OUT.md`、`docs/05-SCALE-OUT.md`
- Test: `examples/records/spec/scale_out_spec.cr`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `scale_out/check.cr`（Task 3）、`examples/records/src/records.cr` の `RECORDS_DATABASE_URL`、`RECORDS_REPLICA_URL`、`RECORDS_PORT`
- Produces: `sh scripts/two_processes.sh`（`examples/records` で走らせる。成功で 0）

- [ ] **Step 1: 失敗する spec を書く**

`examples/records/spec/scale_out_spec.cr`:

```crystal
require "./spec_helper"

private SCRIPT = "scripts/two_processes.sh"
private DOCS   = {"../../docs/en/05-SCALE-OUT.md", "../../docs/05-SCALE-OUT.md"}
private CI     = "../../.github/workflows/ci.yml"

# The bodies of the ```sh blocks in a Markdown file.
private def shell_blocks(path : String) : Array(String)
  blocks = [] of String
  current = nil
  File.each_line(path) do |line|
    if body = current
      if line == "```"
        blocks << body.to_s
        current = nil
      else
        body << line << '\n'
      end
    elsif line == "```sh"
      current = String::Builder.new
    end
  end
  blocks
end

private def links(path : String) : Array(String)
  File.read(path).scan(/\]\(([^)#:]+)(?:#[^)]*)?\)/).map(&.[1])
end

describe "docs/en/05-SCALE-OUT.md" do
  it "shows the commands CI runs for two processes, in both languages" do
    script = File.read(SCRIPT)
    DOCS.each do |path|
      shell_blocks(path).should contain(script), "#{path} has no sh block equal to #{SCRIPT}"
    end
  end

  it "is what CI runs, without and with a replica URL" do
    lines = File.read_lines(CI).map(&.strip)
    lines.count("run: sh #{SCRIPT}").should eq(2)
    lines.count(&.starts_with?("RECORDS_REPLICA_URL:")).should eq(1)
  end

  it "names the variables CI sets for the two processes" do
    ci = File.read(CI)
    {"RECORDS_DATABASE_URL", "RECORDS_REPLICA_URL", "SHOMEN_SECRET", "SHOMEN_ENV"}.each do |name|
      ci.should contain("#{name}:")
      DOCS.each { |path| File.read(path).should contain("`#{name}`") }
    end
  end

  it "links only to files that exist" do
    DOCS.each do |path|
      links(path).each do |link|
        File.exists?(File.join(File.dirname(path), link)).should be_true, "#{path} links to #{link}, which does not exist"
      end
    end
  end
end
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `cd examples/records && crystal spec spec/scale_out_spec.cr`
Expected: 4 failures（ファイルが無い `File::NotFoundError`）

- [ ] **Step 3: スクリプトを書く**

`examples/records/scripts/two_processes.sh`（実行ビットは要らない。`sh` で走らせる。手順書と 1 文字も違えないので、コメントを書かない）:

```sh
set -eu
mkdir -p bin
crystal build src/records.cr -o bin/records
crystal build scale_out/check.cr -o bin/check
RECORDS_PORT=3001 bin/records &
first=$!
RECORDS_PORT=3002 bin/records &
second=$!
trap 'kill "$first" "$second" 2>/dev/null || true' EXIT
bin/check http://127.0.0.1:3001 http://127.0.0.1:3002
kill -TERM "$first" "$second"
wait "$first"
wait "$second"
trap - EXIT
```

`examples/records/.gitignore` に 1 行足す:

```
/bin/
```

- [ ] **Step 4: スクリプトを SQLite の 2 プロセスで確かめる**

2 つのプロセスは 1 つの SQLite ファイルでも動く（SQLite は通知が無く、ポーリングで起きる）。Postgres が無くてもスクリプトと確認を試せる。

Run:

```sh
cd examples/records
RECORDS_DATABASE_URL="sqlite3://$(mktemp -d)/two.sqlite3" SHOMEN_SECRET=local-two-processes-secret-0123456789 sh scripts/two_processes.sh; echo "exit $?"
```

Expected: `two processes: an item registered through http://127.0.0.1:3001 reached the pages and the stream of http://127.0.0.1:3002`、各プロセスの `shomen: shutting down`、`exit 0`。SSE が届くのに Store のポーリング間隔（既定 5 秒）までかかることがあるが、`WAIT`（10 秒）の内に収まる

終了コードが 0 でなければ、どのコマンドで止まったかを見る。SIGTERM の後に `bin/records` が 0 以外で終わるなら、`src/` の不具合の可能性があるので、直さずにユーザーに報告して止める。

`git status --short examples/records` に `bin/` が出ないことを確かめる。

- [ ] **Step 5: 英語の手順書を書く**

`docs/en/05-SCALE-OUT.md`（4 つ目のコードブロックは `scripts/two_processes.sh` と同じ本文にする）:

````markdown
# 05 Scale out

> Canonical text. Japanese translation: [../05-SCALE-OUT.md](../05-SCALE-OUT.md).

These steps take [`examples/records`](../../examples/records) from one process on SQLite to two processes on one Postgres database, first without a replica and then with one. Only environment variables change. The source stays the same. Run every command from `examples/records`.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `RECORDS_DATABASE_URL` | `sqlite3://./var/records.sqlite3` | The primary database, `sqlite3://…` or `postgres://…` |
| `RECORDS_REPLICA_URL` | none | A Postgres replica for reads. Unset or empty means no replica |
| `RECORDS_PORT` | `3000` | The port on 127.0.0.1, from 1 to 65535 |
| `SHOMEN_SECRET` | a random secret until restart | Signs the session cookie and the CSRF token. Every process needs the same value |
| `SHOMEN_ENV` | none | `production` requires a `SHOMEN_SECRET` of at least 32 bytes and hides exception messages |

## One process on SQLite

```sh
shards install
mkdir -p var
crystal run src/records.cr
```

Open <http://127.0.0.1:3000/items>. Ctrl-C stops it: the server finishes the requests in progress, then the ledger stops and the store closes.

## Two processes on Postgres

You need a Postgres server (CI uses Postgres 17) and an existing database whose user may create tables. Both processes use the same database and the same secret:

```sh
export RECORDS_DATABASE_URL=postgres://localhost/records
export SHOMEN_ENV=production
export SHOMEN_SECRET="$(openssl rand -hex 32)"
```

Then run these commands. CI runs them as they are, from [`scripts/two_processes.sh`](../../examples/records/scripts/two_processes.sh):

```sh
set -eu
mkdir -p bin
crystal build src/records.cr -o bin/records
crystal build scale_out/check.cr -o bin/check
RECORDS_PORT=3001 bin/records &
first=$!
RECORDS_PORT=3002 bin/records &
second=$!
trap 'kill "$first" "$second" 2>/dev/null || true' EXIT
bin/check http://127.0.0.1:3001 http://127.0.0.1:3002
kill -TERM "$first" "$second"
wait "$first"
wait "$second"
trap - EXIT
```

They build the application and the check, and start two processes on ports 3001 and 3002. `bin/check` waits until both answer `GET /items`. It opens the item stream of the second process, registers an item through the first, and checks that the second shows it: on the item page and the list, with the session cookies the first set, and on the open stream. Then both processes get SIGTERM, finish, and exit with status 0. A failure stops the commands with a nonzero status.

Each process runs the ledger consumer. A batch commits its rows and the checkpoint together, so each event is applied once, by whichever process reaches it first. An append in either process notifies the other, and its streams wake. The session cookie carries the id of the session's last append, so a page served by the other process waits until the ledger has reached it.

In production, put a load balancer in front of the processes and give them all the same `SHOMEN_SECRET`. To change the secret, see `SHOMEN_SECRET_VERIFY` in [00-INSTRUCTION.md](00-INSTRUCTION.md).

## With a replica

Point `RECORDS_REPLICA_URL` at one hot standby of the primary, and run the same commands:

```sh
export RECORDS_REPLICA_URL=postgres://replica.example/records
```

Pages and streams read the replica once it has reached the session's last append, and the primary when it has not within 2 seconds. Appends, consumer batches, and notifications stay on the primary. Shomen creates nothing on the replica: the ledger's tables reach it by replication. The URL must name one standby, not a pool that spreads connections over several.

CI sets `RECORDS_REPLICA_URL` to the primary's own URL. That shows the processes start and serve with a replica URL and no change to the source. A replica that lags is checked by the phase 7 specs ([decision](../decisions/20261001-phase7-replica-spec.md)).
````

- [ ] **Step 6: 日本語訳を書く**

`docs/05-SCALE-OUT.md`（コードブロックは英語版と同じ本文）:

````markdown
# 05 スケールアウト

> 日本語訳です。正本は [docs/en/05-SCALE-OUT.md](en/05-SCALE-OUT.md) です。食い違ったら英語に合わせ、このファイルを直します。

この手順で、[`examples/records`](../examples/records) を、SQLite の 1 プロセスから、1 つの Postgres DB の上の 2 プロセスにします。まず replica なしで、次に replica ありで動かします。変えるのは環境変数だけで、ソースは同じです。コマンドはどれも `examples/records` で実行します。

## 環境変数

| 変数 | 既定 | 意味 |
|---|---|---|
| `RECORDS_DATABASE_URL` | `sqlite3://./var/records.sqlite3` | primary の DB。`sqlite3://…` か `postgres://…` |
| `RECORDS_REPLICA_URL` | なし | 読みに使う Postgres の replica。無いか空なら replica なし |
| `RECORDS_PORT` | `3000` | 127.0.0.1 のポート。1 から 65535 |
| `SHOMEN_SECRET` | 再起動までの乱数の鍵 | セッションのクッキーと CSRF トークンに署名する。すべてのプロセスで同じ値にする |
| `SHOMEN_ENV` | なし | `production` なら、32 バイト以上の `SHOMEN_SECRET` を求め、例外のメッセージを隠す |

## SQLite の 1 プロセス

```sh
shards install
mkdir -p var
crystal run src/records.cr
```

<http://127.0.0.1:3000/items> を開きます。Ctrl-C で止まります。サーバは処理中の要求を終え、台帳のコンシューマが止まり、Store が閉じます。

## Postgres の 2 プロセス

Postgres のサーバ（CI は Postgres 17）と、表を作れるユーザーの既存の DB が要ります。2 つのプロセスは同じ DB と同じ鍵を使います。

```sh
export RECORDS_DATABASE_URL=postgres://localhost/records
export SHOMEN_ENV=production
export SHOMEN_SECRET="$(openssl rand -hex 32)"
```

次のコマンドを実行します。CI は [`scripts/two_processes.sh`](../examples/records/scripts/two_processes.sh) から、これをそのまま走らせます。

```sh
set -eu
mkdir -p bin
crystal build src/records.cr -o bin/records
crystal build scale_out/check.cr -o bin/check
RECORDS_PORT=3001 bin/records &
first=$!
RECORDS_PORT=3002 bin/records &
second=$!
trap 'kill "$first" "$second" 2>/dev/null || true' EXIT
bin/check http://127.0.0.1:3001 http://127.0.0.1:3002
kill -TERM "$first" "$second"
wait "$first"
wait "$second"
trap - EXIT
```

アプリと確認をビルドし、ポート 3001 と 3002 で 2 つのプロセスを起動します。`bin/check` は、両方が `GET /items` に答えるまで待ちます。2 つ目のプロセスの一覧のストリームを開き、1 つ目で備品を登録し、2 つ目がそれを見せることを確かめます。詳細と一覧は 1 つ目が付けたセッションのクッキーで読み、開いたストリームにも届くことを見ます。その後、両方のプロセスに SIGTERM を送り、処理を終えて終了コード 0 で終わるのを待ちます。どこかで失敗すれば、0 以外の終了コードで止まります。

どちらのプロセスも台帳のコンシューマを動かします。バッチは表の行とチェックポイントを一緒にコミットするので、各イベントは、先に届いたプロセスが 1 回だけ適用します。どちらかのプロセスで追記すると、もう一方に通知が届き、そのストリームが起きます。セッションのクッキーはそのセッションの最後の追記の `id` を運ぶので、もう一方のプロセスが返すページは、台帳がそこまで届くのを待ちます。

本番では、プロセスの前にロードバランサを置き、すべてのプロセスに同じ `SHOMEN_SECRET` を渡します。鍵を変えるときは、[00-INSTRUCTION.md](00-INSTRUCTION.md) の `SHOMEN_SECRET_VERIFY` を見てください。

## replica あり

`RECORDS_REPLICA_URL` に primary の hot standby を 1 台指定し、同じコマンドを実行します。

```sh
export RECORDS_REPLICA_URL=postgres://replica.example/records
```

ページとストリームは、replica がセッションの最後の追記に届いていれば replica から、2 秒以内に届かなければ primary から読みます。追記、コンシューマのバッチ、通知は primary のままです。Shomen は replica に何も作りません。台帳の表はレプリケーションで replica に届きます。URL は 1 台の standby を指してください。接続ごとに別の standby へ振り分ける URL は使えません。

CI は `RECORDS_REPLICA_URL` に primary 自身の URL を渡します。これで、ソースを変えずに replica の URL ありで起動して応答することを確かめます。遅れる replica は、フェーズ 7 の spec が確かめています（[決定](decisions/20261001-phase7-replica-spec.md)）。
````

- [ ] **Step 7: CI に 2 プロセスの確認を 2 回足す**

`.github/workflows/ci.yml` の `examples/records` の手順の後に足す（鍵は CI 専用の値で、本番の秘密ではない）:

```yaml
      # The commands of docs/en/05-SCALE-OUT.md: two processes on one
      # Postgres database, without and then with a replica URL
      # (docs/decisions/20261003-phase8-scale-out.md).
      - name: examples/records on two processes
        working-directory: examples/records
        env:
          SHOMEN_ENV: production
          SHOMEN_SECRET: ci-two-processes-secret-0123456789abcdef
          RECORDS_DATABASE_URL: postgres://postgres:postgres@localhost:5432/postgres
        run: sh scripts/two_processes.sh
      - name: examples/records on two processes with a replica URL
        working-directory: examples/records
        env:
          SHOMEN_ENV: production
          SHOMEN_SECRET: ci-two-processes-secret-0123456789abcdef
          RECORDS_DATABASE_URL: postgres://postgres:postgres@localhost:5432/postgres
          RECORDS_REPLICA_URL: postgres://postgres:postgres@localhost:5432/postgres
        run: sh scripts/two_processes.sh
```

- [ ] **Step 8: 照合の spec と全体が通ることを確かめる**

Run: `cd examples/records && crystal spec spec/scale_out_spec.cr && crystal spec`
Expected: すべて通る

Run: `crystal tool format --check src spec examples`
Expected: 出力なし

Postgres の 2 プロセスと replica ありの確認は、PR の CI で確かめる（ローカルに Postgres があれば、Step 4 のコマンドの `RECORDS_DATABASE_URL` を Postgres の DB にして、`RECORDS_REPLICA_URL` なしとありで走らせる）。

---

### Task 5: README と CONTRIBUTING

**Files:**
- Modify: `README.md`、`README.ja.md`、`CONTRIBUTING.md`、`CONTRIBUTING.ja.md`
- Test: `spec/shomen/readme_spec.cr`

**Interfaces:**
- Consumes: `docs/en/04-API.md`、`docs/04-API.md`（8a）、`docs/en/05-SCALE-OUT.md`、`docs/05-SCALE-OUT.md`（Task 4）、`examples/records`
- Produces: なし

- [ ] **Step 1: 失敗する spec を書く**

`spec/shomen/readme_spec.cr`:

```crystal
require "../spec_helper"

private def links(path : String) : Array(String)
  File.read(path).scan(/\]\(([^)#:]+)(?:#[^)]*)?\)/).map(&.[1])
end

describe "README and CONTRIBUTING" do
  {"README.md", "README.ja.md", "CONTRIBUTING.md", "CONTRIBUTING.ja.md"}.each do |path|
    it "#{path} points at the API list, the scale-out steps, and examples/records" do
      found = links(path).map(&.rstrip('/'))
      found.any?(&.ends_with?("04-API.md")).should be_true, "#{path} has no link to 04-API.md"
      found.any?(&.ends_with?("05-SCALE-OUT.md")).should be_true, "#{path} has no link to 05-SCALE-OUT.md"
      found.should contain("examples/records")
    end

    it "#{path} links only to files that exist" do
      links(path).each do |link|
        File.exists?(link).should be_true, "#{path} links to #{link}, which does not exist"
      end
    end
  end
end
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `crystal spec spec/shomen/readme_spec.cr`
Expected: 「points at」の 4 例が落ちる。「links only」の 4 例は通る（既存のリンクは切れていない。落ちたら、そのリンクをこの Task で直す）

- [ ] **Step 3: README.md を直す**

1. 10 行目の `Version 0.0.0. Phases 1 to 7 are in the tree:` を `Version 0.1.0. Phases 1 to 8 are in the tree:` に、同じ行の末尾 `cached in the process. There is no release tag yet.` を `cached in the process, plus an API list, a records example, and the steps to scale it out. There is no release tag yet.` にする
2. 「Run the example」の `` Open <http://127.0.0.1:3000>. `GET /` returns a document that contains `<h1>Hello</h1>`. `` の段落の後に、空行を挟んで足す:

```markdown
The records example is in [`examples/records`](examples/records). [docs/en/05-SCALE-OUT.md](docs/en/05-SCALE-OUT.md) runs it as one process on SQLite and as two processes on Postgres.
```

3. 見出し `## Phases 1 to 7 are what run` を `## Phases 1 to 8 are what run` にする
4. Phase 7 の箇条書きの後、`The phase list is in` の段落の前に、空行を挟んで足す:

```markdown
Phase 8 adds these:

- [docs/en/04-API.md](docs/en/04-API.md): the public types and methods an application calls, each with the section or decision that defines it. A spec fails when the list and the code disagree
- [`examples/records`](examples/records): an equipment ledger (register, lend, return) on the parts above: typed routes, forms with CSRF, commands and events, a consumer's tables, `remember`, fragments, SSE, an island, a validator, and a cached fragment
- [docs/en/05-SCALE-OUT.md](docs/en/05-SCALE-OUT.md): the steps from one process on SQLite to two processes on Postgres, with and without a replica. CI runs its commands
- Version 0.1.0 in `shard.yml`
```

5. 「Specification」の表の Conventions の行の後に足す:

```markdown
| API | [docs/en/04-API.md](docs/en/04-API.md) | [docs/04-API.md](docs/04-API.md) |
| Scale out | [docs/en/05-SCALE-OUT.md](docs/en/05-SCALE-OUT.md) | [docs/05-SCALE-OUT.md](docs/05-SCALE-OUT.md) |
```

6. 「Development」の `Without SHOMEN_SPEC_POSTGRES` で始まる段落の後に、空行を挟んで足す:

```markdown
The records example has its own specs: `cd examples/records && shards install && crystal spec`. With `RECORDS_SPEC_POSTGRES` set to a URL like the one for `SHOMEN_SPEC_POSTGRES`, they run on a new Postgres database, which they drop at the end.
```

7. 「Development」の CI の段落の `and the `examples/hello` specs.` を `the `examples/hello` specs, the `examples/records` specs on SQLite and on Postgres, and the two-process commands of [docs/en/05-SCALE-OUT.md](docs/en/05-SCALE-OUT.md), without and with a replica URL.` にする（`the build, `crystal spec` with …` の後の「, and」は「,」になる）

- [ ] **Step 4: README.ja.md を直す**

1. 10 行目の `バージョンは 0.0.0 です。リポジトリに入っているのはフェーズ 7 までで、` を `バージョンは 0.1.0 です。リポジトリに入っているのはフェーズ 8 までで、` に、同じ行の `キャッシュする）が動きます。リリースタグはまだありません。` を `キャッシュする）が動きます。API の一覧、業務画面のサンプル、そのスケールアウトの手順もあります。リリースタグはまだありません。` にする
2. 「サンプルを動かす」の `` <http://127.0.0.1:3000> を開きます。 `` の段落の後に足す:

```markdown
業務画面のサンプルは [`examples/records`](examples/records) です。SQLite の 1 プロセスと Postgres の 2 プロセスでの動かし方は [docs/05-SCALE-OUT.md](docs/05-SCALE-OUT.md) にあります。
```

3. 見出し `## いま動くのはフェーズ 1 から 7` を `## いま動くのはフェーズ 1 から 8` にする
4. フェーズ 7 の箇条書きの後、`フェーズの一覧は` の段落の前に足す:

```markdown
フェーズ 8 で足したもの:

- [docs/04-API.md](docs/04-API.md): アプリが呼ぶ公開の型とメソッドの一覧。それぞれを定める仕様の節か決定を添えます。一覧とコードが食い違うと spec が落ちます
- [`examples/records`](examples/records): 備品台帳（登録、貸出、返却）。上の部品、つまり型付きルート、CSRF 付きのフォーム、コマンドとイベント、コンシューマの表、`remember`、断片、SSE、島、検証子、キャッシュした断片を使います
- [docs/05-SCALE-OUT.md](docs/05-SCALE-OUT.md): SQLite の 1 プロセスから、Postgres の 2 プロセス（replica なしとあり）にする手順。CI がそのコマンドを走らせます
- `shard.yml` の版 0.1.0
```

5. 「仕様」の表の 規約 の行の後に足す:

```markdown
| API | [docs/en/04-API.md](docs/en/04-API.md) | [docs/04-API.md](docs/04-API.md) |
| スケールアウト | [docs/en/05-SCALE-OUT.md](docs/en/05-SCALE-OUT.md) | [docs/05-SCALE-OUT.md](docs/05-SCALE-OUT.md) |
```

6. 「開発」の `` `SHOMEN_SPEC_POSTGRES` が無いと `` で始まる段落の後に足す:

```markdown
業務画面のサンプルには別に spec があります（`cd examples/records && shards install && crystal spec`）。`RECORDS_SPEC_POSTGRES` に `SHOMEN_SPEC_POSTGRES` と同じような URL を入れると、新しい Postgres の DB で走り、終わったら消します。
```

7. 「開発」の CI の段落の `` `examples/hello` の spec を走らせます。 `` を `` `examples/hello` の spec、SQLite と Postgres での `examples/records` の spec、[docs/05-SCALE-OUT.md](docs/05-SCALE-OUT.md) の 2 プロセスのコマンド（replica の URL なしとあり）を走らせます。 `` にする（直前の「、」の並びはそのまま）

- [ ] **Step 5: CONTRIBUTING.md を直す**

1. 「Read first」の `The Japanese files next to` の段落の前に、空行を挟んで足す:

```markdown
[docs/en/04-API.md](docs/en/04-API.md) lists what an application calls. [`examples/records`](examples/records) uses it, and [docs/en/05-SCALE-OUT.md](docs/en/05-SCALE-OUT.md) runs that example as two processes.
```

2. 「Checks」の `` `crystal build` writes `./shomen` in the root. Leave it uncommitted. `` の後に、空行を挟んで足す:

```markdown
The records example has its own specs: `cd examples/records && shards install && crystal spec`. `RECORDS_SPEC_POSTGRES`, set like `SHOMEN_SPEC_POSTGRES`, runs them on a new Postgres database. A change to `examples/records/scripts/two_processes.sh` changes both versions of `05-SCALE-OUT.md` in the same commit; a spec compares them.
```

3. 「Checks」の CI の段落の `` and the `examples/hello` specs. Wait `` を `` the `examples/hello` specs, the `examples/records` specs on SQLite and on Postgres, and the two-process commands of [docs/en/05-SCALE-OUT.md](docs/en/05-SCALE-OUT.md), without and with a replica URL. Wait `` にする

- [ ] **Step 6: CONTRIBUTING.ja.md を直す**

1. 「先に読むもの」の `` `docs/en/` の隣にある日本語ファイルは訳です。 `` の段落の前に足す:

```markdown
アプリが呼ぶものの一覧は [docs/04-API.md](docs/04-API.md) です。それを使うサンプルが [`examples/records`](examples/records) で、[docs/05-SCALE-OUT.md](docs/05-SCALE-OUT.md) がそれを 2 プロセスで動かします。
```

2. 「確認」の `` `crystal build` はルートに `./shomen` を書き出します。コミットには含めません。 `` の後に足す:

```markdown
業務画面のサンプルには別に spec があります（`cd examples/records && shards install && crystal spec`）。`RECORDS_SPEC_POSTGRES` を `SHOMEN_SPEC_POSTGRES` と同じように入れると、新しい Postgres の DB で走ります。`examples/records/scripts/two_processes.sh` を変えたら、同じコミットで英日の `05-SCALE-OUT.md` も直します。spec が両者を照合します。
```

3. 「確認」の CI の段落の `` `examples/hello` の spec を走らせます。このチェックが `` を `` `examples/hello` の spec、SQLite と Postgres での `examples/records` の spec、[docs/05-SCALE-OUT.md](docs/05-SCALE-OUT.md) の 2 プロセスのコマンド（replica の URL なしとあり）を走らせます。このチェックが `` にする

- [ ] **Step 7: spec が通ることを確かめる**

Run: `crystal spec spec/shomen/readme_spec.cr spec/shomen/api_list_spec.cr`
Expected: すべて通る

---

### Task 6: フェーズ 8 を締める

**Files:**
- Modify: `docs/en/02-PHASES.md:9`、`docs/02-PHASES.md:9`

**Interfaces:**
- Consumes: Task 1–5 のすべて
- Produces: なし

- [ ] **Step 1: 現行フェーズの表示を直す**

`docs/en/02-PHASES.md` の 9 行目 `Phase 7 acceptance is met. When phase 8 acceptance is met, stop and wait for the next instruction.` を次にする:

```markdown
Phase 8 acceptance is met. Stop here and wait for the next instruction.
```

`docs/02-PHASES.md` の 9 行目 `フェーズ 7 の受入は満たした。8 の受入を満たしたら停止し、ユーザーの次指示を待つ。` を次にする:

```markdown
フェーズ 8 の受入は満たした。ここで停止し、ユーザーの次指示を待つ。
```

- [ ] **Step 2: AGENTS.md の検証をすべて走らせる**

Run:

```sh
crystal spec
crystal build src/shomen.cr --error-trace -o /tmp/shomen
cd examples/hello && shards install && crystal spec && cd ../..
cd examples/records && shards install && crystal spec && cd ../..
crystal tool format --check src spec examples
```

Expected: どれも失敗 0。ローカルに Postgres があれば、`SHOMEN_SPEC_POSTGRES` と `RECORDS_SPEC_POSTGRES` を付けて 1 回ずつ走らせる

- [ ] **Step 3: 受入を 1 つずつ照らす**

「受入との対応」の表の各行について、満たすものが緑であることを確かめる。Postgres の行（records の spec、2 プロセスの確認 2 回）は PR の CI のログで、次の 3 つを見る:

- `examples/records` の手順で `crystal spec` が 2 回とも `0 failures`
- `examples/records on two processes` が `two processes: an item registered through …` を出して成功
- `examples/records on two processes with a replica URL` も同じく成功

どれかが CI でだけ落ちたら、受入は満たしていない。Step 1 の表示を戻し、原因を調べてユーザーに報告する。

- [ ] **Step 4: 報告する**

ユーザーに、変更したファイル、走らせたコマンド、受入の各行が満たされたか、残っていること（v0.1.0 のタグと Release はユーザーの指示待ち）を短く報告する。commit、push、PR はユーザーが指示したときだけ。
