# Phase 1 Routes, HTML, and Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** フェーズ 1 の受入まで届ける。型付き HTML 文書、ルート宣言、path helper、`HTTP::Server` の 200 / 400 / 404 / 500、`examples/hello` の `GET /` が `<h1>Hello</h1>` を含む文書を返す。

**Architecture:** `Shomen::View` がバッファへ要素を書き、`html` / `button` / `img` だけがコンパイル時マクロになる。ルートは `Shomen::Route` の具象サブクラスで、`method` と `path` が定数を置き、`handle` が `Input` を組んで `call` する。ルート表は `Shomen::Route.all_subclasses` から `Shomen::Router.entries` の初回呼び出しで作る。`Shomen::Server` はその表を引き、セキュリティヘッダを付けて `HTTP::Server::Response` へ書く。

**Tech Stack:** Crystal `>= 1.20.0`（開発機は 1.21.1）、標準ライブラリの `spec`、`http/server`、`http/server/handler`、`uri`。外部 shard は足さない。

**Spec:** `docs/00-INSTRUCTION.md` の「2. ルート宣言」「3. ビュー / HTML」「4. レスポンス」「5. サーバ」「9. エラーモデル」と「TDD」の 1–6、`docs/01-ARCHITECTURE.md` のリクエスト経路とモジュール境界、`docs/02-PHASES.md` のフェーズ 1、`docs/03-CONVENTIONS.md`。

## Global Constraints

- 言語は Crystal 1.20 以上。`shard.yml` の下限は `>= 1.20.0` のまま。
- フェーズ 1 の本体 shard に依存キーを足さない。`shard.lock` は `shards: {}` のまま。
- 公開 API は `Shomen::` 配下だけ。
- コードと識別子は英語。この計画、決定ログ、`docs/02-PHASES.md` の追記は日本語。
- フェーズ 2 以降の機能は作らない。セッション、CSRF、SQLite、コマンド、断片、JSON、SSE、島、CSP、本番の例外秘匿は範囲外。
- `render_fragment` はフェーズ 4 まで作らない。
- `input` のラベル検査（`for` / ラップ / `aria-label`）はフェーズ 1 の a11y 列挙に無い。フェーズ 2 の作るものへ移す。フェーズ 1 は `input` をただの要素として出す。
- ユーザーが指示するまで commit しない。この計画に commit 手順は無い。
- `crystal tool format` を通し、警告を残して完了にしない。
- テストはポートを bind しない。`HTTP::Server::Response` を `IO::Memory` に書く。ポート 3000 を使うのは Task 8 の手動確認だけ。
- 検証でリポジトリルートにできる実行ファイル `shomen` は、`docs/decisions/20260928-build-artifact.md` のとおり削除する。

実行はリポジトリルートで行う。フェーズ 0 の `Shomen::VERSION` は `"0.0.0"` のまま変えない。

## Review Focus

- 静的パスとパラメータパスが同じ URL に両方合う。`GET /users/new` は `GET /users/:id` より先に選ばれる。Task 6 の spec で固定する。
- 例外メッセージの `<` が 500 の本文に生で出る。エスケープされた `&lt;` だけが出る。Task 7 の spec で固定する。
- テキスト中の単語 `title` を文書の `<title>` と数えてしまう、または `<title>` が無い文書が通る。Task 3 の成功 spec とコンパイル失敗フィクスチャで固定する。
- `&` を後から置換して `&amp;amp;` にする、または属性値の `"` を素通しする。Task 1 と Task 2 の spec で固定する。
- `/users/:id` と `/users/:name` を別ルートとして両方登録する。shape が同じなので起動時に失敗する。Task 6 の別プロセス spec で固定する。

## File Map

| ファイル | 役割 |
|---|---|
| `src/shomen/html.cr` | `Shomen::HTML.escape` |
| `src/shomen/view.cr` | `Shomen::View`、要素メソッド、`text` / `raw` |
| `src/shomen/a11y.cr` | `html` / `button` / `img` マクロ |
| `src/shomen/not_found.cr` | `Shomen::NotFound` |
| `src/shomen/bad_input.cr` | `Shomen::BadInput` |
| `src/shomen/response.cr` | `Shomen::Response` |
| `src/shomen/route.cr` | `Shomen::Route`、`method` / `path` / `handle` |
| `src/shomen/router.cr` | 照合、キャプチャ、ルート表 |
| `src/shomen/error_view.cr` | 400 / 404 / 500 の文書 |
| `src/shomen/server.cr` | `Shomen::Server` |
| `src/shomen.cr` | 上記を require する |
| `spec/shomen/html_spec.cr` | エスケープ |
| `spec/shomen/view_spec.cr` | 要素、`raw`、属性 |
| `spec/shomen/a11y_spec.cr` | 正しい文書と、コンパイル失敗 |
| `spec/fixtures/*.cr` | 失敗させたい単独プログラム |
| `spec/shomen/response_spec.cr` | status と redirect |
| `spec/support/routes.cr` | spec プロセス内のルートクラス |
| `spec/shomen/route_spec.cr` | path helper と `handle` |
| `spec/shomen/router_spec.cr` | 照合と二重登録 |
| `spec/shomen/server_spec.cr` | 200 / 400 / 404 / 500 とヘッダ |
| `examples/hello/**` | 最小アプリ |
| `docs/02-PHASES.md` | 現行フェーズを 1 にし、ラベル検査をフェーズ 2 へ書く |
| `docs/decisions/20260928-phase1-*.md` | この計画で固定した細部 |

作らないファイル: `src/shomen/handler.cr`、`src/shomen/session.cr`、`src/shomen/command.cr`、`examples/hello` 以外の example。

## 範囲外

- `render_fragment`、JSON 応答、クエリの業務利用、リクエストボディ。
- 405。メソッド違いの未照合は 404。
- `SHOMEN_ENV`。500 は常に例外メッセージをエスケープして出す。隠すのはフェーズ 6。
- CSP。セキュリティヘッダは次の 3 つだけ。`X-Content-Type-Options: nosniff`、`Referrer-Policy: no-referrer`、`X-Frame-Options: DENY`。
- path パラメータの型は `String`、`Int32`、`Int64` だけ。それ以外はコンパイル失敗。
- フェーズ 1 の `Input` のインスタンス変数は path パラメータと過不足なく一致する。フォーム用の余分なフィールドはフェーズ 2 でこの規則を広げる。
- 末尾スラッシュは別パス。`/hello/` は `/hello` に合わない。
- `macro finished` で実行時登録しない。Crystal はその生成コードをファイル末尾で走らせる。`Server.start` が `listen` でブロックすると登録が走らない。登録は `Router.entries` の初回呼び出しで行う。

---

### Task 1: 現行フェーズと HTML エスケープ

**Files:**

- Modify: `docs/02-PHASES.md`
- Create: `docs/decisions/20260928-phase1-html.md`
- Create: `src/shomen/html.cr`
- Create: `spec/shomen/html_spec.cr`
- Modify: `src/shomen.cr`
- Test: `spec/shomen/html_spec.cr`

**Interfaces:**

- Consumes: `Shomen` モジュール（フェーズ 0）
- Produces: `Shomen::HTML.escape(text : String) : String`

- [ ] **Step 1: 現行フェーズをフェーズ 1 に切り替え、ラベル検査の行き先を書く**

`docs/02-PHASES.md` の先頭を次に置き換える。

```markdown
## 現行フェーズ

**フェーズ 1 — ルートと HTML とサーバ**

フェーズ 0 の受入は満たした。ここより先（フェーズ 2 以降）を実装しない。1 の受入を満たしたら停止し、ユーザーの次指示を待つ。
```

フェーズ 2 の「作るもの」に次の 1 行を足す。

```markdown
- `input` のコンパイル時ラベル検査（同一ビュー内の `for` / ラップ、または `aria-label`）。フェーズ 1 は `input` 要素を出すだけで、この検査はしない
```

`docs/decisions/20260928-phase1-html.md` を置く。

