# Phase 2 Forms and Sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** フェーズ 2 の受入まで届ける。署名付きセッション Cookie、セッションに結びついた CSRF トークンと 403、urlencoded の `form` POST から `Input` へのバインド、422 での再描画、`input` のコンパイル時ラベル検査、`examples/hello` のフォーム 1 つ。

**Architecture:** `Shomen::SessionStore` はサーバ側に状態を持たない。Cookie の値は `<id>.<HMAC-SHA256>` にし、CSRF トークンは同じ鍵で `"csrf:" + id` の HMAC-SHA256 を毎回計算する（D1）。`Shomen::Server` は要求ごとにセッションを読み込み、unsafe method の本文を一度だけ `URI::Params` にして `_csrf` を検査し、そのフォームと CSRF トークンの文字列を `Router` 経由で `Route.handle(request, form, csrf_token)` に渡す。ラベル検査は `Shomen::View` の `macro inherited` が各サブクラスに置く `macro method_added` で行い、メソッド本体を `stringify` して字句走査する。

**Tech Stack:** Crystal `>= 1.20.0`（開発機は 1.21.1）、標準ライブラリの `spec`、`http/server`、`uri`、`openssl/hmac`、`crypto/subtle`、`random/secure`。外部 shard は足さない。

**Spec:** `docs/en/00-INSTRUCTION.md` の「3. Views and HTML」（input のラベル検査）、「4. Responses」、「6. Sessions」、「9. Error model」（`Shomen::Forbidden`）、`docs/en/01-ARCHITECTURE.md` のリクエスト経路とモジュール境界、`docs/en/02-PHASES.md` のフェーズ 2、`docs/en/03-CONVENTIONS.md`。細部は次の決定ファイルに従う。

- `docs/decisions/20260929-phase2-session-store.md`（D1）
- `docs/decisions/20260929-phase2-secret-fallback.md`（D2）
- `docs/decisions/20260929-phase2-secure-cookie.md`（D3）
- `docs/decisions/20260929-phase2-csrf.md`（D4）
- `docs/decisions/20260929-phase2-route-csrf-token.md`（D5）
- `docs/decisions/20260929-phase2-form-input.md`（D6）
- `docs/decisions/20260929-phase2-validation-status.md`（D7）
- `docs/decisions/20260929-phase2-input-label-check.md`（D8）
- `docs/decisions/20260929-phase2-form-example.md`（D9）

## Global Constraints

- 言語は Crystal 1.20 以上。`shard.yml` の下限は `>= 1.20.0` のまま。
- 本体 shard に依存キーを足さない（仕様 1: phases 0–2 は依存なし）。`openssl` と `crypto` は標準ライブラリである。
- Cookie 名は `shomen_session`。`HttpOnly`、`SameSite=Lax`、`path=/`。`Secure` は `https: true` のときだけ（仕様 6、D3）。
- 署名の鍵は環境変数 `SHOMEN_SECRET`。未設定または空ならプロセスごとのランダムな鍵と STDERR 警告（D2）。
- CSRF のフィールド名は `_csrf`。POST、PUT、PATCH、DELETE でトークンが一致しなければ 403 の HTML 文書（D4）。
- `Shomen::Route` は `Shomen::Session` を参照しない。ルートが受け取るのは `csrf_token : String` だけ（01-ARCHITECTURE、D5）。
- 公開 API は `Shomen::` 配下だけ。1 ファイル 1 主要型。
- コードと識別子は英語。この計画と決定ログは日本語。
- フェーズ 3 以降の機能は作らない。コマンド、イベント、SQLite、`render_fragment`、JSON、`shomen.js`、SSE、島、CSP、本番の例外秘匿は範囲外。
- ユーザーが指示するまで commit しない。この計画に commit 手順は無い。
- `crystal tool format` を通し、警告を残して完了にしない。
- テストはポートを bind しない。`HTTP::Server::Response` を `IO::Memory` に書く。ポート 3000 を使うのは Task 7 の手動確認だけ。
- 検証でリポジトリルートにできる実行ファイル `shomen` は `docs/decisions/20260928-build-artifact.md` のとおり削除する。

実行はリポジトリルートで行う。`Shomen::VERSION` は `"0.0.0"` のまま変えない。

## Review Focus

- 再起動後の Cookie。同じ `SHOMEN_SECRET` で再起動した後に、署名の正しい Cookie が来る。同じセッションと CSRF トークンのまま受け付け、`Set-Cookie` を返さず、500 にもしない。鍵が変わっていれば新しいセッションを作り直して `Set-Cookie` を返す。Task 1 の spec と `csrf_spec.cr` で固定する（D1 の見直し後）。
- 他人のセッションのトークン。形は正しいが別セッションの `_csrf` を送る。403 になる。Task 3 の spec で固定する。
- urlencoded 以外の本文。`multipart/form-data` の中に `_csrf=<正しい値>` の文字列があっても、読まずに 403 にする。逆に `; charset=UTF-8` 付きの urlencoded は受け付ける。Task 3 の spec で固定する。
- 本文が UTF-8 でない。`name=%FF` は 400 の HTML 文書になり、500 にも文字化けした再描画にもならない。Task 3 の spec で固定する。
- 文字列の中の `label(for: ...)`。`p "label(for: \"a\")"` があっても `input(id: "a")` のラベルとは数えない。Task 6 のフィクスチャで固定する。

## File Map

| ファイル | 役割 | Task |
|---|---|---|
| `src/shomen/session.cr` | `Shomen::Session`。`id`、`fresh?`、`csrf_token` | 1 |
| `src/shomen/session_store.cr` | `Shomen::SessionStore`。作成、署名、検証、`HTTP::Cookie` の生成 | 1 |
| `src/shomen/forbidden.cr` | `Shomen::Forbidden` 例外 | 3 |
| `src/shomen.cr` | 新しいファイルの require | 1, 3 |
| `src/shomen/server.cr` | セッションの読み込み、`Set-Cookie`、フォームの読み取り、CSRF、403 | 2, 3 |
| `src/shomen/router.cr` | handler の Proc にフォームとトークンを足す | 3 |
| `src/shomen/route.cr` | `csrf_token`、`handle` の引数、フォームのバインド、`render(view, status)` | 3, 4, 5 |
| `src/shomen/view.cr` | `csrf_field` | 5 |
| `src/shomen/a11y.cr` | `input` のラベル検査 | 6 |
| `spec/spec_helper.cr` | `SHOMEN_SECRET` を固定、`support/client` の require | 2 |
| `spec/support/client.cr` | `call_with` と `session_cookie` | 2 |
| `spec/support/routes.cr` | フェーズ 2 の spec 用ルート | 3, 4, 5 |
| `spec/shomen/session_store_spec.cr` | Task 1 | 1 |
| `spec/shomen/session_spec.cr` | Server とセッション Cookie | 2 |
| `spec/shomen/server_spec.cr` | 既存の `Set-Cookie` spec の修正 | 2 |
| `spec/shomen/csrf_spec.cr` | CSRF と 403 | 3 |
| `spec/shomen/router_spec.cr` | handler の呼び出し引数を修正 | 3 |
| `spec/shomen/form_spec.cr` | フォームのバインド | 4 |
| `spec/shomen/view_spec.cr` | `csrf_field`、`VoidProbe` の修正 | 5, 6 |
| `spec/shomen/route_spec.cr` | `render` の status | 5 |
| `spec/shomen/a11y_spec.cr` | ラベル検査 | 6 |
| `spec/fixtures/route_get_form_field.cr` など | コンパイル失敗のフィクスチャ | 4, 6 |
| `examples/hello/src/hello.cr` | `Greeting::Edit` と `Greeting::Update` | 7 |
| `examples/hello/spec/spec_helper.cr` | `SHOMEN_SECRET` を固定 | 7 |
| `examples/hello/spec/greeting_spec.cr` | 受入 1〜3 を例で確かめる | 7 |
| `README.md`、`README.ja.md`、`CONTRIBUTING.md`、`CONTRIBUTING.ja.md` | フェーズ 2 の反映 | 8 |