```markdown
# 状況

仕様 3 は `input` のラベル検査をコンパイル時の規則にしている。フェーズ 1 の a11y は `button@type`、`img@alt`、文書の `lang` と `title` だけを名指ししている。`redirect` は仕様 4 にあり、後のフェーズの作るものに出てこない。`render_fragment` はフェーズ 4 にある。

# 決定

フェーズ 1 のコンパイル時検査は `html` の `lang`、文書内の `title` が字句上ちょうど 1 つ、`button` の `type`、`img` の `alt` だけにする。`lang`、`type`、`alt` は文字列リテラルだけを受け、`lang` は `en` や `zh-Hant` の形に限る。`title` の個数は、`html` ブロックのソースから文字列リテラルを消したあとの `title(...)` または `title do` の個数で数える。`redirect` はフェーズ 1 の `Shomen::Response` に置く。`render_fragment` は置かない。`input` のラベル検査はフェーズ 2 に回し、その旨を `docs/02-PHASES.md` のフェーズ 2 に書く。

# 理由

フェーズ文書の「うち」が、今やる検査の境界である。ラベル検査をフェーズ一覧から落とすと、後で誰も実装しない。`redirect` は応答型を導入する今しか置き場が無い。タイトル数は、別マクロをコンパイル時に再帰呼び出しできないため、ブロックソースの走査で数える。

# 破棄した案

- フェーズ 1 で `input` のラベル検査まで実装する
- `title` を `html` の名前付き引数だけにして要素メソッドを作らない
- `redirect` をフェーズ 2 まで延期する
```

- [ ] **Step 2: 失敗する spec を書く**

`spec/shomen/html_spec.cr`

```crystal
require "../spec_helper"

describe Shomen::HTML do
  it "escapes text for HTML" do
    Shomen::HTML.escape("&<>\"'").should eq("&amp;&lt;&gt;&quot;&#39;")
  end

  it "escapes ampersand first" do
    Shomen::HTML.escape("&amp;").should eq("&amp;amp;")
  end

  it "leaves plain text unchanged" do
    Shomen::HTML.escape("plain").should eq("plain")
  end
end
```

- [ ] **Step 3: spec が未定義で失敗することを確認する**

Run: `crystal spec spec/shomen/html_spec.cr --error-trace`

Expected: FAIL。`Shomen::HTML` が未定義。

- [ ] **Step 4: escape を実装し、入口から require する**

`src/shomen/html.cr`

```crystal
module Shomen
  module HTML
    def self.escape(text : String) : String
      text.gsub('&', "&amp;")
        .gsub('<', "&lt;")
        .gsub('>', "&gt;")
        .gsub('"', "&quot;")
        .gsub('\'', "&#39;")
    end
  end
end
```

`src/shomen.cr` を次にする。

```crystal
require "./shomen/version"
require "./shomen/html"

module Shomen
end
```

- [ ] **Step 5: spec が通ることを確認する**

Run: `crystal spec spec/shomen/html_spec.cr --error-trace`

Expected: PASS。出力に `Warning` は無い。

Run: `crystal tool format src/shomen.cr src/shomen/html.cr spec/shomen/html_spec.cr`

---

### Task 2: 要素、テキスト、raw、属性

**Files:**

- Create: `src/shomen/view.cr`
- Create: `spec/shomen/view_spec.cr`
- Modify: `src/shomen.cr`
- Test: `spec/shomen/view_spec.cr`

**Interfaces:**

- Consumes: `Shomen::HTML.escape`
- Produces: `abstract class Shomen::View`。`abstract def to_html : String`。`text(value)`、`raw(value : String)`、`protected def result : String`。内容を取る要素とブロックを取る要素。void 要素 `meta` と `input`。対象タグは `head`、`body`、`header`、`main`、`footer`、`nav`、`h1`、`h2`、`h3`、`p`、`div`、`span`、`ul`、`ol`、`li`、`a`、`form`、`label`、`textarea`、`title`、`meta`、`input`。

ブロック内の裸の文字列はテキストノードにしない。テキストは `h1 "Hello"` のように内容引数へ渡すか、`text` を呼ぶ。

- [ ] **Step 1: 失敗する spec を書く**

`spec/shomen/view_spec.cr`

```crystal
require "../spec_helper"

private class TagProbe < Shomen::View
  def initialize(@tag : String, @content : String)
  end

  def to_html : String
    case @tag
    when "head"      then head(@content)
    when "body"      then body(@content)
    when "header"    then header(@content)
    when "main"      then main(@content)
    when "footer"    then footer(@content)
    when "nav"       then nav(@content)
    when "h1"        then h1(@content)
    when "h2"        then h2(@content)
    when "h3"        then h3(@content)
    when "p"         then p(@content)
    when "div"       then div(@content)
    when "span"      then span(@content)
    when "ul"        then ul(@content)
    when "ol"        then ol(@content)
    when "li"        then li(@content)
    when "a"         then a(@content)
    when "form"      then form(@content)
    when "label"     then label(@content)
    when "textarea"  then textarea(@content)
    when "title"     then title(@content)
    else                  raise "unknown tag #{@tag}"
    end
    result
  end
end

private class EscapeProbe < Shomen::View
  def to_html : String
    h1("<Hi & Co>")
    result
  end
end

private class RawProbe < Shomen::View
  def to_html : String
    div do
      raw("<b>ok</b>")
    end
    result
  end
end

private class AttributeProbe < Shomen::View
  def to_html : String
    a("Hello", href: "/a?b=1&c=2")
    result
  end
end

private class LabelForProbe < Shomen::View
  def to_html : String
    label("Name", for: "name", class: "field")
    result
  end
end

private class VoidProbe < Shomen::View
  def to_html : String
    meta(charset: "utf-8")
    input(type: "text", name: "q")
    result
  end
end

describe Shomen::View do
  %w(head body header main footer nav h1 h2 h3 p div span ul ol li a form label textarea title).each do |tag|
    it "renders #{tag}" do
      html = TagProbe.new(tag, "Hi").to_html
      html.should contain("<#{tag}>Hi</#{tag}>")
    end
  end

  it "escapes element text" do
    EscapeProbe.new.to_html.should contain("<h1>&lt;Hi &amp; Co&gt;</h1>")
  end

  it "inserts raw markup only through raw" do
    RawProbe.new.to_html.should contain("<div><b>ok</b></div>")
  end

  it "escapes attribute values" do
    AttributeProbe.new.to_html.should contain("<a href=\"/a?b=1&amp;c=2\">Hello</a>")
  end

  it "accepts for and class attributes" do
    LabelForProbe.new.to_html.should contain("<label for=\"name\" class=\"field\">Name</label>")
  end

  it "renders void elements without a closing tag" do
    html = VoidProbe.new.to_html
    html.should contain("<meta charset=\"utf-8\">")
    html.should contain("<input type=\"text\" name=\"q\">")
    html.should_not contain("</input>")
    html.should_not contain("</meta>")
  end
end
```

- [ ] **Step 2: spec が失敗することを確認する**

Run: `crystal spec spec/shomen/view_spec.cr --error-trace`

Expected: FAIL。`Shomen::View` が未定義。

- [ ] **Step 3: View を実装する**

`src/shomen/view.cr`

```crystal
abstract class Shomen::View
  abstract def to_html : String

  def initialize
    @out = IO::Memory.new
  end

  def text(value) : Nil
    @out << Shomen::HTML.escape(value.to_s)
  end

  def raw(value : String) : Nil
    @out << value
  end

  protected def result : String
    @out.to_s
  end

  protected def reset : Nil
    @out = IO::Memory.new
  end

  private def open_tag(name : String, attrs) : Nil
    @out << "<" << name
    write_attributes(attrs)
    @out << ">"
  end

  private def close_tag(name : String) : Nil
    @out << "</" << name << ">"
  end

  private def void_tag(name : String, attrs) : Nil
    @out << "<" << name
    write_attributes(attrs)
    @out << ">"
  end

  private def write_attributes(attrs) : Nil
    attrs.each do |key, value|
      @out << " " << key.to_s << "=\"" << Shomen::HTML.escape(value.to_s) << "\""
    end
  end

  {% for name in %w(head body header main footer nav h1 h2 h3 p div span ul ol li a form label textarea title) %}
    def {{name.id}}(content : String, **attrs) : Nil
      open_tag({{name}}, attrs)
      text(content)
      close_tag({{name}})
    end

    def {{name.id}}(**attrs, &) : Nil
      open_tag({{name}}, attrs)
      yield
      close_tag({{name}})
    end
  {% end %}

  def meta(**attrs) : Nil
    void_tag("meta", attrs)
  end

  def input(**attrs) : Nil
    void_tag("input", attrs)
  end
end
```

`src/shomen.cr` の require に `require "./shomen/view"` を `html` の次へ足す。

- [ ] **Step 4: spec が通ることを確認する**

Run: `crystal spec spec/shomen/view_spec.cr --error-trace`

Expected: PASS。出力に `Warning` は無い。属性の並びが Crystal の NamedTuple 順と違って失敗したら、spec の期待文字列をその順に合わせる。エスケープ結果は変えない。

Run: `crystal tool format src/shomen/view.cr spec/shomen/view_spec.cr src/shomen.cr`

---

### Task 3: 文書マクロと a11y

**Files:**

- Create: `src/shomen/a11y.cr`
- Create: `spec/shomen/a11y_spec.cr`
- Create: `spec/fixtures/missing_title.cr`
- Create: `spec/fixtures/two_titles.cr`
- Create: `spec/fixtures/button_missing_type.cr`
- Create: `spec/fixtures/button_bad_type.cr`
- Create: `spec/fixtures/button_dynamic_type.cr`
- Create: `spec/fixtures/img_missing_alt.cr`
- Create: `spec/fixtures/html_missing_lang.cr`
- Modify: `src/shomen.cr`
- Test: `spec/shomen/a11y_spec.cr`

**Interfaces:**

- Consumes: `Shomen::View#text`、`#reset`、`#result`、`@out`
- Produces: ビュー上のマクロ `html(lang, &block)`、`button(content = nil, type = nil, **attrs, &block)`、`img(alt = nil, **attrs)`。`html` は `<!DOCTYPE html><html lang="...">` で始まり `</html>` で終わる `String` を返す。

コンパイル失敗フィクスチャは、検査対象メソッドをトップレベルで呼ぶ。呼ばないメソッドの中のマクロは Crystal が展開しない。

- [ ] **Step 1: 成功 spec とコンパイル失敗 spec を書く**

`spec/shomen/a11y_spec.cr`

```crystal
require "../spec_helper"

private class Page < Shomen::View
  def to_html : String
    html lang: "zh-Hant" do
      head do
        title "say \"hi\""
        meta name: "title", content: "ignored"
      end
      body do
        h1 "Hello"
        p "the word title stays text"
        button type: "submit" do
          text "Go"
        end
        button "Later", type: "button"
        img alt: "", src: "/dot.png"
        img alt: "Logo", src: "/logo.png"
      end
    end
  end
end

def crystal_build_fixture(path : String) : {Int32, String}
  output = IO::Memory.new
  status = Process.run(
    "crystal",
    ["build", path, "-o", "/tmp/shomen-phase1-fixture", "--error-trace"],
    output: output,
    error: output,
  )
  {status.exit_code || 1, output.to_s}
ensure
  File.delete("/tmp/shomen-phase1-fixture") if File.exists?("/tmp/shomen-phase1-fixture")
end

describe Shomen::View do
  it "renders one document with lang, title, button, and alt" do
    html = Page.new.to_html
    html.should start_with("<!DOCTYPE html><html lang=\"zh-Hant\">")
    html.should contain("<title>say &quot;hi&quot;</title>")
    html.should contain("<p>the word title stays text</p>")
    html.should contain("<button type=\"submit\">Go</button>")
    html.should contain("<button type=\"button\">Later</button>")
    html.should contain("<img alt=\"\" src=\"/dot.png\">")
    html.should contain("<img alt=\"Logo\" src=\"/logo.png\">")
    html.should end_with("</html>")
    Page.new.to_html.should eq(html)
  end

  it "rejects a document without a title element" do
    status, output = crystal_build_fixture("spec/fixtures/missing_title.cr")
    status.should_not eq(0)
    output.should contain("exactly one title")
  end

  it "rejects two title elements" do
    status, output = crystal_build_fixture("spec/fixtures/two_titles.cr")
    status.should_not eq(0)
    output.should contain("exactly one title")
  end

  it "rejects a button without type" do
    status, output = crystal_build_fixture("spec/fixtures/button_missing_type.cr")
    status.should_not eq(0)
    output.should contain("button requires type")
  end

  it "rejects a button type outside submit, button, and reset" do
    status, output = crystal_build_fixture("spec/fixtures/button_bad_type.cr")
    status.should_not eq(0)
    output.should contain("button requires type")
  end

  it "rejects a button type that is not a string literal" do
    status, output = crystal_build_fixture("spec/fixtures/button_dynamic_type.cr")
    status.should_not eq(0)
    output.should contain("button requires type")
  end

  it "rejects an image without alt" do
    status, output = crystal_build_fixture("spec/fixtures/img_missing_alt.cr")
    status.should_not eq(0)
    output.should contain("img requires alt")
  end

  it "rejects a document without lang" do
    status, output = crystal_build_fixture("spec/fixtures/html_missing_lang.cr")
    status.should_not eq(0)
    output.should contain("html requires lang")
  end
end
```

`spec/fixtures/missing_title.cr`

```crystal
require "../../src/shomen"

class MissingTitleView < Shomen::View
  def to_html : String
    html lang: "en" do
      body do
        h1 "Hello"
        p "title in text only"
      end
    end
  end
end

MissingTitleView.new.to_html
```

`spec/fixtures/two_titles.cr`

```crystal
require "../../src/shomen"

class TwoTitlesView < Shomen::View
  def to_html : String
    html lang: "en" do
      head do
        title "One"
        title "Two"
      end
    end
  end
end

TwoTitlesView.new.to_html
```

`spec/fixtures/button_missing_type.cr`

```crystal
require "../../src/shomen"

class ButtonMissingTypeView < Shomen::View
  def to_html : String
    button do
      text "Go"
    end
    result
  end
end

ButtonMissingTypeView.new.to_html
```

`spec/fixtures/button_bad_type.cr`

```crystal
require "../../src/shomen"

class ButtonBadTypeView < Shomen::View
  def to_html : String
    button type: "Submit" do
      text "Go"
    end
    result
  end
end

ButtonBadTypeView.new.to_html
```

`spec/fixtures/button_dynamic_type.cr`

```crystal
require "../../src/shomen"

class ButtonDynamicTypeView < Shomen::View
  def initialize(@type : String)
  end

  def to_html : String
    button type: @type do
      text "Go"
    end
    result
  end
end

ButtonDynamicTypeView.new("submit").to_html
```

`spec/fixtures/img_missing_alt.cr`

```crystal
require "../../src/shomen"

class ImgMissingAltView < Shomen::View
  def to_html : String
    img src: "/x.png"
    result
  end
end

ImgMissingAltView.new.to_html
```

`spec/fixtures/html_missing_lang.cr`

```crystal
require "../../src/shomen"

class HtmlMissingLangView < Shomen::View
  def to_html : String
    html do
      title "Hello"
    end
  end
end

HtmlMissingLangView.new.to_html
```

- [ ] **Step 2: 成功例が未定義マクロで失敗することを確認する**

Run: `crystal spec spec/shomen/a11y_spec.cr --error-trace`

Expected: FAIL。`html` マクロが無いため `Page` がコンパイルできない。フィクスチャの subprocess までは届かなくてよい。

- [ ] **Step 3: a11y マクロを実装する**

`src/shomen/a11y.cr`