---

### Task 1: Session と SessionStore

**Files:**
- Create: `src/shomen/session.cr`
- Create: `src/shomen/session_store.cr`
- Modify: `src/shomen.cr`
- Test: `spec/shomen/session_store_spec.cr`

**Interfaces:**
- Consumes: なし
- Produces:
  - `Shomen::Session::COOKIE = "shomen_session"`
  - `Shomen::Session#id : String`、`#fresh? : Bool`、`#csrf_token : String`
  - `Shomen::SessionStore.new(secret : String)`
  - `Shomen::SessionStore#load(cookie_value : String?) : Shomen::Session`
  - `Shomen::SessionStore#cookie(session : Shomen::Session, secure : Bool) : HTTP::Cookie`

- [ ] **Step 1: 失敗する spec を書く**

`spec/shomen/session_store_spec.cr`:

```crystal
require "../spec_helper"

private def cookie_value(store : Shomen::SessionStore, session : Shomen::Session) : String
  store.cookie(session, false).value
end

describe Shomen::SessionStore do
  it "creates a fresh session when there is no cookie" do
    session = Shomen::SessionStore.new("k").load(nil)
    session.fresh?.should be_true
    session.id.should match(/\A[0-9a-f]{64}\z/)
    session.csrf_token.should_not be_empty
  end

  it "loads the same session from its signed cookie" do
    store = Shomen::SessionStore.new("k")
    first = store.load(nil)
    again = store.load(cookie_value(store, first))
    again.fresh?.should be_false
    again.id.should eq(first.id)
    again.csrf_token.should eq(first.csrf_token)
  end

  it "gives each session its own csrf token" do
    store = Shomen::SessionStore.new("k")
    store.load(nil).csrf_token.should_not eq(store.load(nil).csrf_token)
  end

  it "replaces a session whose signature was changed" do
    store = Shomen::SessionStore.new("k")
    first = store.load(nil)
    value = cookie_value(store, first)
    tampered = value[0..-2] + (value[-1] == '0' ? "1" : "0")
    again = store.load(tampered)
    again.fresh?.should be_true
    again.id.should_not eq(first.id)
  end

  it "replaces a session signed with another secret" do
    store = Shomen::SessionStore.new("a")
    first = store.load(nil)
    forged = Shomen::SessionStore.new("b").cookie(first, false).value
    store.load(forged).fresh?.should be_true
  end

  it "keeps a validly signed session across a restart with the same secret" do
    first_store = Shomen::SessionStore.new("k")
    first = first_store.load(nil)
    again = Shomen::SessionStore.new("k").load(cookie_value(first_store, first))
    again.fresh?.should be_false
    again.id.should eq(first.id)
    again.csrf_token.should eq(first.csrf_token)
  end

  it "replaces a malformed cookie" do
    store = Shomen::SessionStore.new("k")
    ["", "abc", ".", "abc.", ".abc"].each do |value|
      store.load(value).fresh?.should be_true
    end
  end

  it "writes HttpOnly, SameSite=Lax, and path=/ without Secure over HTTP" do
    store = Shomen::SessionStore.new("k")
    header = store.cookie(store.load(nil), false).to_set_cookie_header
    header.should start_with("shomen_session=")
    header.should contain("path=/")
    header.should contain("HttpOnly")
    header.should contain("SameSite=Lax")
    header.should_not contain("Secure")
  end

  it "adds Secure over HTTPS" do
    store = Shomen::SessionStore.new("k")
    store.cookie(store.load(nil), true).to_set_cookie_header.should contain("Secure")
  end
end
```

- [ ] **Step 2: spec が失敗することを確認する**

Run: `crystal spec spec/shomen/session_store_spec.cr`
Expected: FAIL。`undefined constant Shomen::SessionStore`

- [ ] **Step 3: Session を実装する**

`src/shomen/session.cr`:

```crystal
class Shomen::Session
  COOKIE = "shomen_session"

  getter id : String
  getter? fresh : Bool
  getter csrf_token : String

  def initialize(@id : String, @fresh : Bool, @csrf_token : String)
  end
end
```

- [ ] **Step 4: SessionStore を実装する**

`src/shomen/session_store.cr`:

```crystal
require "http"
require "openssl/hmac"
require "crypto/subtle"
require "random/secure"

# Holds no server-side state: the id is signed and the csrf token is
# derived from it, so a session survives a restart with the same secret.
class Shomen::SessionStore
  def initialize(@secret : String)
  end

  def load(cookie_value : String?) : Shomen::Session
    if cookie_value && (id = verify(cookie_value))
      return Shomen::Session.new(id, false, csrf_token_for(id))
    end
    id = Random::Secure.hex(32)
    Shomen::Session.new(id, true, csrf_token_for(id))
  end

  def cookie(session : Shomen::Session, secure : Bool) : HTTP::Cookie
    HTTP::Cookie.new(
      Shomen::Session::COOKIE,
      "#{session.id}.#{sign(session.id)}",
      path: "/",
      http_only: true,
      secure: secure,
      samesite: HTTP::Cookie::SameSite::Lax,
    )
  end

  private def sign(id : String) : String
    OpenSSL::HMAC.hexdigest(:sha256, @secret, id)
  end

  # The "csrf:" prefix keeps the token distinct from the cookie signature.
  private def csrf_token_for(id : String) : String
    OpenSSL::HMAC.hexdigest(:sha256, @secret, "csrf:" + id)
  end

  private def verify(value : String) : String?
    id, dot, signature = value.rpartition('.')
    return nil if dot.empty? || id.empty?
    Crypto::Subtle.constant_time_compare(sign(id), signature) ? id : nil
  end
end
```

- [ ] **Step 5: 入口から require する**

`src/shomen.cr` の `require "./shomen/error_view"` の直後に足す:

```crystal
require "./shomen/session"
require "./shomen/session_store"
```

- [ ] **Step 6: spec が通ることを確認する**

Run: `crystal spec spec/shomen/session_store_spec.cr && crystal spec`
Expected: PASS。既存の 72 件も含めて 0 failures

---

### Task 2: Server がセッション Cookie を出す

**Files:**
- Modify: `src/shomen/server.cr`
- Modify: `spec/spec_helper.cr`
- Create: `spec/support/client.cr`
- Modify: `spec/shomen/server_spec.cr`（`sends each Set-Cookie value on its own header`）
- Test: `spec/shomen/session_spec.cr`

**Interfaces:**
- Consumes: Task 1 の `Shomen::SessionStore#load`、`#cookie`、`Shomen::Session#fresh?`、`Shomen::Session::COOKIE`
- Produces:
  - `Shomen::Server.new(secret : String = Shomen::Server.secret_from_env, https : Bool = false)`
  - `Shomen::Server.start(host : String = "127.0.0.1", port : Int32 = 3000, https : Bool = false) : Nil`
  - `Shomen::Server.secret_from_env : String`
  - spec 用 `call_with(server, method, path, cookie = nil, body = nil, content_type = "application/x-www-form-urlencoded") : HTTP::Client::Response`
  - spec 用 `session_cookie(response) : String`（`"shomen_session=<value>"` の部分だけ）

- [ ] **Step 1: spec 用の鍵と client を用意する**

`spec/spec_helper.cr` を次にする:

```crystal
require "spec"
ENV["SHOMEN_SECRET"] = "spec-secret"
require "../src/shomen"
require "./support/process"
require "./support/client"
require "./support/routes"
```

`spec/support/client.cr`:

```crystal
require "http"
require "http/client"

def call_with(server : Shomen::Server, method : String, path : String, cookie : String? = nil, body : String? = nil, content_type : String = "application/x-www-form-urlencoded") : HTTP::Client::Response
  headers = HTTP::Headers.new
  headers["Cookie"] = cookie if cookie
  headers["Content-Type"] = content_type if body
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  server.call(HTTP::Server::Context.new(HTTP::Request.new(method, path, headers, body), response))
  response.close
  HTTP::Client::Response.from_io(IO::Memory.new(io.to_s))
end

def session_cookie(response : HTTP::Client::Response) : String
  header = response.headers.get("Set-Cookie").find(&.starts_with?("shomen_session=")) || raise "no session cookie"
  header.split(';').first
end
```