```crystal
class Shomen::View
  macro html(lang = nil, &block)
    {% unless lang.is_a?(StringLiteral) %}
      {% raise "html requires lang: as a string literal" %}
    {% end %}
    {% unless lang =~ /^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$/ %}
      {% raise "html lang must look like en or zh-Hant" %}
    {% end %}
    {% stripped = block.body.stringify.gsub(/"(?:[^"\\]|\\.)*"/, "\"\"") %}
    {% count = stripped.scan(/(^|[^.\w])title\s*(\(|do\b)/).size %}
    {% if count != 1 %}
      {% raise "html document must contain exactly one title, found #{count}" %}
    {% end %}
    reset
    @out << "<!DOCTYPE html><html lang=\""
    @out << Shomen::HTML.escape({{lang}})
    @out << "\">"
    {{block.body}}
    @out << "</html>"
    result
  end

  macro button(content = nil, type = nil, **attrs, &block)
    {% allowed = ["submit", "button", "reset"] %}
    {% unless type.is_a?(StringLiteral) && allowed.includes?(type) %}
      {% raise "button requires type: \"submit\" | \"button\" | \"reset\"" %}
    {% end %}
    {% if content && block %}
      {% raise "button takes either text or a block" %}
    {% end %}
    @out << "<button type=\"" << Shomen::HTML.escape({{type}}) << "\""
    {% for key, value in attrs %}
      @out << " " << {{key.id.stringify}} << "=\"" << Shomen::HTML.escape(({{value}}).to_s) << "\""
    {% end %}
    @out << ">"
    {% if content %}
      text({{content}})
    {% elsif block %}
      {{block.body}}
    {% end %}
    @out << "</button>"
  end

  macro img(alt = nil, **attrs)
    {% unless alt.is_a?(StringLiteral) %}
      {% raise "img requires alt: as a string literal" %}
    {% end %}
    @out << "<img alt=\"" << Shomen::HTML.escape({{alt}}) << "\""
    {% for key, value in attrs %}
      @out << " " << {{key.id.stringify}} << "=\"" << Shomen::HTML.escape(({{value}}).to_s) << "\""
    {% end %}
    @out << ">"
  end
end
```

`src/shomen.cr` で `view` の次に `require "./shomen/a11y"` を足す。

属性名の貼り付けで `src` が `"\"src\""` になるなら、`{{key.id.stringify}}` を、すでに文字列リテラルであるノードを二重に `stringify` しない形へ直す。期待する生成コードは `@out << " " << "src" << ...` である。

- [ ] **Step 4: spec が通ることを確認する**

Run: `crystal spec spec/shomen/a11y_spec.cr --error-trace`

Expected: PASS。出力に `Warning` は無い。コンパイル失敗の 7 件は exit code が 0 以外で、指定した文言を含む。

Run: `crystal tool format src/shomen/a11y.cr spec/shomen/a11y_spec.cr spec/fixtures`

---

### Task 4: Response と redirect

**Files:**

- Create: `src/shomen/not_found.cr`
- Create: `src/shomen/bad_input.cr`
- Create: `src/shomen/response.cr`
- Create: `spec/shomen/response_spec.cr`
- Modify: `src/shomen.cr`
- Test: `spec/shomen/response_spec.cr`

**Interfaces:**

- Consumes: なし
- Produces: `Shomen::NotFound < Exception`、`Shomen::BadInput < Exception`。`Shomen::Response` は `status : Int32`、`content_type : String`、`body : String`、`headers : HTTP::Headers`。`Shomen::Response.html(body : String, status : Int32 = 200)`。`Shomen::Response.redirect(location : String, status : Int32 = 303)`。既定の content type は `text/html; charset=utf-8`。redirect の `Location` は `headers["Location"]`。

- [ ] **Step 1: 失敗する spec を書く**

`spec/shomen/response_spec.cr`

```crystal
require "../spec_helper"

describe Shomen::Response do
  it "builds an HTML response" do
    response = Shomen::Response.html("<h1>Hello</h1>")
    response.status.should eq(200)
    response.content_type.should eq("text/html; charset=utf-8")
    response.body.should eq("<h1>Hello</h1>")
  end

  it "builds a redirect" do
    response = Shomen::Response.redirect("/next")
    response.status.should eq(303)
    response.headers["Location"].should eq("/next")
  end

  it "accepts an explicit redirect status" do
    response = Shomen::Response.redirect("/gone", 302)
    response.status.should eq(302)
    response.headers["Location"].should eq("/gone")
  end
end
```

- [ ] **Step 2: spec が失敗することを確認する**

Run: `crystal spec spec/shomen/response_spec.cr --error-trace`

Expected: FAIL。`Shomen::Response` が未定義。

- [ ] **Step 3: 型を実装する**

`src/shomen/not_found.cr`

```crystal
class Shomen::NotFound < Exception
end
```

`src/shomen/bad_input.cr`

```crystal
class Shomen::BadInput < Exception
end
```

`src/shomen/response.cr`

```crystal
require "http"

class Shomen::Response
  getter status : Int32
  getter content_type : String
  getter body : String
  getter headers : HTTP::Headers

  def initialize(@status : Int32, @content_type : String, @body : String, @headers : HTTP::Headers = HTTP::Headers.new)
  end

  def self.html(body : String, status : Int32 = 200) : self
    new(status, "text/html; charset=utf-8", body)
  end

  def self.redirect(location : String, status : Int32 = 303) : self
    headers = HTTP::Headers.new
    headers["Location"] = location
    new(status, "text/html; charset=utf-8", "", headers)
  end
end
```

`src/shomen.cr` に、a11y の次へ次を足す。

```crystal
require "./shomen/not_found"
require "./shomen/bad_input"
require "./shomen/response"
```

- [ ] **Step 4: spec が通ることを確認する**

Run: `crystal spec spec/shomen/response_spec.cr --error-trace`

Expected: PASS。出力に `Warning` は無い。

Run: `crystal tool format src/shomen/not_found.cr src/shomen/bad_input.cr src/shomen/response.cr spec/shomen/response_spec.cr`

---

### Task 5: ルート宣言、path helper、Input

**Files:**

- Create: `docs/decisions/20260928-phase1-routing.md`
- Create: `src/shomen/route.cr`
- Create: `spec/shomen/route_spec.cr`
- Create: `spec/fixtures/route_missing_path.cr`
- Create: `spec/fixtures/route_bad_input_type.cr`
- Create: `spec/fixtures/route_input_mismatch.cr`
- Modify: `src/shomen.cr`
- Test: `spec/shomen/route_spec.cr`

**Interfaces:**

- Consumes: `Shomen::Response`、`Shomen::View`、`Shomen::BadInput`、`URI.encode_path_segment`
- Produces: `abstract class Shomen::Route`。サブクラスの `self.verb : String`、`self.pattern : String`、`self.path`（静的パス）または `self.path(**kwargs)`（パラメータ）。`self.handle(request : HTTP::Request) : Shomen::Response`。インスタンスの `render(view : Shomen::View) : Shomen::Response` と `redirect(location : String, status : Int32 = 303) : Shomen::Response`。

`path` マクロは `TypeNode#instance_vars` を呼ばない。トップレベルのマクロ展開ではそのメソッドが禁止されている。型の対応は `handle` のメソッド本体マクロで検査する。そこはメソッド内部なのでインスタンス変数を読める。

`Input` にフィールドがあるときは、利用側が `getter` と `initialize` を書く。空の path は `struct Input; end`。

- [ ] **Step 1: 決定ログを書く**

`docs/decisions/20260928-phase1-routing.md`

```markdown
# 状況

ルートの登録漏れと二重登録は、コンパイル失敗か起動失敗のどちらかにする必要がある。path helper は `Hello::Show.path` のようにルートクラスから呼べる。`:id` は `Input` の同名フィールドへ束縛し、変換失敗は 400 にする。指示書のクラス本体は `method`、`path`、`struct Input`、`call` の順である。

# 決定

具象サブクラスは `macro inherited` で `Shomen::Route::Hooks` を include し、`handle` をそのクラス自身に定義する。`method` は `GET` `POST` `PUT` `PATCH` `DELETE` `HEAD` だけを受け、`VERB` 定数と `self.verb` を置く。`path` は `/` で始まる文字列リテラルだけを宣言として受け、`PATH` 定数と `self.pattern` を置く。引数なし、またはキーワード引数の `path` 呼び出しは path helper である。静的 path は宣言文字列を返し、パラメータは `URI.encode_path_segment` で 1 セグメントにする。値に `/`、`?`、`#` が含まれるときは `ArgumentError`。照合とキャプチャは宣言と同じ `String#split("/")` を使う。`"/"` の split は `["", ""]` である。空のキャプチャセグメントは不一致。クエリは `HTTP::Request#path` に含まれないので照合しない。

`handle` は path パラメータと `Input` のインスタンス変数が名前も個数も一致することをコンパイル時に検査する。型は `String`、`Int32`、`Int64` だけ。整数へ変換できない値は `Shomen::BadInput` を上げる。ルート表は `Shomen::Route.all_subclasses` を `Router.entries` の初回呼び出しで走査して作る。具象サブクラスに `VERB` または `PATH` が無いときは、その走査のコンパイルに失敗する。同じメソッドかつ同じ shape（パラメータ名を `:` に潰した path）は `duplicate route` で起動失敗する。リテラルセグメントが多いルートを優先する。`src/shomen/handler.cr` は作らず、`Shomen::Server` が `HTTP::Handler` を include する。

# 理由

`macro finished` の実行時コードはファイル末尾に回る。`Server.start` が listen すると、その登録は走らない。`instance_vars` はトップレベルのマクロ展開では呼べないので、path helper ではなく `handle` の中で Input を検査する。shape で比べると `/users/:id` と `/users/:name` を二重登録にできる。

# 破棄した案

- クラス定義の実行時に `macro finished` で `Router.add` する
- path helper の呼び出し位置で `instance_vars` を読み、`.as(Int32)` する
- サブクラス一覧をアプリが手で渡す
- メソッド違いを 405 にする
```

- [ ] **Step 2: 失敗する spec を書く**

`spec/shomen/route_spec.cr`

```crystal
require "../spec_helper"

class PendingRoot::Show < Shomen::Route
  method GET
  path "/phase1/root"

  struct Input
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("root")
  end
end

class Users::Show < Shomen::Route
  method GET
  path "/phase1/users/:id"

  struct Input
    getter id : Int32

    def initialize(@id : Int32)
    end
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html(input.id.to_s)
  end
end

class Labels::Show < Shomen::Route
  method GET
  path "/phase1/labels/:name"

  struct Input
    getter name : String

    def initialize(@name : String)
    end
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html(input.name)
  end
end

describe Shomen::Route do
  it "returns a static path from the route class" do
    PendingRoot::Show.path.should eq("/phase1/root")
    PendingRoot::Show.verb.should eq("GET")
    PendingRoot::Show.pattern.should eq("/phase1/root")
  end

  it "fills one path parameter" do
    Users::Show.path(id: 15).should eq("/phase1/users/15")
  end

  it "rejects a path component that would add a segment" do
    expect_raises(ArgumentError) do
      Labels::Show.path(name: "a/b")
    end
  end

  it "builds Input from the request path" do
    response = Users::Show.handle(HTTP::Request.new("GET", "/phase1/users/15"))
    response.status.should eq(200)
    response.body.should eq("15")
  end

  it "raises BadInput when an integer segment is not an integer" do
    expect_raises(Shomen::BadInput) do
      Users::Show.handle(HTTP::Request.new("GET", "/phase1/users/abc"))
    end
  end
end
```

`spec/fixtures/route_missing_path.cr`

```crystal
require "../../src/shomen"

class MissingPath < Shomen::Route
  method GET

  struct Input
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("x")
  end
end

MissingPath.handle(HTTP::Request.new("GET", "/"))
```

`spec/fixtures/route_bad_input_type.cr`

```crystal
require "../../src/shomen"

class BadInputType < Shomen::Route
  method GET
  path "/items/:id"

  struct Input
    getter id : Bool

    def initialize(@id : Bool)
    end
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("x")
  end
end

BadInputType.handle(HTTP::Request.new("GET", "/items/1"))
```

`spec/fixtures/route_input_mismatch.cr`

```crystal
require "../../src/shomen"

class InputMismatch < Shomen::Route
  method GET
  path "/items/:id"

  struct Input
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("x")
  end
end

InputMismatch.handle(HTTP::Request.new("GET", "/items/1"))
```

`route_spec.cr` の最後に、Task 3 と同じ `crystal_build_fixture` を使い、上の 3 フィクスチャが exit 0 以外で、出力がそれぞれ `must declare path`、`String, Int32, or Int64`、`must match path params` を含む example を足す。

- [ ] **Step 3: spec が失敗することを確認する**

Run: `crystal spec spec/shomen/route_spec.cr --error-trace`

Expected: FAIL。`Shomen::Route` が未定義、または `method` マクロが無い。

- [ ] **Step 4: Route を実装する**

`src/shomen/route.cr`

```crystal
require "http"
require "uri"