- [ ] **Step 2: 失敗する spec を書く**

`spec/shomen/session_spec.cr`:

```crystal
require "../spec_helper"

private def session_header(response : HTTP::Client::Response) : String
  response.headers.get("Set-Cookie").find(&.starts_with?("shomen_session=")) || raise "no session cookie"
end

describe "Shomen::Server sessions" do
  it "sets a session cookie on a response to a request without one" do
    header = session_header(call_with(Shomen::Server.new, "GET", "/phase1/home"))
    header.should contain("HttpOnly")
    header.should contain("SameSite=Lax")
    header.should_not contain("Secure")
  end

  it "sets a session cookie on a 404 too" do
    response = call_with(Shomen::Server.new, "GET", "/phase2/missing")
    response.status_code.should eq(404)
    session_header(response).should start_with("shomen_session=")
  end

  it "does not set the cookie again when the request carries a valid one" do
    server = Shomen::Server.new
    cookie = session_cookie(call_with(server, "GET", "/phase1/home"))
    response = call_with(server, "GET", "/phase1/home", cookie: cookie)
    response.headers.has_key?("Set-Cookie").should be_false
  end

  it "replaces a cookie signed with another secret" do
    cookie = session_cookie(call_with(Shomen::Server.new(secret: "a"), "GET", "/phase1/home"))
    response = call_with(Shomen::Server.new(secret: "b"), "GET", "/phase1/home", cookie: cookie)
    session_header(response).should start_with("shomen_session=")
  end

  it "marks the cookie Secure when the server runs behind HTTPS" do
    header = session_header(call_with(Shomen::Server.new(https: true), "GET", "/phase1/home"))
    header.should contain("Secure")
  end
end
```

`spec/shomen/server_spec.cr` の `sends each Set-Cookie value on its own header` を次にする:

```crystal
  it "sends each Set-Cookie value on its own header" do
    response = call_server("GET", "/phase1/cookies")
    response.status_code.should eq(200)
    cookies = response.headers.get("Set-Cookie")
    cookies[0, 2].should eq(["a=1", "b=2"])
    cookies[2].should start_with("shomen_session=")
    assert_security_headers(response)
  end
```

- [ ] **Step 3: spec が失敗することを確認する**

Run: `crystal spec spec/shomen/session_spec.cr spec/shomen/server_spec.cr`
Expected: FAIL。`no session cookie` と、`Shomen::Server.new(secret:)` のオーバーロードが無いこと

- [ ] **Step 4: Server を実装する**

`src/shomen/server.cr` を次にする:

```crystal
require "http/server"
require "http/server/handler"
require "random/secure"

class Shomen::Server
  include HTTP::Handler

  @@generated_secret : String?

  def self.start(host : String = "127.0.0.1", port : Int32 = 3000, https : Bool = false) : Nil
    Shomen::Router.entries
    server = HTTP::Server.new([new(https: https)])
    server.bind_tcp(host, port)
    server.listen
  end

  def self.secret_from_env : String
    if secret = ENV["SHOMEN_SECRET"]?.presence
      return secret
    end
    @@generated_secret ||= begin
      STDERR.puts "shomen: SHOMEN_SECRET is not set; using a random secret until restart"
      Random::Secure.hex(32)
    end
  end

  def initialize(secret : String = Shomen::Server.secret_from_env, @https : Bool = false)
    @sessions = Shomen::SessionStore.new(secret)
  end

  def call(context : HTTP::Server::Context) : Nil
    session = @sessions.load(context.request.cookies[Shomen::Session::COOKIE]?.try(&.value))
    write_response(context, respond(context.request), session)
  end

  def dispatch(request : HTTP::Request) : Shomen::Response
    handler = Shomen::Router.find(request.method, request.path)
    return error_response(404, "Not found", nil) unless handler
    handler.call(request)
  end

  private def respond(request : HTTP::Request) : Shomen::Response
    dispatch(request)
  rescue ex : Shomen::BadInput
    error_response(400, "Bad input", ex.message)
  rescue ex : Shomen::NotFound
    error_response(404, "Not found", nil)
  rescue ex
    error_response(500, "Error", ex.message)
  end

  private def error_response(status : Int32, heading : String, detail : String?) : Shomen::Response
    Shomen::Response.html(Shomen::ErrorView.new(heading, detail).to_html, status)
  end

  private def write_response(context : HTTP::Server::Context, response : Shomen::Response, session : Shomen::Session) : Nil
    context.response.status_code = response.status
    context.response.content_type = response.content_type
    response.headers.each do |entry|
      name, values = entry
      context.response.headers[name] = values
    end
    if session.fresh?
      context.response.headers.add("Set-Cookie", @sessions.cookie(session, @https).to_set_cookie_header)
    end
    context.response.headers["X-Content-Type-Options"] = "nosniff"
    context.response.headers["Referrer-Policy"] = "no-referrer"
    context.response.headers["X-Frame-Options"] = "DENY"
    if context.request.method == "HEAD"
      context.response.content_length = response.body.bytesize
    else
      context.response.print(response.body)
    end
  end
end
```

`Set-Cookie` は本文を書く前に足す。本文を書いたあとではヘッダを変えられない。

- [ ] **Step 5: spec が通ることを確認する**

Run: `crystal spec`
Expected: PASS。0 failures。`SHOMEN_SECRET is not set` が出力に出ないこと

---

### Task 3: CSRF と 403

**Files:**
- Create: `src/shomen/forbidden.cr`
- Modify: `src/shomen.cr`
- Modify: `src/shomen/server.cr`
- Modify: `src/shomen/router.cr`（`Entry`、`find`、`build_entries`）
- Modify: `src/shomen/route.cr`（`csrf_token`、`handle` の引数と末尾）
- Modify: `spec/shomen/router_spec.cr`（`handler.call` の 3 か所）
- Modify: `spec/support/routes.cr`
- Test: `spec/shomen/csrf_spec.cr`

**Interfaces:**
- Consumes: Task 2 の `Shomen::Server`、`call_with`、`session_cookie`、Task 1 の `Shomen::Session#csrf_token`
- Produces:
  - `Shomen::Forbidden < Exception`
  - `Shomen::Router::Entry#handler : Proc(HTTP::Request, URI::Params, String, Shomen::Response)`
  - `Shomen::Router.find(method, path) : Proc(HTTP::Request, URI::Params, String, Shomen::Response)?`
  - `Route.handle(request : HTTP::Request, form : URI::Params = URI::Params.new, csrf_token : String = "") : Shomen::Response`
  - `Shomen::Route#csrf_token : String`（`property`、既定値 `""`）
  - `Shomen::Server#dispatch(request : HTTP::Request, form : URI::Params = URI::Params.new, csrf_token : String = "") : Shomen::Response`
  - spec 用ルート `ServerRoutes::Token`（`GET /phase2/token`、本文は `csrf_token`）、`ServerRoutes::Echo`（`POST /phase2/echo`、本文は `accepted`）、`ServerRoutes::Denied`（`GET /phase2/denied`、`Shomen::Forbidden` を上げる）

- [ ] **Step 1: spec 用ルートを足す**

`spec/support/routes.cr` の `module ServerRoutes` の末尾（`Update` の後）に足す:

```crystal
  class Token < Shomen::Route
    method GET
    path "/phase2/token"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html(csrf_token)
    end
  end

  class Echo < Shomen::Route
    method POST
    path "/phase2/echo"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html("accepted")
    end
  end

  class Denied < Shomen::Route
    method GET
    path "/phase2/denied"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      raise Shomen::Forbidden.new
    end
  end
```

- [ ] **Step 2: 失敗する spec を書く**

`spec/shomen/csrf_spec.cr`:

```crystal
require "../spec_helper"

private def start_session(server : Shomen::Server) : {String, String}
  response = call_with(server, "GET", "/phase2/token")
  {session_cookie(response), response.body}
end

private def form_body(pairs : Hash(String, String)) : String
  URI::Params.encode(pairs)
end

describe "CSRF" do
  it "returns 403 HTML for a POST without a session or token" do
    response = call_with(Shomen::Server.new, "POST", "/phase2/echo", body: "")
    response.status_code.should eq(403)
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    response.body.should contain("<title>Forbidden</title>")
    response.headers["X-Frame-Options"].should eq("DENY")
  end

  it "returns 403 when the form has no token" do
    server = Shomen::Server.new
    cookie, _ = start_session(server)
    call_with(server, "POST", "/phase2/echo", cookie: cookie, body: "name=x").status_code.should eq(403)
  end

  it "returns 403 for a wrong token" do
    server = Shomen::Server.new
    cookie, _ = start_session(server)
    response = call_with(server, "POST", "/phase2/echo", cookie: cookie, body: form_body({"_csrf" => "wrong"}))
    response.status_code.should eq(403)
  end

  it "returns 403 for another session's token" do
    server = Shomen::Server.new
    cookie, _ = start_session(server)
    _, other_token = start_session(server)
    response = call_with(server, "POST", "/phase2/echo", cookie: cookie, body: form_body({"_csrf" => other_token}))
    response.status_code.should eq(403)
  end

  it "accepts the session's token" do
    server = Shomen::Server.new
    cookie, token = start_session(server)
    response = call_with(server, "POST", "/phase2/echo", cookie: cookie, body: form_body({"_csrf" => token}))
    response.status_code.should eq(200)
    response.body.should eq("accepted")
  end

  it "accepts the session's token after a restart with the same secret" do
    cookie, token = start_session(Shomen::Server.new(secret: "k"))
    response = call_with(Shomen::Server.new(secret: "k"), "POST", "/phase2/echo", cookie: cookie, body: form_body({"_csrf" => token}))
    response.status_code.should eq(200)
  end

  it "keeps the same token for the same session" do
    server = Shomen::Server.new
    cookie, token = start_session(server)
    call_with(server, "GET", "/phase2/token", cookie: cookie).body.should eq(token)
  end

  it "accepts a charset parameter on the form content type" do
    server = Shomen::Server.new
    cookie, token = start_session(server)
    response = call_with(server, "POST", "/phase2/echo", cookie: cookie, body: form_body({"_csrf" => token}),
      content_type: "application/x-www-form-urlencoded; charset=UTF-8")
    response.status_code.should eq(200)
  end

  it "does not read the token from a body that is not urlencoded" do
    server = Shomen::Server.new
    cookie, token = start_session(server)
    response = call_with(server, "POST", "/phase2/echo", cookie: cookie, body: form_body({"_csrf" => token}),
      content_type: "multipart/form-data; boundary=x")
    response.status_code.should eq(403)
  end

  it "checks PUT, PATCH, and DELETE" do
    %w(PUT PATCH DELETE).each do |verb|
      call_with(Shomen::Server.new, verb, "/phase2/echo", body: "").status_code.should eq(403)
    end
  end

  it "does not check GET" do
    call_with(Shomen::Server.new, "GET", "/phase2/token").status_code.should eq(200)
  end

  it "returns 400 HTML for a form body that is not UTF-8" do
    server = Shomen::Server.new
    cookie, token = start_session(server)
    response = call_with(server, "POST", "/phase2/echo", cookie: cookie, body: form_body({"_csrf" => token}) + "&name=%FF")
    response.status_code.should eq(400)
    response.body.should contain("<title>Bad input</title>")
  end

  it "returns 403 for a form body without a token even when it is not UTF-8" do
    server = Shomen::Server.new
    cookie, _ = start_session(server)
    call_with(server, "POST", "/phase2/echo", cookie: cookie, body: "name=%FF").status_code.should eq(403)
  end

  it "turns Shomen::Forbidden from a route into 403 HTML" do
    response = call_with(Shomen::Server.new, "GET", "/phase2/denied")
    response.status_code.should eq(403)
    response.body.should contain("<title>Forbidden</title>")
  end
end
```

`spec/shomen/router_spec.cr` の `handler.call(HTTP::Request.new(...))` の 3 か所を、引数を足した形にする:

```crystal
    handler.call(HTTP::Request.new("GET", "/phase1/people/new"), URI::Params.new, "").body.should eq("new")
```

```crystal
    handler.call(HTTP::Request.new("GET", "/phase1/people/%6Eew"), URI::Params.new, "").body.should eq("new")
```

```crystal
    handler.call(HTTP::Request.new("GET", "/phase1/people/8"), URI::Params.new, "").body.should eq("8")
```

- [ ] **Step 3: spec が失敗することを確認する**

Run: `crystal spec spec/shomen/csrf_spec.cr`
Expected: FAIL。`undefined constant Shomen::Forbidden`

- [ ] **Step 4: Forbidden を置く**

`src/shomen/forbidden.cr`:

```crystal
class Shomen::Forbidden < Exception
end
```

`src/shomen.cr` の `require "./shomen/bad_input"` の直後に `require "./shomen/forbidden"` を足す。

- [ ] **Step 5: Router の handler にフォームとトークンを足す**

`src/shomen/router.cr`:

```crystal
  record Entry, verb : String, pattern : String, shape : String, literals : Int32, handler : Proc(HTTP::Request, URI::Params, String, Shomen::Response)
```

```crystal
  def self.find(method : String, path : String) : Proc(HTTP::Request, URI::Params, String, Shomen::Response)?
```

`build_entries` の Proc:

```crystal
          ->(request : HTTP::Request, form : URI::Params, csrf_token : String) { {{klass}}.handle(request, form, csrf_token) },
```

- [ ] **Step 6: Route に csrf_token を渡す**

`src/shomen/route.cr` の `abstract class Shomen::Route` 直下（`module Hooks` の前）に足す:

```crystal
  property csrf_token : String = ""
```

`Hooks` の `handle` のシグネチャを次にする:

```crystal
      def self.handle(request : HTTP::Request, form : URI::Params = URI::Params.new, csrf_token : String = "") : Shomen::Response
```

`handle` の末尾の `new.call(input)` を次にする:

```crystal
            route = new
            route.csrf_token = csrf_token
            route.call(input)
```

- [ ] **Step 7: Server でフォームを読み、CSRF を検査する**

`src/shomen/server.cr` の変更点。先頭の require に `require "crypto/subtle"` を足す。クラス本体の `@@generated_secret` の前に定数を置く:

```crystal
  UNSAFE_METHODS = {"POST", "PUT", "PATCH", "DELETE"}
  FORM_TYPE      = "application/x-www-form-urlencoded"
  CSRF_FIELD     = "_csrf"
```

`call`、`dispatch`、`respond` を次にし、`read_form`、`check_encoding`、`csrf_valid?` を足す。文字コードの検査は CSRF の検査の後に行う。トークンの無い POST は、本文が UTF-8 でなくても 403 にする（D4）:

```crystal
  def call(context : HTTP::Server::Context) : Nil
    session = @sessions.load(context.request.cookies[Shomen::Session::COOKIE]?.try(&.value))
    write_response(context, respond(context.request, session), session)
  end

  def dispatch(request : HTTP::Request, form : URI::Params = URI::Params.new, csrf_token : String = "") : Shomen::Response
    handler = Shomen::Router.find(request.method, request.path)
    return error_response(404, "Not found", nil) unless handler
    handler.call(request, form, csrf_token)
  end

  private def respond(request : HTTP::Request, session : Shomen::Session) : Shomen::Response
    form = read_form(request)
    if UNSAFE_METHODS.includes?(request.method) && !csrf_valid?(form, session)
      return error_response(403, "Forbidden", nil)
    end
    check_encoding(form)
    dispatch(request, form, session.csrf_token)
  rescue ex : Shomen::BadInput
    error_response(400, "Bad input", ex.message)
  rescue ex : Shomen::Forbidden
    error_response(403, "Forbidden", nil)
  rescue ex : Shomen::NotFound
    error_response(404, "Not found", nil)
  rescue ex
    error_response(500, "Error", ex.message)
  end

  private def read_form(request : HTTP::Request) : URI::Params
    return URI::Params.new unless UNSAFE_METHODS.includes?(request.method)
    media_type = request.headers["Content-Type"]?.try(&.split(';').first.strip.downcase)
    return URI::Params.new unless media_type == FORM_TYPE
    URI::Params.parse(request.body.try(&.gets_to_end) || "")
  end

  private def check_encoding(form : URI::Params) : Nil
    form.each do |key, value|
      unless key.valid_encoding? && value.valid_encoding?
        raise Shomen::BadInput.new("invalid form encoding")
      end
    end
  end

  private def csrf_valid?(form : URI::Params, session : Shomen::Session) : Bool
    sent = form[CSRF_FIELD]?
    return false unless sent
    Crypto::Subtle.constant_time_compare(sent, session.csrf_token)
  end
```

- [ ] **Step 8: spec が通ることを確認する**

Run: `crystal spec`
Expected: PASS。0 failures。フィクスチャ `route_input_mismatch.cr` などは `handle(request)` の既定値で従来どおりコンパイルされること

---

### Task 4: フォームから Input を組む

**Files:**
- Modify: `src/shomen/route.cr`（`Hooks` の `handle` 本体）
- Modify: `spec/support/routes.cr`
- Create: `spec/fixtures/route_get_form_field.cr`
- Create: `spec/fixtures/route_form_bad_type.cr`
- Test: `spec/shomen/form_spec.cr`

**Interfaces:**
- Consumes: Task 3 の `handle(request, form, csrf_token)`、`call_with`、`ServerRoutes::Token`
- Produces:
  - GET/HEAD 以外のルートでは、path に無い `Input` のフィールドを `form` から読む。欠けていれば `Shomen::BadInput("missing <name>")`、整数に変換できなければ `Shomen::BadInput("invalid <name>")`
  - spec 用ルート `ServerRoutes::Signup`（`POST /phase2/signup`、`name : String`、`age : Int32`、本文は `"<name>:<age>"` をエスケープしたもの）、`ServerRoutes::Rename`（`POST /phase2/people/:id`、`id : Int64`、`name : String`、本文は `"<id>:<name>"`）

- [ ] **Step 1: spec 用ルートを足す**

`spec/support/routes.cr` の `module ServerRoutes` の末尾に足す:

```crystal
  class Signup < Shomen::Route
    method POST
    path "/phase2/signup"

    struct Input
      getter name : String
      getter age : Int32

      def initialize(@name : String, @age : Int32)
      end
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html(Shomen::HTML.escape("#{input.name}:#{input.age}"))
    end
  end

  class Rename < Shomen::Route
    method POST
    path "/phase2/people/:id"

    struct Input
      getter id : Int64
      getter name : String

      def initialize(@id : Int64, @name : String)
      end
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html(Shomen::HTML.escape("#{input.id}:#{input.name}"))
    end
  end
```

- [ ] **Step 2: 失敗する spec とフィクスチャを書く**

`spec/fixtures/route_get_form_field.cr`:

```crystal
require "../../src/shomen"

class GetFormField < Shomen::Route
  method GET
  path "/items"

  struct Input
    getter name : String

    def initialize(@name : String)
    end
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("x")
  end
end

GetFormField.handle(HTTP::Request.new("GET", "/items"))
```

`spec/fixtures/route_form_bad_type.cr`:

```crystal
require "../../src/shomen"

class FormBadType < Shomen::Route
  method POST
  path "/items"

  struct Input
    getter price : Float64

    def initialize(@price : Float64)
    end
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("x")
  end
end

FormBadType.handle(HTTP::Request.new("POST", "/items"))
```

`spec/shomen/form_spec.cr`:

```crystal
require "../spec_helper"

private def post(path : String) : HTTP::Request
  HTTP::Request.new("POST", path)
end

describe "form input" do
  it "binds form fields to Input" do
    response = ServerRoutes::Signup.handle(post("/phase2/signup"), URI::Params.parse("name=Ada&age=36"), "t")
    response.body.should eq("Ada:36")
  end

  it "binds a path parameter and a form field together" do
    response = ServerRoutes::Rename.handle(post("/phase2/people/7"), URI::Params.parse("name=Ada"), "t")
    response.body.should eq("7:Ada")
  end

  it "decodes plus signs and percent escapes" do
    response = ServerRoutes::Signup.handle(post("/phase2/signup"), URI::Params.parse("name=Ada+L%C3%B6v&age=36"), "t")
    response.body.should eq("Ada Löv:36")
  end

  it "uses the first value of a repeated field" do
    response = ServerRoutes::Signup.handle(post("/phase2/signup"), URI::Params.parse("name=Ada&name=Bob&age=36"), "t")
    response.body.should eq("Ada:36")
  end

  it "ignores fields that Input does not declare" do
    response = ServerRoutes::Signup.handle(post("/phase2/signup"), URI::Params.parse("_csrf=x&extra=1&name=Ada&age=36"), "t")
    response.body.should eq("Ada:36")
  end

  it "raises BadInput for a missing field" do
    expect_raises(Shomen::BadInput, "missing age") do
      ServerRoutes::Signup.handle(post("/phase2/signup"), URI::Params.parse("name=Ada"), "t")
    end
  end

  it "raises BadInput for a field that is not an integer" do
    ["abc", " 36", ""].each do |age|
      expect_raises(Shomen::BadInput, "invalid age") do
        ServerRoutes::Signup.handle(post("/phase2/signup"), URI::Params.new({"name" => ["Ada"], "age" => [age]}), "t")
      end
    end
  end

  it "hands the csrf token to the route" do
    ServerRoutes::Token.handle(HTTP::Request.new("GET", "/phase2/token"), URI::Params.new, "tok").body.should eq("tok")
  end

  it "returns 400 HTML through the server for a missing field" do
    server = Shomen::Server.new
    token_response = call_with(server, "GET", "/phase2/token")
    cookie = session_cookie(token_response)
    body = URI::Params.encode({"_csrf" => token_response.body, "name" => "Ada"})
    response = call_with(server, "POST", "/phase2/signup", cookie: cookie, body: body)
    response.status_code.should eq(400)
    response.body.should contain("missing age")
  end

  it "rejects a GET route whose Input has a field outside the path" do
    status, output = crystal_build_fixture("spec/fixtures/route_get_form_field.cr")
    status.should_not eq(0)
    output.should contain("must match path params")
  end

  it "rejects a form field type outside String, Int32, and Int64" do
    status, output = crystal_build_fixture("spec/fixtures/route_form_bad_type.cr")
    status.should_not eq(0)
    output.should contain("String, Int32, or Int64")
  end
end
```

- [ ] **Step 3: spec が失敗することを確認する**

Run: `crystal spec spec/shomen/form_spec.cr`
Expected: FAIL。`Signup` の `handle` がコンパイル時に `Input must match path params` を上げる

- [ ] **Step 4: handle のバインドを広げる**

`src/shomen/route.cr` の `Hooks` の `handle` 本体（`{% begin %}` から `{% end %}` まで）を次にする。シグネチャは Task 3 のまま。