abstract class Shomen::Route
  module Hooks
    macro included
      def self.handle(request : HTTP::Request) : Shomen::Response
        {% verbatim do %}
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
            {% if ivars.size != params.size %}
              {% raise "#{@type.name.stringify} Input must match path params #{params}, found #{ivars.keys}" %}
            {% end %}
            {% for pname in params %}
              {% typ = ivars[pname] %}
              {% unless typ == "Int32" || typ == "Int64" || typ == "String" %}
                {% raise "#{@type.name.stringify} field #{pname} has type #{typ}, want String, Int32, or Int64" %}
              {% end %}
            {% end %}
            captures = ::Shomen::Router.captures!(PATH, request.path)
            input = Input.new(
              {% for pname in params %}
                {{pname.id}}: begin
                  raw = captures[{{pname}}]
                  {% if ivars[pname] == "Int32" %}
                    raw.to_i32? || raise ::Shomen::BadInput.new("invalid " + {{pname}})
                  {% elsif ivars[pname] == "Int64" %}
                    raw.to_i64? || raise ::Shomen::BadInput.new("invalid " + {{pname}})
                  {% else %}
                    raw
                  {% end %}
                end,
              {% end %}
            )
            new.call(input)
          {% end %}
        {% end %}
      end
    end
  end

  macro inherited
    include Hooks
  end

  macro method(verb)
    {% name = verb.id.stringify %}
    {% unless ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"].includes?(name) %}
      {% verb.raise "method must be GET, POST, PUT, PATCH, DELETE, or HEAD" %}
    {% end %}
    VERB = {{name}}

    def self.verb : String
      VERB
    end
  end

  macro path(pattern = nil, **kwargs)
    {% if pattern.is_a?(StringLiteral) %}
      {% if kwargs.size != 0 %}
        {% raise "path declaration does not take named arguments" %}
      {% end %}
      {% unless pattern.starts_with?("/") %}
        {% pattern.raise "path must start with /" %}
      {% end %}
      PATH = {{pattern}}

      def self.pattern : String
        PATH
      end
    {% elsif pattern.is_a?(Nop) || pattern.is_a?(NilLiteral) %}
      {% path_node = @type.constant("PATH") %}
      {% if path_node.is_a?(Nop) %}
        {% raise "#{@type.name.stringify} must declare path" %}
      {% end %}
      {% names = [] of Nil %}
      {% for part in path_node.split("/") %}
        {% if part.starts_with?(":") %}
          {% names << part[1..-1] %}
        {% end %}
      {% end %}
      {% if names.empty? %}
        {% if kwargs.size != 0 %}
          {% raise "#{@type.name.stringify}.path takes no arguments" %}
        {% end %}
        {{path_node}}
      {% else %}
        {% if kwargs.size != names.size %}
          {% raise "#{@type.name.stringify}.path arguments must match #{names}" %}
        {% end %}
        {% for pname in names %}
          {% if kwargs[pname].is_a?(Nop) %}
            {% raise "#{@type.name.stringify}.path requires #{pname}" %}
          {% end %}
        {% end %}
        String.build do |io|
          {% for part in path_node.split("/") %}
            {% if part.starts_with?(":") %}
              %component = ({{kwargs[part[1..-1]]}}).to_s
              if %component.includes?("/") || %component.includes?("?") || %component.includes?("#")
                raise ArgumentError.new("invalid path component")
              end
              io << "/"
              io << URI.encode_path_segment(%component)
            {% elsif part != "" %}
              io << "/" << {{part}}
            {% end %}
          {% end %}
        end
      {% end %}
    {% else %}
      {% pattern.raise "path helper takes named arguments" %}
    {% end %}
  end

  def render(view : Shomen::View) : Shomen::Response
    Shomen::Response.html(view.to_html)
  end

  def redirect(location : String, status : Int32 = 303) : Shomen::Response
    Shomen::Response.redirect(location, status)
  end
end
```

`handle` は `Shomen::Router.captures!` を呼ぶ。Task 6 まで仮実装を `src/shomen/router.cr` に置く。

```crystal
require "http"

module Shomen::Router
  def self.captures!(pattern : String, path : String) : Hash(String, String)
    expected = pattern.split("/")
    actual = path.split("/")
    unless expected.size == actual.size
      raise Shomen::NotFound.new
    end
    found = {} of String => String
    expected.each_with_index do |part, index|
      got = actual[index]
      if part.starts_with?(":")
        raise Shomen::NotFound.new if got.empty?
        found[part[1..]] = got
      elsif part != got
        raise Shomen::NotFound.new
      end
    end
    found
  end
end
```

`src/shomen.cr` に `require "./shomen/route"` と `require "./shomen/router"` を足す。`router` を `route` より先に require する。`handle` の中の `Router` 参照は実行時なので、定義順が逆でもコンパイルは通る。require 順は `router`、`route` にする。

- [ ] **Step 5: spec が通ることを確認する**

Run: `crystal spec spec/shomen/route_spec.cr --error-trace`

Expected: PASS。出力に `Warning` は無い。3 つのフィクスチャはコンパイルに失敗する。

`captures[{{pname}}]` がキー `"\"id\""` を探す `KeyError` になったら、`pname` はすでに文字列リテラルなので `stringify` を足さない。逆にキーがシンボルになっていたら、生成コードが `captures["id"]` になる貼り方へ直す。

Run: `crystal tool format src/shomen/route.cr src/shomen/router.cr spec/shomen/route_spec.cr spec/fixtures/route_missing_path.cr spec/fixtures/route_bad_input_type.cr spec/fixtures/route_input_mismatch.cr`

---

### Task 6: ルート表と照合

**Files:**

- Modify: `src/shomen/router.cr`
- Create: `spec/support/routes.cr`
- Create: `spec/shomen/router_spec.cr`
- Create: `spec/fixtures/duplicate_route.cr`
- Create: `spec/fixtures/duplicate_shape.cr`
- Modify: `spec/spec_helper.cr`
- Test: `spec/shomen/router_spec.cr`

**Interfaces:**

- Consumes: `Shomen::Route.all_subclasses`、`self.verb`、`self.pattern`、`self.handle`
- Produces: `Shomen::Router.entries`、`Shomen::Router.find(method : String, path : String) : (HTTP::Request -> Shomen::Response)?`、既存の `captures!`。`find` はリテラルセグメントが多いルートを優先する。同じ shape は `raise "duplicate route ..."`.

- [ ] **Step 1: 共有ルートと失敗する spec を書く**

`spec/spec_helper.cr` の末尾に `require "./support/routes"` を足す。

`spec/support/routes.cr` に、spec プロセスで共有するルートを置く。path はすべて `/phase1/` で始める。Task 5 の `PendingRoot::Show`、`Users::Show`、`Labels::Show` とは path もクラス名も重ねない。

```crystal
require "http"

module ServerRoutes
  class HomeView < Shomen::View
    def to_html : String
      html lang: "en" do
        head do
          title "Hello"
        end
        body do
          h1 "Hello"
        end
      end
    end
  end

  class Home < Shomen::Route
    method GET
    path "/phase1/home"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render HomeView.new
    end
  end

  class User < Shomen::Route
    method GET
    path "/phase1/people/:id"

    struct Input
      getter id : Int32

      def initialize(@id : Int32)
      end
    end

    def call(input : Input) : Shomen::Response
      render_text = input.id.to_s
      Shomen::Response.html(render_text)
    end
  end

  class NewPerson < Shomen::Route
    method GET
    path "/phase1/people/new"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html("new")
    end
  end

  class Boom < Shomen::Route
    method GET
    path "/phase1/boom"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      raise "boom <script>"
    end
  end

  class Gone < Shomen::Route
    method GET
    path "/phase1/gone"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      raise Shomen::NotFound.new
    end
  end

  class Bad < Shomen::Route
    method GET
    path "/phase1/bad/:id"

    struct Input
      getter id : Int32

      def initialize(@id : Int32)
      end
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html(input.id.to_s)
    end
  end

  class Redirector < Shomen::Route
    method GET
    path "/phase1/redirect"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      redirect("/phase1/home")
    end
  end

  class Update < Shomen::Route
    method POST
    path "/phase1/home"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html("posted")
    end
  end
end
```

`spec/shomen/router_spec.cr`

```crystal
require "../spec_helper"

describe Shomen::Router do
  it "prefers a static route over a parameter route" do
    handler = Shomen::Router.find("GET", "/phase1/people/new").not_nil!
    handler.call(HTTP::Request.new("GET", "/phase1/people/new")).body.should eq("new")
  end

  it "captures an integer segment" do
    handler = Shomen::Router.find("GET", "/phase1/people/8").not_nil!
    handler.call(HTTP::Request.new("GET", "/phase1/people/8")).body.should eq("8")
  end

  it "ignores the query string" do
    handler = Shomen::Router.find("GET", HTTP::Request.new("GET", "/phase1/people/8?x=1").path)
    handler.should_not be_nil
  end

  it "treats a different method as no match" do
    Shomen::Router.find("POST", "/phase1/people/8").should be_nil
    Shomen::Router.find("POST", "/phase1/home").should_not be_nil
  end

  it "does not match a different number of segments" do
    Shomen::Router.find("GET", "/phase1/people/8/edit").should be_nil
    Shomen::Router.find("GET", "/phase1/people").should be_nil
  end
end
```

二重登録の 2 フィクスチャは `crystal run` で起動失敗させる。`crystal build` だけではクラス本体の `entries` 呼び出しが走らない。

`spec/fixtures/duplicate_route.cr`

```crystal
require "../../src/shomen"

class DupA < Shomen::Route
  method GET
  path "/dup"

  struct Input
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("a")
  end
end

class DupB < Shomen::Route
  method GET
  path "/dup"

  struct Input
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html("b")
  end
end

Shomen::Router.entries
```

`spec/fixtures/duplicate_shape.cr`

```crystal
require "../../src/shomen"

class ShapeA < Shomen::Route
  method GET
  path "/people/:id"

  struct Input
    getter id : String

    def initialize(@id : String)
    end
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html(input.id)
  end
end

class ShapeB < Shomen::Route
  method GET
  path "/people/:name"

  struct Input
    getter name : String

    def initialize(@name : String)
    end
  end

  def call(input : Input) : Shomen::Response
    Shomen::Response.html(input.name)
  end
end

Shomen::Router.entries
```

`router_spec.cr` に次の helper と 2 example を足す。

```crystal
def crystal_run_fixture(path : String) : {Int32, String}
  output = IO::Memory.new
  status = Process.run(
    "crystal",
    ["run", "--error-trace", File.expand_path(path)],
    output: output,
    error: output,
  )
  {status.exit_code || 1, output.to_s}
ensure
  binary = path.sub(/\.cr$/, "")
  File.delete(binary) if File.exists?(binary)
end
```

example は両方とも exit code が 0 以外、出力に `duplicate route` を含むこと。

- [ ] **Step 2: spec が失敗することを確認する**

Run: `crystal spec spec/shomen/router_spec.cr --error-trace`

Expected: FAIL。`Shomen::Router.find` が未定義。

- [ ] **Step 3: ルート表を実装する**

`src/shomen/router.cr` の `captures!` は残し、次を同じモジュールに足す。

```crystal
record Entry, verb : String, pattern : String, shape : String, literals : Int32, handler : Proc(HTTP::Request, Shomen::Response)

def self.entries : Array(Entry)
  @@entries ||= build_entries
end

def self.find(method : String, path : String) : Proc(HTTP::Request, Shomen::Response)?
  matches = entries.select { |entry| entry.verb == method && match?(entry.pattern, path) }
  return nil if matches.empty?
  exact = matches.find { |entry| entry.pattern == path }
  return exact.handler if exact
  best = matches.max_of { |entry| entry.literals }
  top = matches.select { |entry| entry.literals == best }
  if top.size > 1
    raise "ambiguous route #{method} #{path}"
  end
  top.first.handler
end

def self.match?(pattern : String, path : String) : Bool
  expected = pattern.split("/")
  actual = path.split("/")
  return false unless expected.size == actual.size
  expected.each_with_index do |part, index|
    got = actual[index]
    if part.starts_with?(":")
      return false if got.empty?
    elsif part != got
      return false
    end
  end
  true
end

def self.shape_for(pattern : String) : String
  pattern.split("/").map { |part| part.starts_with?(":") ? ":" : part }.join("/")
end

def self.literal_count(pattern : String) : Int32
  pattern.split("/").count { |part| !part.empty? && !part.starts_with?(":") }
end

private def self.build_entries : Array(Entry)
  built = [] of Entry
  seen = {} of String => String
  {% for klass in Shomen::Route.all_subclasses %}
    {% if !klass.abstract? %}
      {% unless klass.has_constant?("VERB") && klass.has_constant?("PATH") %}
        {% raise "#{klass.name.stringify} must declare method and path" %}
      {% end %}
      verb = {{klass}}.verb
      pattern = {{klass}}.pattern
      shape = shape_for(pattern)
      key = verb + " " + shape
      if seen[key]?
        raise "duplicate route #{verb} #{pattern}"
      end
      seen[key] = pattern
      built << Entry.new(
        verb,
        pattern,
        shape,
        literal_count(pattern),
        ->(request : HTTP::Request) { {{klass}}.handle(request) },
      )
    {% end %}
  {% end %}
  built
end
```

`Array#max_of` がこの Crystal に無ければ、`literals` の最大値を `each` で求める。挙動は変えない。

- [ ] **Step 4: spec が通ることを確認する**

Run: `crystal spec spec/shomen/router_spec.cr spec/shomen/route_spec.cr --error-trace`

Expected: PASS。出力に `Warning` は無い。Task 5 のルートと Task 6 の共有ルートが同じプロセスに載る。path の shape が重なって `duplicate route` になったら、重なったクラスの path をどちらかへずらす。指示書の意味（同じ method と同じ shape は失敗）は変えない。

Run: `crystal tool format src/shomen/router.cr spec/shomen/router_spec.cr spec/support/routes.cr spec/spec_helper.cr`

---

### Task 7: サーバ

**Files:**

- Create: `docs/decisions/20260928-phase1-errors.md`
- Create: `src/shomen/error_view.cr`
- Create: `src/shomen/server.cr`
- Create: `spec/shomen/server_spec.cr`
- Modify: `src/shomen.cr`
- Test: `spec/shomen/server_spec.cr`

**Interfaces:**

- Consumes: `Shomen::Router.find`、`Shomen::Response`、`Shomen::NotFound`、`Shomen::BadInput`、`Shomen::View`
- Produces: `class Shomen::Server`。`include HTTP::Handler`。`def call(context : HTTP::Server::Context)`。`def self.start(host : String = "127.0.0.1", port : Int32 = 3000)`。`start` は listen の前に `Router.entries` を呼ぶ。

すべての応答に 3 つのセキュリティヘッダを付ける。ルートが付けた `Location` は残す。同じ名前のセキュリティヘッダをルートが付けても、サーバの値で上書きする。

- [ ] **Step 1: 決定ログと失敗する spec を書く**

`docs/decisions/20260928-phase1-errors.md`

```markdown
# 状況

未照合は 404 の HTML 文書である。未処理例外は 500 の HTML 文書で、開発時はメッセージを出してよい。本番で隠すフラグはフェーズ 6 にある。想定内の入力失敗は `BadInput`、ルートが自分で見つからないと言うときは `NotFound` である。

# 決定

フェーズ 1 の 500 は例外メッセージを常にエスケープして本文へ出す。`SHOMEN_ENV` は読まない。未照合の 404 と、`NotFound` の 404 は同じ文書にする。`BadInput` は 400 の HTML 文書にする。いずれの本文も `ErrorView` が `lang="en"` と `title` を持つ文書として描く。スタックトレースは出さない。

# 理由

フェーズ 6 が本番の秘匿を受け持っている。フェーズ 1 で環境変数を読むと、そのフェーズの受入を先に実装することになる。4xx と 500 を HTML 文書にするのは、空の JSON を禁止している仕様 5 に合わせるためである。

# 破棄した案

- 開発と本番をフェーズ 1 で分岐する
- 404 をプレーンテキストだけにする
- `BadInput` を 500 に混ぜる
```

`spec/shomen/server_spec.cr`

```crystal
require "../spec_helper"
require "http/client"

def call_server(method : String, path : String) : HTTP::Client::Response
  io = IO::Memory.new
  request = HTTP::Request.new(method, path)
  response = HTTP::Server::Response.new(io)
  context = HTTP::Server::Context.new(request, response)
  Shomen::Server.new.call(context)
  response.close
  io.rewind
  HTTP::Client::Response.from_io(io)
end

def assert_security_headers(response)
  response.headers["X-Content-Type-Options"].should eq("nosniff")
  response.headers["Referrer-Policy"].should eq("no-referrer")
  response.headers["X-Frame-Options"].should eq("DENY")
end

describe Shomen::Server do
  it "returns 200 HTML for a matched route" do
    response = call_server("GET", "/phase1/home")
    response.status_code.should eq(200)
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    response.body.should contain("<h1>Hello</h1>")
    response.body.should contain("<html lang=\"en\">")
    assert_security_headers(response)
  end

  it "returns 404 HTML for an unknown path" do
    response = call_server("GET", "/phase1/missing")
    response.status_code.should eq(404)
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    response.body.should contain("<title>Not found</title>")
    response.body.should_not contain("{")
    assert_security_headers(response)
  end

  it "returns 404 HTML when the route raises NotFound" do
    response = call_server("GET", "/phase1/gone")
    response.status_code.should eq(404)
    response.body.should contain("<title>Not found</title>")
  end

  it "returns 400 HTML when path input is invalid" do
    response = call_server("GET", "/phase1/bad/abc")
    response.status_code.should eq(400)
    response.body.should contain("<title>Bad input</title>")
    response.body.should contain("invalid id")
    assert_security_headers(response)
  end

  it "returns 500 HTML and escapes the exception message" do
    response = call_server("GET", "/phase1/boom")
    response.status_code.should eq(500)
    response.body.should contain("<title>Error</title>")
    response.body.should contain("boom &lt;script&gt;")
    response.body.should_not contain("<script>")
    assert_security_headers(response)
  end

  it "keeps a redirect location and adds security headers" do
    response = call_server("GET", "/phase1/redirect")
    response.status_code.should eq(303)
    response.headers["Location"].should eq("/phase1/home")
    assert_security_headers(response)
  end
end
```

- [ ] **Step 2: spec が失敗することを確認する**

Run: `crystal spec spec/shomen/server_spec.cr --error-trace`

Expected: FAIL。`Shomen::Server` が未定義。

- [ ] **Step 3: ErrorView と Server を実装する**

`src/shomen/error_view.cr`

```crystal
class Shomen::ErrorView < Shomen::View
  def initialize(@heading : String, @detail : String?)
  end

  def to_html : String
    heading = @heading
    detail = @detail
    html lang: "en" do
      head do
        title heading
      end
      body do
        h1 heading
        if text = detail
          p text
        end
      end
    end
  end
end
```

`if text = detail` は `String?` を `String` に絞る。`title heading` は字句上の `title` 呼び出し 1 つなので、文書検査を満たす。

`src/shomen/server.cr`

```crystal
require "http/server"
require "http/server/handler"

class Shomen::Server
  include HTTP::Handler

  def self.start(host : String = "127.0.0.1", port : Int32 = 3000) : Nil
    Shomen::Router.entries
    server = HTTP::Server.new([new])
    server.bind_tcp(host, port)
    server.listen
  end

  def call(context : HTTP::Server::Context) : Nil
    write_response(context, dispatch(context.request))
  rescue ex : Shomen::BadInput
    write_response(context, error_response(400, "Bad input", ex.message))
  rescue ex : Shomen::NotFound
    write_response(context, error_response(404, "Not found", nil))
  rescue ex
    write_response(context, error_response(500, "Error", ex.message))
  end

  def dispatch(request : HTTP::Request) : Shomen::Response
    handler = Shomen::Router.find(request.method, request.path)
    return error_response(404, "Not found", nil) unless handler
    handler.call(request)
  end

  private def error_response(status : Int32, heading : String, detail : String?) : Shomen::Response
    Shomen::Response.html(Shomen::ErrorView.new(heading, detail).to_html, status)
  end

  private def write_response(context : HTTP::Server::Context, response : Shomen::Response) : Nil
    context.response.status_code = response.status
    context.response.content_type = response.content_type
    response.headers.each do |entry|
      name, value = entry
      case value
      when String
        context.response.headers[name] = value
      when Array
        context.response.headers[name] = value.join(", ")
      end
    end
    context.response.headers["X-Content-Type-Options"] = "nosniff"
    context.response.headers["Referrer-Policy"] = "no-referrer"
    context.response.headers["X-Frame-Options"] = "DENY"
    context.response.print(response.body)
  end
end
```

`src/shomen.cr` の末尾側に `require "./shomen/error_view"` と `require "./shomen/server"` を足す。完成形は次の順。

```crystal
require "./shomen/version"
require "./shomen/html"
require "./shomen/view"
require "./shomen/a11y"
require "./shomen/not_found"
require "./shomen/bad_input"
require "./shomen/response"
require "./shomen/error_view"
require "./shomen/router"
require "./shomen/route"
require "./shomen/server"

module Shomen
end
```

- [ ] **Step 4: spec が通ることを確認する**

Run: `crystal spec --error-trace`

Expected: フェーズ 0 の VERSION spec を含む全 example が PASS。出力に `Warning` は無い。

Run: `crystal tool format src spec`

---

### Task 8: examples/hello と受入確認

**Files:**

- Create: `examples/hello/shard.yml`
- Create: `examples/hello/.gitignore`
- Create: `examples/hello/src/hello.cr`
- Create: `examples/hello/spec/spec_helper.cr`
- Create: `examples/hello/spec/hello_spec.cr`
- Test: `examples/hello/spec/hello_spec.cr`

**Interfaces:**

- Consumes: パス依存 `shomen`、`Shomen::Server.start`、`Shomen::Route`、`Shomen::View`
- Produces: `Hello::Show` が `GET /`。`Hello::ShowView` の文書が `<h1>Hello</h1>` を含む。

- [ ] **Step 1: アプリと、ポートを使わない spec を書く**

`examples/hello/shard.yml`

```yaml
name: hello
version: 0.0.1
license: MIT
crystal: ">= 1.20.0"

dependencies:
  shomen:
    path: ../..
```

`examples/hello/.gitignore`

```gitignore
/lib/
```

`examples/hello/src/hello.cr`

```crystal
require "shomen"

module Hello
  class ShowView < Shomen::View
    def to_html : String
      html lang: "en" do
        head do
          title "Hello"
        end
        body do
          h1 "Hello"
        end
      end
    end
  end

  class Show < Shomen::Route
    method GET
    path "/"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render ShowView.new
    end
  end
end

Shomen::Server.start
```

`examples/hello/spec/spec_helper.cr`

```crystal
require "spec"
require "../src/hello"
```

この require は `Shomen::Server.start` をファイル末尾で呼ぶ `hello.cr` を読み込む。spec が listen してしまう。`hello.cr` の `Shomen::Server.start` を次の条件に変える。

```crystal
Shomen::Server.start unless ENV["SHOMEN_SPEC"]?
```

spec_helper の先頭で `ENV["SHOMEN_SPEC"] = "1"` してから `hello` を require する。本体ライブラリは `SHOMEN_SPEC` を読まない。example の起動ガードだけが読む。

`examples/hello/spec/hello_spec.cr`

```crystal
require "./spec_helper"
require "http/client"

describe Hello::Show do
  it "returns a document containing h1 Hello" do
    io = IO::Memory.new
    request = HTTP::Request.new("GET", "/")
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(request, response)
    Shomen::Server.new.call(context)
    response.close
    io.rewind
    parsed = HTTP::Client::Response.from_io(io)
    parsed.status_code.should eq(200)
    parsed.body.should contain("<h1>Hello</h1>")
  end

  it "exposes the declared path" do
    Hello::Show.path.should eq("/")
  end
end
```

- [ ] **Step 2: example の spec が先に失敗することを確認する**

ファイルを全部置いたあと、`src/hello.cr` の `render` 呼び出しを一時的にコメントアウトせず、依存インストール前なら未解決で失敗する。実装は Step 1 のファイルが完成形なので、失敗確認は `shards install` の前に `crystal spec` を一回走らせ、`shomen` が見つからないことを見る。その後インストールする。

Run: `cd examples/hello && crystal spec`

Expected: FAIL。`shomen` が無い。

- [ ] **Step 3: 依存を入れて spec を通す**

Run: `cd examples/hello && shards install && crystal spec --error-trace`

Expected: PASS。出力に `Warning` は無い。`examples/hello/lib/` は example の `.gitignore` に入る。ルートの `shard.yml` と `shard.lock` は変わらない。

Run: `crystal tool format examples/hello/src/hello.cr examples/hello/spec/spec_helper.cr examples/hello/spec/hello_spec.cr`

- [ ] **Step 4: 本体と example の受入コマンドを通す**

リポジトリルートで、この順に実行する。

```sh
shards install
crystal spec --error-trace
crystal build src/shomen.cr --error-trace
rm -f shomen
cd examples/hello && shards install && crystal spec --error-trace
```

Expected: どちらも exit 0。`crystal spec` と `crystal build` の出力に `Warning` は無い。ルートの `shard.lock` は `shards: {}`。`src/shomen/server.cr` 以外にフェーズ 2 のファイルは無い。

ポート確認は example ディレクトリで行う。3000 が空いているときだけ。

```sh
cd examples/hello
crystal run src/hello.cr &
pid=$!
ok=0
i=0
while [ "$i" -lt 50 ]; do
  if curl -sf http://127.0.0.1:3000/ | grep -F '<h1>Hello</h1>' >/dev/null; then
    ok=1
    break
  fi
  i=$((i + 1))
  sleep 0.1
done
kill "$pid"
wait "$pid" 2>/dev/null || true
test "$ok" -eq 1
```

`crystal run` が `examples/hello/hello` を残したら削除する。bind に失敗したら、3000 を使用中のプロセスを止めずに、失敗として報告する。

Expected: curl の本文に `<h1>Hello</h1>` がある。

---

## Self-review メモ

実装後に、この計画の Review Focus 5 項目がそれぞれ 1 件以上の example で赤くなり得たことを確認する。`docs/02-PHASES.md` のフェーズ 1 受入は、TDD 1–6、`examples/hello` の HTML、本体 shard の依存なし、の 3 つである。TDD の対応は次のとおり。

| 指示書 | 固定する example |
|---|---|
| 1. `GET /` が 200 と HTML | `examples/hello` の spec。本体側の代表は `GET /phase1/home` |
| 2. 未知 path が 404 HTML | `Shomen::Server` の unknown path |
| 3. 特殊文字のエスケープ | `Shomen::HTML` と `EscapeProbe` |
| 4. `button` の `type` 欠落がコンパイル失敗 | `spec/fixtures/button_missing_type.cr` |
| 5. path helper | `PendingRoot::Show.path` と `Hello::Show.path` |
| 6. 二重登録が失敗 | `duplicate_route.cr` と `duplicate_shape.cr` |