```crystal
          {% begin %}
            {% path_node = @type.constant("PATH") %}
            {% if path_node.is_a?(Nop) %}
              {% raise "#{@type.name.stringify} must declare path" %}
            {% end %}
            {% input = @type.constant("Input") %}
            {% unless input.is_a?(TypeNode) %}
              {% raise "#{@type.name.stringify} must declare struct Input" %}
            {% end %}
            {% params = [] of Nil %}
            {% for part in path_node.split("/") %}
              {% if part.starts_with?(":") %}
                {% params << part[1..-1] %}
              {% end %}
            {% end %}
            {% ivars = {} of Nil => Nil %}
            {% for ivar in input.instance_vars %}
              {% ivars[ivar.name.stringify] = ivar.type.stringify %}
            {% end %}
            {% verb = @type.constant("VERB") %}
            {% reads_form = verb != "GET" && verb != "HEAD" %}
            {% fields = ivars.keys.reject { |name| params.includes?(name) } %}
            {% if params.any? { |name| ivars[name].is_a?(NilLiteral) } || (!reads_form && !fields.empty?) %}
              {% raise "#{@type.name.stringify} Input must match path params #{params}, found #{ivars.keys}" %}
            {% end %}
            {% for name in ivars.keys %}
              {% typ = ivars[name] %}
              {% unless typ == "Int32" || typ == "Int64" || typ == "String" %}
                {% raise "#{@type.name.stringify} field #{name} has type #{typ}, want String, Int32, or Int64" %}
              {% end %}
            {% end %}
            captures = ::Shomen::Router.captures!(PATH, request.path)
            input = Input.new(
              {% for name in ivars.keys %}
                {{name.id}}: begin
                  {% if params.includes?(name) %}
                    raw = captures[{{name}}]
                  {% else %}
                    raw = form[{{name}}]? || raise ::Shomen::BadInput.new("missing " + {{name}})
                  {% end %}
                  {% if ivars[name] == "Int32" %}
                    raw.to_i32?(whitespace: false) || raise ::Shomen::BadInput.new("invalid " + {{name}})
                  {% elsif ivars[name] == "Int64" %}
                    raw.to_i64?(whitespace: false) || raise ::Shomen::BadInput.new("invalid " + {{name}})
                  {% else %}
                    raw
                  {% end %}
                end,
              {% end %}
            )
            route = new
            route.csrf_token = csrf_token
            route.call(input)
          {% end %}
```

- [ ] **Step 5: spec が通ることを確認する**

Run: `crystal spec spec/shomen/form_spec.cr spec/shomen/route_spec.cr && crystal spec`
Expected: PASS。`route_input_mismatch.cr` と `route_bad_input_type.cr` の既存 spec も同じメッセージで通る

---

### Task 5: csrf_field と render の status

**Files:**
- Modify: `src/shomen/view.cr`
- Modify: `src/shomen/route.cr`（`render`）
- Modify: `spec/support/routes.cr`
- Test: `spec/shomen/view_spec.cr`、`spec/shomen/route_spec.cr`

**Interfaces:**
- Consumes: Task 3 の `csrf_token`、`ServerRoutes::HomeView`
- Produces:
  - `Shomen::View#csrf_field(token : String) : Nil`。`<input type="hidden" name="_csrf" value="...">` を書く
  - `Shomen::Route#render(view : Shomen::View, status : Int32 = 200) : Shomen::Response`
  - spec 用ルート `ServerRoutes::Invalid`（`POST /phase2/invalid`、`render HomeView.new, status: 422`）

- [ ] **Step 1: spec 用ルートを足す**

`spec/support/routes.cr` の `module ServerRoutes` の末尾に足す:

```crystal
  class Invalid < Shomen::Route
    method POST
    path "/phase2/invalid"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render HomeView.new, status: 422
    end
  end
```

- [ ] **Step 2: 失敗する spec を書く**

`spec/shomen/view_spec.cr` の private クラス群の後に足す:

```crystal
private class CsrfProbe < Shomen::View
  def to_html : String
    csrf_field("a\"b")
    result
  end
end
```

`describe Shomen::View` の中に足す:

```crystal
  it "writes the csrf field as an escaped hidden input" do
    CsrfProbe.new.to_html.should eq("<input type=\"hidden\" name=\"_csrf\" value=\"a&quot;b\">")
  end
```

`spec/shomen/route_spec.cr` の末尾の `describe` の中に足す:

```crystal
  it "renders a view with the status the route asks for" do
    response = ServerRoutes::Invalid.handle(HTTP::Request.new("POST", "/phase2/invalid"))
    response.status.should eq(422)
    response.content_type.should eq("text/html; charset=utf-8")
    response.body.should contain("<h1>Hello</h1>")
  end
```

- [ ] **Step 3: spec が失敗することを確認する**

Run: `crystal spec spec/shomen/view_spec.cr spec/shomen/route_spec.cr`
Expected: FAIL。`undefined method 'csrf_field'` と、`render` に `status` が無いこと

- [ ] **Step 4: 実装する**

`src/shomen/view.cr` の `def input(**attrs)` の後に足す:

```crystal
  def csrf_field(token : String) : Nil
    void_tag("input", {type: "hidden", name: "_csrf", value: token})
  end
```

`src/shomen/route.cr` の `render` を次にする:

```crystal
  def render(view : Shomen::View, status : Int32 = 200) : Shomen::Response
    Shomen::Response.html(view.to_html, status)
  end
```

- [ ] **Step 5: spec が通ることを確認する**

Run: `crystal spec`
Expected: PASS。0 failures

---

### Task 6: input のラベル検査

**Files:**
- Modify: `src/shomen/a11y.cr`
- Modify: `spec/shomen/view_spec.cr`（`VoidProbe` と対応する期待値）
- Create: `spec/fixtures/input_missing_label.cr`
- Create: `spec/fixtures/input_label_mismatch.cr`
- Create: `spec/fixtures/input_after_label_block.cr`
- Create: `spec/fixtures/input_label_in_string.cr`
- Create: `spec/fixtures/input_in_helper_method.cr`
- Test: `spec/shomen/a11y_spec.cr`

**Interfaces:**
- Consumes: Task 5 の `csrf_field`
- Produces:
  - `Shomen::View` のサブクラス（孫クラスを含む）で定義したメソッドの本体に、ラベルの無い `input` 呼び出しがあればコンパイルエラー。メッセージは `<Type> input needs a label: label for: matching id:, a wrapping label, or "aria-label"`
  - `Shomen::View.check_input_labels(source, type_name)` マクロ（内部用。`method_added` からだけ呼ぶ）

- [ ] **Step 1: 失敗するフィクスチャを書く**

5 ファイルとも同じ形で、クラス名と `to_html` の本体だけが違う。

`spec/fixtures/input_missing_label.cr`:

```crystal
require "../../src/shomen"

class InputMissingLabelView < Shomen::View
  def to_html : String
    input(type: "text", name: "q")
    result
  end
end

InputMissingLabelView.new.to_html
```

`spec/fixtures/input_label_mismatch.cr`:

```crystal
require "../../src/shomen"

class InputLabelMismatchView < Shomen::View
  def to_html : String
    label("Name", for: "other")
    input(id: "name", name: "name")
    result
  end
end

InputLabelMismatchView.new.to_html
```

`spec/fixtures/input_after_label_block.cr`:

```crystal
require "../../src/shomen"

class InputAfterLabelBlockView < Shomen::View
  def to_html : String
    label do
      text "Query"
    end
    input(name: "q")
    result
  end
end

InputAfterLabelBlockView.new.to_html
```

`spec/fixtures/input_label_in_string.cr`:

```crystal
require "../../src/shomen"

class InputLabelInStringView < Shomen::View
  def to_html : String
    p "label(for: \"a\")"
    input(id: "a", name: "a")
    result
  end
end

InputLabelInStringView.new.to_html
```

`spec/fixtures/input_in_helper_method.cr`:

```crystal
require "../../src/shomen"

class InputInHelperMethodView < Shomen::View
  def to_html : String
    label("Name", for: "name")
    field
    result
  end

  private def field : Nil
    input(id: "name", name: "name")
  end
end

InputInHelperMethodView.new.to_html
```

- [ ] **Step 2: 失敗する spec を書く**

`spec/shomen/a11y_spec.cr` の `private class Page` の後に足す:

```crystal
private class LabeledForm < Shomen::View
  def to_html : String
    form(action: "/save", method: "post") do
      csrf_field("tok")
      label("Name", for: "name")
      input(id: "name", name: "name", type: "text")
      label do
        text "Email"
        input(name: "email", type: "email")
      end
      input(name: "q", type: "search", "aria-label": "Search")
      input(type: "hidden", name: "step", value: "1")
    end
    result
  end
end

private class LabeledBase < Shomen::View
  def to_html : String
    result
  end
end

private class LabeledChild < LabeledBase
  def to_html : String
    label do
      input(name: "q")
    end
    result
  end
end
```

`describe Shomen::View` の中に足す:

```crystal
  it "accepts inputs with a for label, a wrapping label, aria-label, or hidden type" do
    html = LabeledForm.new.to_html
    html.should contain("<input type=\"hidden\" name=\"_csrf\" value=\"tok\">")
    html.should contain("<label for=\"name\">Name</label><input id=\"name\" name=\"name\" type=\"text\">")
    html.should contain("<label>Email<input name=\"email\" type=\"email\"></label>")
    html.should contain("<input name=\"q\" type=\"search\" aria-label=\"Search\">")
    html.should contain("<input type=\"hidden\" name=\"step\" value=\"1\">")
  end

  it "checks a view that inherits from another view" do
    LabeledChild.new.to_html.should eq("<label><input name=\"q\"></label>")
  end

  {
    "input_missing_label"     => "an input without a label",
    "input_label_mismatch"    => "a label whose for does not match the input id",
    "input_after_label_block" => "an input after a label block closes",
    "input_label_in_string"   => "a label call that only appears inside a string",
    "input_in_helper_method"  => "an input whose label is in another method",
  }.each do |fixture, description|
    it "rejects #{description}" do
      status, output = crystal_build_fixture("spec/fixtures/#{fixture}.cr")
      status.should_not eq(0)
      output.should contain("input needs a label")
    end
  end
```

`spec/shomen/view_spec.cr` の `VoidProbe` を次にする:

```crystal
private class VoidProbe < Shomen::View
  def to_html : String
    meta(charset: "utf-8")
    input(type: "text", name: "q", "aria-label": "Query")
    result
  end
end
```

同じファイルで `<input type=\"text\" name=\"q\">` を期待している行を次にする:

```crystal
    html.should contain("<input type=\"text\" name=\"q\" aria-label=\"Query\">")
```

- [ ] **Step 3: spec が失敗することを確認する**

Run: `crystal spec spec/shomen/a11y_spec.cr`
Expected: FAIL。5 つの `rejects ...` がコンパイル成功（status 0）で落ちる

- [ ] **Step 4: ラベル検査を実装する**

`src/shomen/a11y.cr` の `class Shomen::View` の中（`macro img` の後）に足す:

```crystal
  macro inherited
    macro method_added(method)
      ::Shomen::View.check_input_labels(\{{method.body.stringify}}, \{{@type.name.stringify}})
    end
  end

  # method.body.stringify prints one statement per line with two-space
  # indentation, so a label block's extent is found by indentation.
  macro check_input_labels(source, type_name)
    {% lines = source.lines %}
    {% codes = lines.map { |line| line.gsub(/"(?:[^"\\]|\\.)*"/, "\"\"").gsub(/\/(?:\\.|[^\/\n])*\/[a-z]*/, "") } %}
    {% fors = [] of Nil %}
    {% for line, index in lines %}
      {% if codes[index] =~ /(^|[^.\w])label(\(|\s|$)/ %}
        {% for found in line.scan(/\bfor: "((?:[^"\\]|\\.)*)"/) %}
          {% fors << found[1] %}
        {% end %}
      {% end %}
    {% end %}
    {% open = [] of Nil %}
    {% for line, index in lines %}
      {% code = codes[index] %}
      {% indent = line.size - line.gsub(/^ +/, "").size %}
      {% if code.strip == "end" && !open.empty? && open.last >= indent %}
        {% open = open.size == 1 ? [] of Nil : open[0..-2] %}
      {% end %}
      {% if code =~ /(^|[^.\w])label(\(.*\))? do\b/ %}
        {% open << indent %}
      {% elsif code =~ /(^|[^.\w])input(\(|\s*$)/ %}
        {% ok = !open.empty? || line.includes?("type: \"hidden\"") || line.includes?("\"aria-label\": ") %}
        {% unless ok %}
          {% ids = line.scan(/\bid: "((?:[^"\\]|\\.)*)"/) %}
          {% ok = !ids.empty? && fors.includes?(ids[0][1]) %}
        {% end %}
        {% unless ok %}
          {% raise "#{type_name.id} input needs a label: label for: matching id:, a wrapping label, or \"aria-label\"" %}
        {% end %}
      {% end %}
    {% end %}
  end
```

`macro inherited` の中の `macro method_added` は `\{{ }}` でエスケープする。外側の `inherited` の展開時ではなく、サブクラスでメソッドが定義されたときに評価させるためである。判定ロジックを `inherited` の本体に直接書くと、`do` や `end` を含む文字列を外側のマクロ字句解析が数えてしまい、`unterminated macro` になる。そのため判定は別マクロ `check_input_labels` に分けている。

- [ ] **Step 5: spec が通ることを確認する**

Run: `crystal spec spec/shomen/a11y_spec.cr spec/shomen/view_spec.cr && crystal spec`
Expected: PASS。0 failures。`ErrorView` と既存の spec 用ビューもコンパイルが通る

---

### Task 7: examples/hello のフォーム

**Files:**
- Modify: `examples/hello/src/hello.cr`
- Modify: `examples/hello/spec/spec_helper.cr`
- Test: `examples/hello/spec/greeting_spec.cr`

**Interfaces:**
- Consumes: Task 2 の `Shomen::Server.new`、Task 3 の `csrf_token`、Task 4 のフォームバインド、Task 5 の `csrf_field` と `render(view, status:)`、Task 6 のラベル検査
- Produces: `Greeting::EditView`、`Greeting::Edit`（`GET /greeting`）、`Greeting::Update`（`POST /greeting`）

- [ ] **Step 1: 失敗する spec を書く**

`examples/hello/spec/spec_helper.cr`:

```crystal
require "spec"
ENV["SHOMEN_SPEC"] = "1"
ENV["SHOMEN_SECRET"] = "spec-secret"
require "../src/hello"
```

`examples/hello/spec/greeting_spec.cr`:

```crystal
require "./spec_helper"
require "http/client"

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

private def open_form(server : Shomen::Server) : {String, String}
  response = request(server, "GET", "/greeting")
  cookie = response.headers["Set-Cookie"].split(';').first
  token = response.body.match(/name="_csrf" value="([^"]+)"/).not_nil![1]
  {cookie, token}
end

describe Greeting do
  it "shows the form with a label, a csrf field, and a session cookie" do
    response = request(Shomen::Server.new, "GET", "/greeting")
    response.status_code.should eq(200)
    response.body.should contain("<label for=\"name\">Name</label>")
    response.body.should contain("name=\"_csrf\"")
    response.headers["Set-Cookie"].should start_with("shomen_session=")
  end

  it "redisplays the submitted value with 422 when it is too short" do
    server = Shomen::Server.new
    cookie, token = open_form(server)
    body = URI::Params.encode({"_csrf" => token, "name" => "<"})
    response = request(server, "POST", "/greeting", cookie, body)
    response.status_code.should eq(422)
    response.body.should contain("value=\"&lt;\"")
    response.body.should contain("Name must be at least 2 characters")
  end

  it "redirects with 303 when the name is valid" do
    server = Shomen::Server.new
    cookie, token = open_form(server)
    body = URI::Params.encode({"_csrf" => token, "name" => "Ada"})
    response = request(server, "POST", "/greeting", cookie, body)
    response.status_code.should eq(303)
    response.headers["Location"].should eq("/greeting")
  end

  it "rejects a POST without the csrf token" do
    server = Shomen::Server.new
    cookie, _ = open_form(server)
    request(server, "POST", "/greeting", cookie, "name=Ada").status_code.should eq(403)
  end

  it "exposes the declared path" do
    Greeting::Edit.path.should eq("/greeting")
  end
end
```

- [ ] **Step 2: spec が失敗することを確認する**

Run: `cd examples/hello && shards install && crystal spec`
Expected: FAIL。`undefined constant Greeting`

- [ ] **Step 3: 例を実装する**

`examples/hello/src/hello.cr` の `module Hello ... end` の後、`Shomen::Server.start` の前に足す:

```crystal
module Greeting
  class EditView < Shomen::View
    def initialize(@name : String, @token : String, @error : String?)
    end

    def to_html : String
      name = @name
      token = @token
      error = @error
      html lang: "en" do
        head do
          title "Greeting"
        end
        body do
          main do
            h1 "Greeting"
            if message = error
              p message
            end
            form(action: Greeting::Update.path, method: "post") do
              csrf_field(token)
              label("Name", for: "name")
              input(id: "name", name: "name", type: "text", value: name)
              button "Save", type: "submit"
            end
          end
        end
      end
    end
  end

  class Edit < Shomen::Route
    method GET
    path "/greeting"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render EditView.new("", csrf_token, nil)
    end
  end

  class Update < Shomen::Route
    method POST
    path "/greeting"

    struct Input
      getter name : String

      def initialize(@name : String)
      end
    end

    def call(input : Input) : Shomen::Response
      if input.name.strip.size < 2
        return render EditView.new(input.name, csrf_token, "Name must be at least 2 characters"), status: 422
      end
      redirect Edit.path
    end
  end
end
```

- [ ] **Step 4: spec が通ることを確認する**

Run: `cd examples/hello && shards install && crystal spec`
Expected: PASS。既存の 2 件と合わせて 7 examples, 0 failures

- [ ] **Step 5: 手で動かして確かめる**

別の端末で `cd examples/hello && crystal run src/hello.cr` を起動し、次を実行する:

```sh
jar="$(mktemp)"
token="$(curl -s -c "$jar" http://127.0.0.1:3000/greeting | sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p')"
curl -s -b "$jar" -o /dev/null -w '%{http_code}\n' --data-urlencode "_csrf=$token" --data-urlencode "name=A" http://127.0.0.1:3000/greeting
curl -s -b "$jar" -o /dev/null -w '%{http_code}\n' --data-urlencode "name=Ada" http://127.0.0.1:3000/greeting
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/
rm -f "$jar"
```

Expected: `422`、`403`、`200` の順。サーバの起動時に `SHOMEN_SECRET is not set` の警告が 1 行出る。確認したらサーバを止める。

---

### Task 8: README と CONTRIBUTING を反映し、受入を確かめる

**Files:**
- Modify: `README.md`、`README.ja.md`（冒頭のバージョン段落、`## Phase 1 is what runs` / `## いま動くのはフェーズ 1` の節）
- Modify: `CONTRIBUTING.md`、`CONTRIBUTING.ja.md`（30 行目）

**Interfaces:**
- Consumes: Task 1〜7 のすべて
- Produces: なし

- [ ] **Step 1: README.md を直す**

7 行目を次にする:

```markdown
Version 0.0.0. Phases 1 and 2 are in the tree: typed routes, a typed HTML DSL, an HTTP server, form binding, a signed session cookie, and CSRF protection. Later phases are specified and not implemented. There is no release tag yet.
```

`## Phase 1 is what runs` の節を次にする（`## Specification` の直前まで）:

```markdown
## Phases 1 and 2 are what run

Phase 1 builds these:

- HTML elements listed in the specification, plus escaping
- Compile-time checks for `html` `lang`, one `title`, `button` `type`, and `img` `alt`
- Route declarations, registration, and path helpers
- HTTP responses 200, 400, 404, and 500
- `examples/hello`

Phase 2 adds these:

- `Input` fields from a urlencoded form POST. A missing or malformed field is 400
- `render(view, status: 422)` to redisplay a form
- A signed `shomen_session` cookie. The key is `SHOMEN_SECRET`. Without it, a random key lasts until restart
- A CSRF token in the session. `csrf_field(csrf_token)` writes it into a form. POST, PUT, PATCH, and DELETE without the matching `_csrf` return 403
- A compile-time check that every `input` has a `label` with a matching `for`, a wrapping `label`, or `"aria-label"`. `type: "hidden"` is exempt
- `GET /greeting` and `POST /greeting` in `examples/hello`

These are specified for later phases and are not in the code: SQLite, commands and events, HTML fragments, the official JavaScript file, SSE, and islands.

The phase list is in [docs/en/02-PHASES.md](docs/en/02-PHASES.md).
```

- [ ] **Step 2: README.ja.md を同じ内容に直す**

7 行目を次にする:

```markdown
バージョンは 0.0.0 です。リポジトリに入っているのはフェーズ 2 までで、型付きルート、型付き HTML、HTTP サーバ、フォームの束縛、署名付きセッション Cookie、CSRF 対策が動きます。それより後のフェーズは仕様にあり、実装はまだありません。リリースタグもまだありません。
```

`## いま動くのはフェーズ 1` の節を次にする（`## 仕様` の直前まで）:

```markdown
## いま動くのはフェーズ 1 と 2

フェーズ 1 で入っているもの:

- 仕様にある HTML 要素と、テキストのエスケープ
- `html` の `lang`、`title` が 1 つ、`button` の `type`、`img` の `alt` というコンパイル時検査
- ルート宣言、登録、path helper
- 200 / 400 / 404 / 500
- `examples/hello`

フェーズ 2 で足したもの:

- urlencoded の form POST から `Input` のフィールドを組む。欠けたフィールドや不正な値は 400
- フォームを描き直すための `render(view, status: 422)`
- 署名付きの `shomen_session` Cookie。鍵は `SHOMEN_SECRET` で、未設定なら再起動まで有効なランダムな鍵を使う
- セッションに入った CSRF トークン。`csrf_field(csrf_token)` でフォームに書く。一致する `_csrf` が無い POST、PUT、PATCH、DELETE は 403
- すべての `input` に、`for` が一致する `label`、囲む `label`、`"aria-label"` のいずれかを求めるコンパイル時検査。`type: "hidden"` は対象外
- `examples/hello` の `GET /greeting` と `POST /greeting`

SQLite、コマンドとイベント、HTML 断片、公式 JavaScript、SSE、島は、後のフェーズの仕様であり、コードにはありません。

フェーズの一覧は [docs/en/02-PHASES.md](docs/en/02-PHASES.md) にあります。日本語訳は [docs/02-PHASES.md](docs/02-PHASES.md) です。
```

- [ ] **Step 3: CONTRIBUTING を直す**

`CONTRIBUTING.md` 30 行目:

```markdown
- No new shard unless the spec names it. Phases 0–2 have no dependencies.
```

`CONTRIBUTING.ja.md` 30 行目:

```markdown
- 仕様が名前を挙げた shard 以外は足しません。フェーズ 0〜2 の依存はゼロです。
```

- [ ] **Step 4: 受入をまとめて確かめる**

Run:

```sh
crystal tool format --check src spec examples
crystal spec
crystal build src/shomen.cr --error-trace
rm -f shomen
cd examples/hello && shards install && crystal spec
```

Expected: format の差分なし。本体の spec は 0 failures、警告なし。ビルドが成功する。hello は 7 examples, 0 failures。`shard.yml` に `dependencies` が無い。

受入との対応:

- 「フォームを 1 つ持つ例が、送信後に値を表示し直す」→ `greeting_spec.cr` の `redisplays the submitted value with 422`
- 「CSRF の無い POST は 403」→ `csrf_spec.cr` と `greeting_spec.cr` の `rejects a POST without the csrf token`
- 「セッションの無い応答に `Set-Cookie` が付く」→ `session_spec.cr` の `sets a session cookie on a response to a request without one`

満たしたら止まり、ユーザーの次の指示を待つ（現行フェーズの規則）。
