# Phase 4 Fragments and Fetch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** フェーズ 4 の受入まで届ける。`render_fragment`、`shomen.js` の `data-shomen-get` と `data-shomen-post`（対象 `id` の要素だけを差し替える）、ルートが `json` を呼んだときだけの JSON 応答。

**Architecture:** 断片は `Shomen::Fragment < Shomen::View` で、`content` を実装し、`html` を書くとコンパイルエラーになる。文書ビューは `embed` で断片を埋め込み、ルートは `render_fragment` で断片だけを返す。`render` に断片を渡すとコンパイルエラー（D1）。`shomen.js` は `Shomen-Target: <id>` ヘッダを付けて fetch し、ルートは `target : String?` で断片か文書かを選ぶ。サーバはすべての応答に `Vary: Shomen-Target` を付ける（D2）。`shomen.js` は `a[data-shomen-get]` と `form[data-shomen-post]` の `href` / `action` を使うので、JS が無くても同じリンクとフォームが動く（D3、D4）。`shomen.js` はコンパイル時にバイナリへ埋め込み、`Shomen::Island::Script` ルートが `GET /shomen.js` で返す（D5）。`json(value, status)` は `application/json` を返し、エラーは JSON のルートでも HTML 文書のまま（D6）。JS の挙動は、標準ライブラリの `HTTP::WebSocket` だけで書いた DevTools プロトコルのクライアントでヘッドレス Chrome を動かして spec で確かめる（D7）。

**Tech Stack:** Crystal `>= 1.20.0`（開発機は 1.21.1）、標準ライブラリの `spec`、`json`、`http/server`、`http/web_socket`、`file_utils`。外部 shard は増やさない（`sqlite3` と `db` のまま）。JavaScript は素の ES2020、npm なし、ビルドなし。ブラウザ spec は開発機の Google Chrome（`/Applications/Google Chrome.app`）を使う。

**Spec:** `docs/en/00-INSTRUCTION.md` の「2. Route declarations」（JSON はルートが求めたときだけ）、「3. Views and HTML」、「4. Responses」（`render_fragment`）、「8. Fragment updates and islands」、「9. Error model」（JSON のエラー形式）、`docs/en/01-ARCHITECTURE.md` の「Module boundaries」（`Shomen::Island`）、「Rendering」（断片は根要素 1 つ）、「Official JavaScript」、`docs/en/02-PHASES.md` のフェーズ 4、`docs/en/03-CONVENTIONS.md`。細部は次の決定ファイルに従う。この計画の Task 1 で足すもの:

- `docs/decisions/20260929-phase4-fragment-view.md`（D1）
- `docs/decisions/20260929-phase4-fragment-request.md`（D2）
- `docs/decisions/20260929-phase4-script-attributes.md`（D3）
- `docs/decisions/20260929-phase4-script-response.md`（D4）
- `docs/decisions/20260929-phase4-script-serving.md`（D5）
- `docs/decisions/20260929-phase4-json-response.md`（D6）
- `docs/decisions/20260929-phase4-browser-spec.md`（D7）
- `docs/decisions/20260929-phase4-greeting-example.md`（D8）

D6 と D7 はユーザーが選んだ案（2026-09-29 の計画時の質問: JSON は `json` ヘルパーだけ、JS の受入は Chrome を CDP で自動テスト）。

## Global Constraints

- 言語は Crystal 1.20 以上。`shard.yml` の下限は `>= 1.20.0` のまま。依存 shard を足さない（仕様 1）。
- 公式 JavaScript は `src/shomen/assets/shomen.js` の 1 ファイル。npm パッケージ、`package.json`、`import`、`export`、`require(`、ビルド手順を持たない。10 KB（10,240 バイト）未満（仕様「about 10KB」）。
- `shomen.js` が読む独自属性は `data-shomen-*` だけ（仕様 8）。`dataset` を使わない（Task 4 の spec が文字列で検査する）。
- `shomen.js` が送るヘッダは `Shomen-Target` だけ。値は差し替える要素の `id`。
- サーバは `Accept` を見て形式を変えない。JSON は `json` を呼んだルートだけが返す。エラー（400/403/404/409/413/500）は常に HTML 文書。
- すべての応答に `Vary: Shomen-Target` を付ける。既存のセキュリティヘッダ 3 つはそのまま。
- `render_fragment` の応答は `text/html; charset=utf-8` で、`<!DOCTYPE html>` と `<html>` を含まない。
- モジュール境界: HTML（`view.cr`、`a11y.cr`、`fragment.cr`）は Server と Island を知らない。Island は Route に依存してよい。Store、Event、Command、Projection は変えない。
- 公開 API は `Shomen::` 配下だけ。1 ファイル 1 主要型。ファイル名は機能名。
- SPA ルーター、`history.pushState`、WebSocket、SSE、島（`data-shomen-island`）、CSP、`ETag`、断片キャッシュを作らない（フェーズ 5 以降）。
- 色コード、デザイントークン、国際化の仕組みを作らない。
- コードと識別子は英語。この計画と決定ログは日本語。
- ユーザーが指示するまで commit しない。この計画に commit 手順は無い。
- `crystal tool format` を通し、警告を残して完了にしない。
- テストは固定ポートを bind しない。ブラウザ spec だけが `127.0.0.1` の一時ポート（`bind_tcp("127.0.0.1", 0)`）を使う。sleep で同期しない（ブラウザの待ちは `MutationObserver` と DevTools のイベントで行い、20 秒の上限は失敗の検出だけに使う）。ポート 3000 を使うのは Task 7 の手動確認だけ。
- 検証でリポジトリルートにできる実行ファイル `shomen` は `docs/decisions/20260928-build-artifact.md` のとおり削除する。

実行はリポジトリルートで行う。`Shomen::VERSION` は `"0.0.0"` のまま変えない。

## Review Focus

- 別オリジンのリンク、修飾キー付きのクリック、新しいタブ。`data-shomen-get` が別オリジンの URL を指す、Ctrl / Cmd / 中ボタンでクリックする、`target="_blank"` のリンク。どれも `shomen.js` は触らず、ブラウザの既定の動作に任せる。別オリジンの HTML を取ってきてページに差し込むことはしない。Task 6 の "leaves cross-origin, modified, and new-window clicks to the browser" で固定する。
- 同じ URL の 2 つの表現。JS で断片を取った URL を、戻る・再読み込み・直接開くと、断片ではなく文書が出る。サーバはすべての応答に `Vary: Shomen-Target` を付ける。Task 3 の "sends Vary: Shomen-Target on every response" で固定する。
- fetch の最中のエラー応答。CSRF 期限切れの 403、古いフォームの 409、500 は対象 `id` を含まない HTML 文書で返る。`shomen.js` は POST を送り直さず、その文書をページ全体として表示する。要素の中にエラーページを入れ子にしない。Task 6 の "shows a response without the element as the whole page after a POST" で固定する。
- 二重送信。応答を待っている間に同じ要素へ 2 回目の送信やクリックがあっても、リクエストは 1 回だけ。Task 6 の "sends one request when a form is submitted twice before the answer" で固定する。
- 壊れた `Shomen-Target`。空、空白を含む、2 つ付いている値は 400 の HTML 文書。ルートに不正な `id` を渡さない。Task 3 の "answers a malformed Shomen-Target with 400" で固定する。

## File Map

| ファイル | 役割 | Task |
|---|---|---|
| `docs/en/02-PHASES.md`、`docs/02-PHASES.md` | 現行フェーズをフェーズ 4 にする | 1 |
| `docs/en/00-INSTRUCTION.md`、`docs/00-INSTRUCTION.md` | 仕様 4 に `json`、仕様 9 の JSON エラー形式 | 1 |
| `docs/decisions/20260929-phase4-*.md` | D1〜D8 | 1 |
| `src/shomen/fragment.cr` | `Shomen::Fragment`。`content`、`html` の禁止 | 2 |
| `src/shomen/view.cr` | `embed`（Task 2）、`SCRIPT_PATH` と `shomen_script`（Task 4） | 2, 4 |
| `src/shomen/route.cr` | `render_fragment`、`render` の断片拒否（Task 2）、`target`、`TARGET_HEADER`、`target_of`、`json`（Task 3） | 2, 3 |
| `src/shomen/server.cr` | `Vary: Shomen-Target` | 3 |
| `src/shomen/island.cr` | `Shomen::Island`。`SOURCE` と `Script` ルート | 4 |
| `src/shomen/assets/shomen.js` | 公式 JavaScript | 4, 6 |
| `src/shomen.cr` | `fragment` と `island` の require | 2, 4 |
| `spec/spec_helper.cr` | `call_with` の `headers:`、新しい support の require | 2, 3, 5, 6 |
| `spec/support/fragment_routes.cr` | 断片、`target`、JSON を確かめるルート | 2, 3 |
| `spec/support/browser.cr` | `Browser`（CDP クライアント）、`with_browser`、`with_live_server` | 5 |
| `spec/support/browser_routes.cr` | ブラウザ spec のページとルート | 6 |
| `spec/fixtures/fragment_with_html.cr`、`spec/fixtures/render_with_fragment.cr`、`spec/fixtures/render_fragment_with_document.cr` | コンパイル失敗のフィクスチャ | 2 |
| `spec/shomen/fragment_spec.cr` | Task 2 | 2 |
| `spec/shomen/fragment_request_spec.cr`、`spec/shomen/json_spec.cr` | Task 3 | 3 |
| `spec/shomen/island_spec.cr` | Task 4 | 4 |
| `spec/shomen/browser_spec.cr` | Task 5 | 5 |
| `spec/shomen/script_spec.cr` | Task 6 | 6 |
| `examples/hello/src/hello.cr` | `Greeting` を断片と `shomen.js` に対応させる | 7 |
| `examples/hello/spec/greeting_fetch_spec.cr` | 例での受入 | 7 |
| `README.md`、`README.ja.md`、`CONTRIBUTING.md`、`CONTRIBUTING.ja.md` | フェーズ 4 の反映、Chrome の要件 | 8 |

---

### Task 1: 現行フェーズ、仕様、決定ファイル

**Files:**
- Modify: `docs/en/02-PHASES.md:5-9`
- Modify: `docs/02-PHASES.md:5-9`
- Modify: `docs/en/00-INSTRUCTION.md:148-152`、`docs/en/00-INSTRUCTION.md:243`
- Modify: `docs/00-INSTRUCTION.md:148-152`、`docs/00-INSTRUCTION.md:243`
- Create: `docs/decisions/20260929-phase4-fragment-view.md`
- Create: `docs/decisions/20260929-phase4-fragment-request.md`
- Create: `docs/decisions/20260929-phase4-script-attributes.md`
- Create: `docs/decisions/20260929-phase4-script-response.md`
- Create: `docs/decisions/20260929-phase4-script-serving.md`
- Create: `docs/decisions/20260929-phase4-json-response.md`
- Create: `docs/decisions/20260929-phase4-browser-spec.md`
- Create: `docs/decisions/20260929-phase4-greeting-example.md`

**Interfaces:**
- Consumes: なし
- Produces: 後続タスクが従う決定 D1〜D8。ここで決めた名前（`Shomen::Fragment`、`content`、`embed`、`render_fragment`、`Shomen::Route::TARGET_HEADER`、`Shomen::Route#target`、`Shomen::Route.target_of`、`json`、`Shomen::Island::SOURCE`、`Shomen::Island::Script`、`Shomen::View::SCRIPT_PATH`、`shomen_script`、`Browser`、`SHOMEN_CHROME`）は Task 2〜7 のコードと一致させる。

- [ ] **Step 1: 現行フェーズを書き換える（英語）**

`docs/en/02-PHASES.md` の「## Current phase」の本文を次にする。

```markdown
## Current phase

**Phase 4 — fragments and fetch**

Phase 3 acceptance is met. Do not implement past this point (phase 5 and later). When phase 4 acceptance is met, stop and wait for the next instruction.
```

- [ ] **Step 2: 現行フェーズを書き換える（日本語訳）**

`docs/02-PHASES.md` の「## 現行フェーズ」の本文を次にする。見出しの表記は同じファイルの「## フェーズ 4 — 断片と fetch」に合わせる。

```markdown
## 現行フェーズ

**フェーズ 4 — 断片と fetch**

フェーズ 3 の受入は満たした。ここより先（フェーズ 5 以降）を実装しない。4 の受入を満たしたら停止し、ユーザーの次指示を待つ。
```

- [ ] **Step 3: 仕様 4 と 9 を直す（英語）**

`docs/en/00-INSTRUCTION.md` の「### 4. Responses」の Helpers を次にする（`json` の行を足す）。

```markdown
Helpers:

- `render(view)` returns 200 and `text/html; charset=utf-8`
- `render_fragment(view)` returns 200 and a fragment, without a document `<html>`
- `json(value, status = 200)` returns `application/json` with `value.to_json`. The server never chooses JSON on its own
- `redirect(path, status = 303)`
```

「### 9. Error model」の最後の行「A JSON error format is undefined until phase 4.」を次にする。

```markdown
Errors are HTML documents, also for a route that returns JSON. There is no JSON error format (`docs/decisions/20260929-phase4-json-response.md`).
```

- [ ] **Step 4: 仕様 4 と 9 を直す（日本語訳）**

`docs/00-INSTRUCTION.md` の「ヘルパ:」の箇条書きを次にする。

```markdown
ヘルパ:

- `render(view)` → 200 + `text/html; charset=utf-8`
- `render_fragment(view)` → 200 + 断片。文書の `<html>` を含めない
- `json(value, status = 200)` → `application/json` + `value.to_json`。サーバが自分で JSON を選ぶことはない
- `redirect(path, status = 303)`
```

「### 9. エラーモデル」の最後の行「JSON エラー形式はフェーズ 4 まで定義しない。」を次にする。

```markdown
エラーは、JSON を返すルートでも HTML 文書で返す。JSON のエラー形式は無い（`docs/decisions/20260929-phase4-json-response.md`）。
```

- [ ] **Step 5: D1 を書く**

`docs/decisions/20260929-phase4-fragment-view.md`:

```markdown
# 状況

仕様 4 は `render_fragment(view)` が文書の `<html>` を含まない断片を返すとする。01-ARCHITECTURE は断片ビューの根要素を 1 つとし、文書と断片を 1 クラスに詰め込まなくてよいとする。フェーズ 3 までの `Shomen::View` は、文書なら `html` マクロが出力をやり直し、そうでなければ呼ぶ側が `result` を返していた。

# 決定

`abstract class Shomen::Fragment < Shomen::View` を足す。サブクラスは `content : Nil` を実装する。`to_html` は `Fragment` が持ち、出力を空にしてから `content` を呼んで結果を返す。`Fragment` は `html` マクロを上書きし、断片の中で `html` を書くとコンパイルエラーにする。

`Shomen::View#embed(fragment : Shomen::Fragment)` で文書ビューに断片を埋め込む。`Shomen::Route#render_fragment(view : Shomen::Fragment, status = 200)` は断片だけを 200 の `text/html; charset=utf-8` で返す。`render` に `Shomen::Fragment` を渡すとコンパイルエラー、`render_fragment` に文書ビューを渡すと型が合わずコンパイルエラーになる。

根要素が 1 つであることは検査しない。

# 理由

文書と断片の取り違えは、JS 無しで断片だけが届く、または要素の中に文書が入れ子になる事故になる。型で分ければコンパイル時に止まる。`embed` で同じ断片クラスを文書と断片応答の両方で使えるので、「同じビューを断片として返せる」（仕様 8）を満たす。根要素の数は HTML を解析しないとわからず、`shomen.js` は応答から `id` で要素を探すので、数を強制しなくても動く。

# 破棄した案

- `render_fragment(view : Shomen::View)` で出力が `<!DOCTYPE` で始まるかを実行時に調べる（コンパイル時に止まらない）
- ビューに `fragment?` を渡して 1 クラスで文書と断片を切り替える（文書の骨組みと断片の中身が 1 つのメソッドに混ざる）
- 根要素の数を実行時に数える（HTML の解析が要る）
```

- [ ] **Step 6: D2 を書く**

`docs/decisions/20260929-phase4-fragment-request.md`:

```markdown
# 状況

ルートは断片と文書の両方を返せる。どちらを返すかを、ルートは要求から知る必要がある。JS が無いときは同じ URL で文書を返さなければならない。

# 決定

`shomen.js` は差し替える要素の `id` を `Shomen-Target` ヘッダに入れて送る。ルートは `target : String?` で読む。ヘッダが無ければ `nil`。値が空、ASCII の空白を含む、不正な UTF-8、ヘッダが 2 つ以上（連結されて `", "` を含む）のときは `Shomen::BadInput` で 400。

どちらを返すかはルートが決める（`target ? render_fragment(...) : render(...)`）。サーバはすべての応答に `Vary: Shomen-Target` を付ける。

# 理由

リンクとフォームの URL を JS の有無で変えないので、JS が無くても同じ URL が文書を返す。ヘッダの値を `id` にすると、1 つのルートが複数の場所に断片を返すときにも区別できる。`Vary` が無いと、ブラウザや中継のキャッシュが断片を文書として出すことがある。HTML の `id` は空でなく空白を含まないので、それ以外はクライアントの誤りとして 400 にする。

# 破棄した案

- クエリ文字列（`?_fragment=id`）で知らせる（URL が JS の有無で変わり、ルートの `Input` と混ざる）
- `Accept` で知らせる（`text/html` の文書と断片を区別できない）
- `HX-Request` など他のライブラリのヘッダ名を借りる（互換レイヤを作らない）
- `Vary` を断片を返したときだけ付ける（文書の応答もキャッシュの鍵を分ける必要がある）
```

- [ ] **Step 7: D3 を書く**

`docs/decisions/20260929-phase4-script-attributes.md`:

```markdown
# 状況

フェーズ 4 は `shomen.js` の `data-shomen-get` と `data-shomen-post` で対象 `id` を差し替える。受入は、JS 無しでフェーズ 2 のフォームが動くこと。仕様 8 は属性を `data-shomen-*` だけとする。

# 決定

`<a href="..." data-shomen-get="ID">` と `<form method="post" action="..." data-shomen-post="ID">` を使う。属性の値は差し替える要素の `id`。URL はリンクの `href`、フォームの `action` から取る。

`shomen.js` は次のときは触らず、ブラウザの既定の動作に任せる:

- 別オリジンの URL
- 左ボタン以外のクリック、Ctrl / Cmd / Shift / Alt 付きのクリック
- `target` が `_self` 以外、`download` 付きのリンク
- `method` が `post` でないフォーム、`enctype` が `application/x-www-form-urlencoded` でないフォーム、`target` が `_self` 以外のフォーム
- `formaction`、`formmethod`、`formenctype`、`formtarget` を持つボタンからの送信
- 他のリスナーが `preventDefault` した操作
- 値の `id` の要素がページに無いとき

フォームの属性は `getAttribute` で読む。フォームの値は `new URLSearchParams(new FormData(form, submitter))` で urlencoded にして送る。

# 理由

URL を `href` と `action` に置くので、JS が無くても同じリンクとフォームが動く。別オリジンの HTML をページに差し込むと、そのオリジンがページにマークアップを入れられる。修飾キーや `target` は利用者が新しいタブを選んだ合図である。サーバはフォームを urlencoded でしか読まない（フェーズ 2）。`form.action` などのプロパティは、同じ名前の入力欄があると入力欄を返すので、属性を読む。

# 破棄した案

- `data-shomen-get="/url"` と `data-shomen-target="ID"` の 2 属性（URL が JS 無しで使われない）
- `button` や任意の要素にも付けられるようにする（JS 無しで動かない）
- `FormData` を multipart のまま送る（サーバが読めない）
```

- [ ] **Step 8: D4 を書く**

`docs/decisions/20260929-phase4-script-response.md`:

```markdown
# 状況

`shomen.js` は応答で対象の要素を差し替える。応答は断片、文書、リダイレクト、エラー文書のどれかになる。受入は、JS 有効時に指定要素だけが差し替わること。

# 決定

`shomen.js` は応答を次の順で扱う。

1. fetch がリダイレクトを辿った（`response.redirected`）: `location.assign(response.url)` でその URL を読み込む
2. 応答に対象と同じ `id` の要素がある: 対象をその要素で置き換える。状態コードは問わない（422 の再表示も置き換える）
3. GET: `location.assign(url)` でその URL を読み込む
4. POST: 応答の文書をページ全体として表示する（`documentElement` を置き換える）。送り直さない

応答の HTML は `<template>` で解析し、スクリプトを実行しない。置き換えの前にフォーカスが対象の中にあり、フォーカスされていた要素に `id` があれば、置き換えた後に同じ `id` の要素へフォーカスを戻す。

要求の間、対象に `aria-busy="true"` を付ける。付いている間の同じ対象への操作は `preventDefault` して捨てる。

通信が失敗したとき、GET は `location.assign(url)` し、POST はページをそのままにしてエラーを投げ直す。

履歴（`history.pushState`）とスクロール位置は変えない。

# 理由

POST の後のリダイレクトは別のリソースへ移ることを意味するので、URL と履歴が正しいページ読み込みにする。要素の一部だけを他のページから取ると、見出しなど対象の外の表示が古いまま残る。対象の `id` が無い応答は、エラー文書か、ルートが断片に対応していない応答である。GET はもう一度送っても安全なので普通に読み込み、POST は二重に追記しないよう受け取った文書をそのまま出す。フォーカスを戻さないと、キーボードと読み上げの利用者は置き換えのたびにページの先頭へ戻される。`aria-busy` は支援技術に更新中を伝える標準の属性で、二重送信の目印を兼ねる。履歴を書き換えるのはクライアントルーターの仕事で、範囲外である。

# 破棄した案

- `redirect: "manual"` でリダイレクトを止める（`Location` を読めない不透明な応答になる）
- リダイレクト先の応答からも対象の `id` を探して置き換える（対象の外の表示が古いまま残る）
- 対象の `id` が無い POST の応答で `form.submit()` し直す（二重に追記する）
- `document.write` で文書を書き換える（ページのリスナーが消え、仕様上も非推奨）
- `aria-busy` の代わりに JS の中の集合で送信中を覚える（支援技術に伝わらない）
```

- [ ] **Step 9: D5 を書く**

`docs/decisions/20260929-phase4-script-serving.md`:

```markdown
# 状況

01-ARCHITECTURE は `src/shomen/assets/shomen.js` を静的ファイルとしてビルド無しで配り、配るのは `Shomen::Island`（Server に依存してよい）とする。HTML は Server を知らない。フェーズ 5 の受入は、島の外にイベントリスナーを撒かないこと。

# 決定

`Shomen::Island::SOURCE` は `{{ read_file("#{__DIR__}/assets/shomen.js") }}` でコンパイル時に読み込んだ文字列。`Shomen::Island::Script < Shomen::Route` が `GET /shomen.js` で `text/javascript; charset=utf-8` として返す。ルートとして登録されるのでサーバは変えない。キャッシュのヘッダは付けない。

`Shomen::View::SCRIPT_PATH = "/shomen.js"` を置き、`shomen_script` が `<script src="/shomen.js" defer></script>` を書く。DSL が書く `script` 要素はこれだけ。`Shomen::Island::Script.path` と `SCRIPT_PATH` が同じことは spec で確かめる。

`shomen.js` は `document` に `click` と `submit` のリスナーを 1 つずつ付け、そこで `data-shomen-get` と `data-shomen-post` を探す。要素ごとにリスナーを付けない。

# 理由

コンパイル時に埋め込むと、アプリの作業ディレクトリやインストール先に関係なく同じファイルが配られ、ビルド手順も要らない。ルートにすれば登録と重複検査が既存の仕組みで済み、HTML が Island を知らずに済む。外部ファイルにするので、フェーズ 6 の CSP で `script-src 'self'` にできる。`document` への委譲は要素ごとのリスナーを撒かず、差し替えで入った要素にもそのまま効く。キャッシュは後のフェーズ（`ETag`）で扱う。

# 破棄した案

- 実行時に `src/shomen/assets/shomen.js` をディスクから読む（配置先で壊れる）
- サーバが `/shomen.js` を特別扱いする（Server が Island を知る）
- インラインの `<script>` で配る（CSP と両立しない）
- `script` 要素を DSL に足す（任意のスクリプトを書けてしまう）
```

- [ ] **Step 10: D6 を書く**

`docs/decisions/20260929-phase4-json-response.md`:

```markdown
# 状況

仕様 2 は JSON をフェーズ 4 以降、ルートが求めたときだけとする。仕様 9 は JSON のエラー形式をフェーズ 4 まで定義しないとしていた。フェーズ 4 の Build は「ルートが求めたときだけ JSON 応答」だけで、エラー形式を挙げていない。

# 決定

`Shomen::Route#json(value, status = 200)` を足す。`value.to_json` を本文にし、`Content-Type` は `application/json`。サーバは `Accept` を見ない。

エラー（400、403、404、409、413、500）は、JSON を返すルートでも HTML 文書のままにする。JSON のエラー形式は作らない。仕様 9 をそう書き直す。

# 理由

「ルートが求めたとき」を、ルートが `json` を呼んだときと読むのが最小である。エラー形式を足すには、ルートが JSON だと宣言する仕組みと、ルートが決まる前のエラー（CSRF の 403、未照合の 404、413）の扱いが要り、フェーズ 4 の受入に関係しない。計画時にユーザーがこの案を選んだ。

# 破棄した案

- ルートが `format json` を宣言し、そのルートの中で起きた例外を `{"error": "..."}` にする（ルート確定前のエラーは HTML のままで、形式が混ざる）
- `Accept: application/json` で形式を切り替える（「ルートが求めたときだけ」に反する）
```

- [ ] **Step 11: D7 を書く**

`docs/decisions/20260929-phase4-browser-spec.md`:

```markdown
# 状況

フェーズ 4 の受入「JS 有効では指定要素だけが差し替わる」は、ブラウザで JS を動かさないと確かめられない。公式 JS は npm に依存しない。本体の依存 shard は決定ファイル無しに増やせない。仕様はテストに実ポートを取らせず、一時ポートを使わせる。

# 決定

`spec/support/browser.cr` に、標準ライブラリの `HTTP::WebSocket` と `HTTP::Client` だけで書いた DevTools プロトコルのクライアント `Browser` を置く。Chrome を `--headless --remote-debugging-port=0` と一時プロファイルで起動し、標準エラーの `DevTools listening on ws://…` から接続先を読む。`Page.navigate`、`Page.loadEventFired`、`Runtime.evaluate`（`awaitPromise`）だけを使う。

Chrome は `SHOMEN_CHROME`、macOS の `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`、`PATH` の `google-chrome`、`chromium`、`chromium-browser` の順に探す。見つからなければブラウザ spec は `pending` になる。

ブラウザ spec は `Shomen::Server` を `127.0.0.1` の一時ポートで動かす。待ちはページ内の `MutationObserver` と DevTools のイベントで行い、20 秒を過ぎたら失敗にする。

# 理由

受入を手で確かめるだけでは回帰を捕まえられない。CDP は WebSocket と JSON だけで話せるので、shard も npm も足さずに済む。Chrome が無い環境で `crystal spec` 全体を落とさないために `pending` にし、フェーズの完了確認では Chrome のある開発機で pending が 0 件であることを確かめる。計画時にユーザーがこの案を選んだ。

# 破棄した案

- Playwright や Puppeteer（npm に依存する）
- jsdom や happy-dom を Node で動かす（npm に依存する）
- `chrome --dump-dom --virtual-time-budget`（操作を挟めず、macOS では出力の後に終了しないことがあった）
- 手動のブラウザ確認だけにする（回帰を捕まえられない）
```

- [ ] **Step 12: D8 を書く**

`docs/decisions/20260929-phase4-greeting-example.md`:

```markdown
# 状況

フェーズ 4 の受入は、JS 無しでフェーズ 2 のフォーム（`examples/hello` の `Greeting`）が動くことと、JS 有りで指定要素だけが差し替わること。

# 決定

`Greeting::FormView < Shomen::Fragment` を足し、根要素を `div(id: "greeting-form")` にする。中身はエラーの `p`（`role: "alert"`）と、`data-shomen-post: "greeting-form"` を付けたフォーム。保存ボタンに `id: "greeting-save"` を付ける。`Greeting::EditView` は見出しの後に `embed` で `FormView` を埋め込む。

`Greeting::ShowView` は `div(id: "greeting-form")` の中に「Change」リンク（`data-shomen-get: "greeting-form"`）を置く。両方の文書は `head` で `shomen_script` を呼ぶ。

`Greeting::Edit` と `Greeting::Update` の 422 は、`target` があれば `render_fragment(FormView)`、無ければ今までどおり文書を返す。正しい名前は今までどおり 303 で `Greeting::Show` へ移る。`Users` の例は変えない。

# 理由

同じフォームを、JS 無しでは今までの文書とリダイレクトで、JS 有りでは「Change」で表示中のページにフォームを差し込み、422 ではフォームだけを差し替えて動かせる。フェーズ 2 の spec はそのまま通る。`role="alert"` で差し替え後のエラーが読み上げられ、ボタンの `id` で置き換えの後もフォーカスが保存ボタンに戻る。

# 破棄した案

- 新しい例 `examples/fetch` を作る（受入はフェーズ 2 のフォームを名指ししている）
- `Users` の名前変更も断片にする（受入に要らない）
```

- [ ] **Step 13: 文書だけの変更を確かめる**

Run: `git status --short`
Expected: 上の 12 ファイルだけが変更・追加されている。コードは変えていない。

---

### Task 2: Fragment、render_fragment、embed

**Files:**
- Create: `src/shomen/fragment.cr`
- Modify: `src/shomen/view.cr`（`embed` を足す）
- Modify: `src/shomen/route.cr:506-508`（`render` の断片拒否と `render_fragment`）
- Modify: `src/shomen.cr`（`require "./shomen/fragment"` を `a11y` の後に）
- Modify: `spec/spec_helper.cr`（`require "./support/fragment_routes"`）
- Create: `spec/support/fragment_routes.cr`
- Create: `spec/fixtures/fragment_with_html.cr`
- Create: `spec/fixtures/render_with_fragment.cr`
- Create: `spec/fixtures/render_fragment_with_document.cr`
- Test: `spec/shomen/fragment_spec.cr`

**Interfaces:**
- Consumes: `Shomen::View`（`reset`、`result`、`@out`、要素メソッド）、`Shomen::Response.html(body, status)`、`crystal_build_fixture(path) : {Int32, String}`
- Produces:
  - `abstract class Shomen::Fragment < Shomen::View` と `abstract def content : Nil`、`def to_html : String`
  - `Shomen::View#embed(fragment : Shomen::Fragment) : Nil`
  - `Shomen::Route#render_fragment(view : Shomen::Fragment, status : Int32 = 200) : Shomen::Response`
  - `FragmentRoutes::NoteFragment`（`div#note` の中に `p`）、`FragmentRoutes::NotePage`（文書）、`FragmentRoutes::Note`（`GET /phase4/note`）

- [ ] **Step 1: support のルートを書く**

`spec/support/fragment_routes.cr`:

```crystal
module FragmentRoutes
  class NoteFragment < Shomen::Fragment
    def initialize(@message : String)
    end

    def content : Nil
      message = @message
      div(id: "note") do
        p message
      end
    end
  end

  class NotePage < Shomen::View
    def initialize(@message : String)
    end

    def to_html : String
      message = @message
      html lang: "en" do
        head do
          title "Note"
        end
        body do
          main do
            h1 "Note"
            embed NoteFragment.new(message)
          end
        end
      end
    end
  end

  class Note < Shomen::Route
    method GET
    path "/phase4/note"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render_fragment NoteFragment.new("<saved>")
    end
  end
end
```

`spec/spec_helper.cr` の `require "./support/projections"` の後に足す:

```crystal
require "./support/fragment_routes"
```

- [ ] **Step 2: コンパイル失敗のフィクスチャを書く**

`spec/fixtures/fragment_with_html.cr`:

```crystal
require "../../src/shomen"

class FragmentWithHtml < Shomen::Fragment
  def content : Nil
    html lang: "en" do
      head do
        title "Nested"
      end
    end
  end
end

FragmentWithHtml.new.to_html
```

`spec/fixtures/render_with_fragment.cr`:

```crystal
require "../../src/shomen"

class RenderedFragment < Shomen::Fragment
  def content : Nil
    p "hi"
  end
end

class RenderWithFragment < Shomen::Route
  method GET
  path "/fixture"

  struct Input
  end

  def call(input : Input) : Shomen::Response
    render RenderedFragment.new
  end
end

Shomen::Router.entries
```

`spec/fixtures/render_fragment_with_document.cr`:

```crystal
require "../../src/shomen"

class DocumentPage < Shomen::View
  def to_html : String
    html lang: "en" do
      head do
        title "Page"
      end
    end
  end
end

class RenderFragmentWithDocument < Shomen::Route
  method GET
  path "/fixture"

  struct Input
  end

  def call(input : Input) : Shomen::Response
    render_fragment DocumentPage.new
  end
end

Shomen::Router.entries
```

- [ ] **Step 3: 失敗する spec を書く**

`spec/shomen/fragment_spec.cr`:

```crystal
require "../spec_helper"

describe Shomen::Fragment do
  it "renders its element without a document" do
    FragmentRoutes::NoteFragment.new("<hi>").to_html.should eq("<div id=\"note\"><p>&lt;hi&gt;</p></div>")
  end

  it "renders the same html each time" do
    note = FragmentRoutes::NoteFragment.new("a")
    note.to_html.should eq(note.to_html)
  end

  it "is embedded in a document view" do
    FragmentRoutes::NotePage.new("<hi>").to_html.should eq(
      "<!DOCTYPE html><html lang=\"en\"><head><title>Note</title></head>" \
      "<body><main><h1>Note</h1><div id=\"note\"><p>&lt;hi&gt;</p></div></main></body></html>"
    )
  end

  it "is sent alone by render_fragment" do
    response = call_with(Shomen::Server.new, "GET", "/phase4/note")
    response.status_code.should eq(200)
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    response.body.should eq("<div id=\"note\"><p>&lt;saved&gt;</p></div>")
  end

  it "keeps the status given to render_fragment" do
    response = FragmentRoutes::Note.new.render_fragment(FragmentRoutes::NoteFragment.new("x"), status: 422)
    response.status.should eq(422)
    response.body.should eq("<div id=\"note\"><p>x</p></div>")
  end

  it "rejects html inside a fragment at compile time" do
    status, output = crystal_build_fixture("spec/fixtures/fragment_with_html.cr")
    status.should_not eq(0)
    output.should contain("a fragment cannot contain html")
  end

  it "rejects render with a fragment at compile time" do
    status, output = crystal_build_fixture("spec/fixtures/render_with_fragment.cr")
    status.should_not eq(0)
    output.should contain("render takes a document view")
  end

  it "rejects render_fragment with a document view at compile time" do
    status, output = crystal_build_fixture("spec/fixtures/render_fragment_with_document.cr")
    status.should_not eq(0)
    output.should contain("render_fragment")
  end
end
```

- [ ] **Step 4: 失敗を確かめる**

Run: `crystal spec spec/shomen/fragment_spec.cr`
Expected: コンパイルエラー `undefined constant Shomen::Fragment`。

- [ ] **Step 5: Fragment を書く**

`src/shomen/fragment.cr`:

```crystal
require "./view"

# A view of one element to put inside a document, never a document
# itself. A view embeds it; a route sends it alone with render_fragment.
abstract class Shomen::Fragment < Shomen::View
  macro html(*args, **kwargs, &block)
    {% raise "a fragment cannot contain html; use Shomen::View for a document" %}
  end

  abstract def content : Nil

  def to_html : String
    reset
    content
    result
  end
end
```

`src/shomen/view.cr` の `raw` の後に足す:

```crystal
  def embed(fragment : Shomen::Fragment) : Nil
    @out << fragment.to_html
  end
```

`src/shomen.cr` の `require "./shomen/a11y"` の後に足す:

```crystal
require "./shomen/fragment"
```

- [ ] **Step 6: render_fragment を書く**

`src/shomen/route.cr` の `render` を次にする（`redirect` はそのまま）:

```crystal
  def render(view : Shomen::View, status : Int32 = 200) : Shomen::Response
    Shomen::Response.html(view.to_html, status)
  end

  def render(view : Shomen::Fragment, status : Int32 = 200) : Shomen::Response
    {% raise "render takes a document view; send a Shomen::Fragment with render_fragment" %}
  end

  def render_fragment(view : Shomen::Fragment, status : Int32 = 200) : Shomen::Response
    Shomen::Response.html(view.to_html, status)
  end
```

- [ ] **Step 7: 通ることを確かめる**

Run: `crystal spec spec/shomen/fragment_spec.cr`
Expected: 8 examples, 0 failures。

Run: `crystal spec && crystal tool format --check && crystal build src/shomen.cr --error-trace && rm -f shomen`
Expected: 0 failures、書式の差分なし、警告なし。

---

### Task 3: Shomen-Target、Vary、json

**Files:**
- Modify: `src/shomen/route.cr`（`require "json"`、`TARGET_HEADER`、`target`、`target_of`、`handle` で `target` を入れる、`json`）
- Modify: `src/shomen/server.cr:724-738`（`Vary`）
- Modify: `spec/spec_helper.cr:12-22`（`call_with` に `headers:`）
- Modify: `spec/support/fragment_routes.cr`（`Note` の分岐、`Target`、`PostTarget`、`Json`、`JsonMissing`）
- Test: `spec/shomen/fragment_request_spec.cr`
- Test: `spec/shomen/json_spec.cr`

**Interfaces:**
- Consumes: Task 2 の `render_fragment`、`FragmentRoutes::NoteFragment`、`FragmentRoutes::NotePage`
- Produces:
  - `Shomen::Route::TARGET_HEADER = "Shomen-Target"`
  - `Shomen::Route#target : String?`（`property`）
  - `Shomen::Route.target_of(request : HTTP::Request) : String?`（不正なら `Shomen::BadInput`）
  - `Shomen::Route#json(value, status : Int32 = 200) : Shomen::Response`
  - すべての応答の `Vary: Shomen-Target`
  - `call_with(..., headers : HTTP::Headers = HTTP::Headers.new)`

- [ ] **Step 1: call_with にヘッダを渡せるようにする**

`spec/spec_helper.cr` の `call_with` を次にする:

```crystal
def call_with(server : Shomen::Server, method : String, path : String, cookie : String? = nil, body : String? = nil, content_type : String = "application/x-www-form-urlencoded", headers : HTTP::Headers = HTTP::Headers.new) : HTTP::Client::Response
  headers = headers.dup
  headers["Cookie"] = cookie if cookie
  headers["Content-Type"] = content_type if body
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  server.call(HTTP::Server::Context.new(HTTP::Request.new(method, path, headers, body), response))
  response.close
  HTTP::Client::Response.from_io(IO::Memory.new(io.to_s))
end
```

- [ ] **Step 2: support のルートを足す**

`spec/support/fragment_routes.cr` の `Note#call` を次にする:

```crystal
    def call(input : Input) : Shomen::Response
      return render_fragment NoteFragment.new("<saved>") if target
      render NotePage.new("<saved>")
    end
```

同じモジュールの `Note` の後に足す:

```crystal
  class Target < Shomen::Route
    method GET
    path "/phase4/target"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html(Shomen::HTML.escape(target || "none"))
    end
  end

  class PostTarget < Shomen::Route
    method POST
    path "/phase4/target"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.html(Shomen::HTML.escape(target || "none"))
    end
  end

  class Json < Shomen::Route
    method GET
    path "/phase4/json"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      json({name: "<Ada>", count: 2}, status: 201)
    end
  end

  class JsonMissing < Shomen::Route
    method GET
    path "/phase4/json/missing"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      raise Shomen::NotFound.new
    end
  end
```

Task 2 の spec "is sent alone by render_fragment" はヘッダ無しで断片を期待していたので、次に書き換える:

```crystal
  it "is sent alone by render_fragment" do
    headers = HTTP::Headers{"Shomen-Target" => "note"}
    response = call_with(Shomen::Server.new, "GET", "/phase4/note", headers: headers)
    response.status_code.should eq(200)
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    response.body.should eq("<div id=\"note\"><p>&lt;saved&gt;</p></div>")
  end
```

- [ ] **Step 3: 失敗する spec を書く**

`spec/shomen/fragment_request_spec.cr`:

```crystal
require "../spec_helper"

private def targeted(*values : String) : HTTP::Headers
  headers = HTTP::Headers.new
  values.each { |value| headers.add("Shomen-Target", value) }
  headers
end

describe "fragment requests" do
  it "renders the document without Shomen-Target" do
    response = call_with(Shomen::Server.new, "GET", "/phase4/note")
    response.status_code.should eq(200)
    response.body.should start_with("<!DOCTYPE html>")
    response.body.should contain("<div id=\"note\"><p>&lt;saved&gt;</p></div>")
  end

  it "renders only the fragment with Shomen-Target" do
    response = call_with(Shomen::Server.new, "GET", "/phase4/note", headers: targeted("note"))
    response.status_code.should eq(200)
    response.body.should eq("<div id=\"note\"><p>&lt;saved&gt;</p></div>")
  end

  it "gives the route the target id" do
    call_with(Shomen::Server.new, "GET", "/phase4/target", headers: targeted("a&b")).body.should eq("a&amp;b")
    call_with(Shomen::Server.new, "GET", "/phase4/target").body.should eq("none")
  end

  it "gives the target to a POST that passes the csrf check" do
    server = Shomen::Server.new
    first = call_with(server, "GET", "/phase2/token")
    body = URI::Params.encode({"_csrf" => first.body})
    response = call_with(server, "POST", "/phase4/target", session_cookie(first), body, headers: targeted("box"))
    response.status_code.should eq(200)
    response.body.should eq("box")
  end

  it "answers a malformed Shomen-Target with 400" do
    ["", "a b", "a\tb"].each do |value|
      response = call_with(Shomen::Server.new, "GET", "/phase4/target", headers: targeted(value))
      response.status_code.should eq(400)
      response.body.should contain("<title>Bad input</title>")
    end
    call_with(Shomen::Server.new, "GET", "/phase4/target", headers: targeted("a", "b")).status_code.should eq(400)
  end

  it "sends Vary: Shomen-Target on every response" do
    ["/phase4/note", "/phase1/missing", "/phase1/boom", "/phase1/redirect"].each do |path|
      call_with(Shomen::Server.new, "GET", path).headers["Vary"].should eq("Shomen-Target")
    end
  end
end
```

`spec/shomen/json_spec.cr`:

```crystal
require "../spec_helper"

private def accepting_json : HTTP::Headers
  HTTP::Headers{"Accept" => "application/json"}
end

describe "JSON responses" do
  it "sends JSON from a route that calls json" do
    response = call_with(Shomen::Server.new, "GET", "/phase4/json")
    response.status_code.should eq(201)
    response.headers["Content-Type"].should eq("application/json")
    response.body.should eq(%({"name":"<Ada>","count":2}))
    response.headers["X-Content-Type-Options"].should eq("nosniff")
  end

  it "keeps HTML for an HTML route when the client accepts JSON" do
    response = call_with(Shomen::Server.new, "GET", "/phase1/home", headers: accepting_json)
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    response.body.should contain("<h1>Hello</h1>")
  end

  it "answers errors with HTML documents when the client accepts JSON" do
    ["/phase4/json/missing", "/phase4/json/nowhere"].each do |path|
      response = call_with(Shomen::Server.new, "GET", path, headers: accepting_json)
      response.status_code.should eq(404)
      response.headers["Content-Type"].should eq("text/html; charset=utf-8")
      response.body.should contain("<title>Not found</title>")
    end
  end
end
```

- [ ] **Step 4: 失敗を確かめる**

Run: `crystal spec spec/shomen/fragment_request_spec.cr spec/shomen/json_spec.cr`
Expected: コンパイルエラー `undefined local variable or method 'target'`（support の `Note`）。

- [ ] **Step 5: Route に target と json を足す**

`src/shomen/route.cr` の先頭の require に足す:

```crystal
require "json"
```

`abstract class Shomen::Route` の先頭を次にする:

```crystal
abstract class Shomen::Route
  TARGET_HEADER = "Shomen-Target"

  property csrf_token : String = ""
  property target : String? = nil

  # The id of the element shomen.js replaces with this response, or nil
  # for a request that did not come from shomen.js. An id is not empty
  # and has no whitespace; two headers join with ", " and fail too.
  def self.target_of(request : HTTP::Request) : String?
    value = request.headers[TARGET_HEADER]?
    return nil unless value
    if value.empty? || !value.valid_encoding? || value.each_char.any?(&.ascii_whitespace?)
      raise Shomen::BadInput.new("invalid #{TARGET_HEADER} header")
    end
    value
  end
```

`Hooks` の `handle` の終わりを次にする:

```crystal
            route = new
            route.csrf_token = csrf_token
            route.target = ::Shomen::Route.target_of(request)
            route.call(input)
```

`render_fragment` の後に足す:

```crystal
  def json(value, status : Int32 = 200) : Shomen::Response
    Shomen::Response.new(status, "application/json", value.to_json)
  end
```

- [ ] **Step 6: Vary を付ける**

`src/shomen/server.cr` の `write_response` で、ルートのヘッダを写すループの直後に足す:

```crystal
    # A route may answer one URL with a document or a fragment.
    context.response.headers.add("Vary", Shomen::Route::TARGET_HEADER)
```

- [ ] **Step 7: 通ることを確かめる**

Run: `crystal spec spec/shomen/fragment_request_spec.cr spec/shomen/json_spec.cr spec/shomen/fragment_spec.cr`
Expected: 0 failures。

Run: `crystal spec && crystal tool format --check && crystal build src/shomen.cr --error-trace && rm -f shomen`
Expected: 0 failures、書式の差分なし、警告なし。

---

### Task 4: shomen.js の配信と shomen_script

**Files:**
- Create: `src/shomen/assets/shomen.js`（この Task では空の骨組み）
- Create: `src/shomen/island.cr`
- Modify: `src/shomen/view.cr`（`SCRIPT_PATH`、`shomen_script`）
- Modify: `src/shomen.cr`（`require "./shomen/island"` を `route` の後に）
- Test: `spec/shomen/island_spec.cr`

**Interfaces:**
- Consumes: `Shomen::Route`（`method`、`path`、`Input`）、`Shomen::Response.new`
- Produces:
  - `Shomen::Island::SOURCE : String`
  - `Shomen::Island::Script`（`GET /shomen.js`、`text/javascript; charset=utf-8`）
  - `Shomen::View::SCRIPT_PATH = "/shomen.js"`、`Shomen::View#shomen_script : Nil`

- [ ] **Step 1: 失敗する spec を書く**

`spec/shomen/island_spec.cr`:

```crystal
require "../spec_helper"

private def script_file : String
  "src/shomen/assets/shomen.js"
end

private class ScriptPage < Shomen::View
  def to_html : String
    html lang: "en" do
      head do
        title "Script"
        shomen_script
      end
    end
  end
end

describe Shomen::Island do
  it "serves shomen.js as JavaScript" do
    response = call_with(Shomen::Server.new, "GET", "/shomen.js")
    response.status_code.should eq(200)
    response.headers["Content-Type"].should eq("text/javascript; charset=utf-8")
    response.body.should eq(File.read(script_file))
    response.headers["X-Content-Type-Options"].should eq("nosniff")
  end

  it "writes the script element for the path it serves" do
    Shomen::Island::Script.path.should eq(Shomen::View::SCRIPT_PATH)
    ScriptPage.new.to_html.should eq(
      "<!DOCTYPE html><html lang=\"en\"><head><title>Script</title>" \
      "<script src=\"/shomen.js\" defer></script></head></html>"
    )
  end

  it "has no npm dependency and stays under 10 KB" do
    source = File.read(script_file)
    source.bytesize.should be < 10_240
    source.should_not match(/\bimport\b|\bexport\b|\brequire\s*\(/)
    File.exists?("package.json").should be_false
    Dir.glob("src/shomen/assets/*").should eq([script_file])
  end

  it "uses no data attribute outside data-shomen-" do
    source = File.read(script_file)
    source.scan(/data-[a-z-]+/).map(&.[0]).reject(&.starts_with?("data-shomen-")).should be_empty
    source.should_not contain("dataset")
  end
end
```

- [ ] **Step 2: 失敗を確かめる**

Run: `crystal spec spec/shomen/island_spec.cr`
Expected: コンパイルエラー `undefined method 'shomen_script'`。

- [ ] **Step 3: shomen.js の骨組みを置く**

`src/shomen/assets/shomen.js`（Task 6 で中身を書く）:

```js
// shomen.js: the official JavaScript of Shomen. No build step and no
// dependencies.
(() => {
  "use strict";
})();
```

- [ ] **Step 4: Island と shomen_script を書く**

`src/shomen/island.cr`:

```crystal
require "./route"

# Serves the official JavaScript. The file is read at compile time, so
# the binary carries it wherever it runs and nothing builds it.
module Shomen::Island
  SOURCE = {{ read_file("#{__DIR__}/assets/shomen.js") }}

  class Script < Shomen::Route
    method GET
    path "/shomen.js"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.new(200, "text/javascript; charset=utf-8", SOURCE)
    end
  end
end
```

`src/shomen/view.cr` の `abstract def to_html : String` の前に足す:

```crystal
  # Shomen::Island::Script serves the official JavaScript here.
  SCRIPT_PATH = "/shomen.js"
```

`csrf_field` の後に足す:

```crystal
  # The only script element the DSL writes.
  def shomen_script : Nil
    @out << "<script src=\"" << SCRIPT_PATH << "\" defer></script>"
  end
```

`src/shomen.cr` の `require "./shomen/route"` の後に足す:

```crystal
require "./shomen/island"
```

- [ ] **Step 5: 通ることを確かめる**

Run: `crystal spec spec/shomen/island_spec.cr`
Expected: 4 examples, 0 failures。

Run: `crystal spec && crystal tool format --check && crystal build src/shomen.cr --error-trace && rm -f shomen`
Expected: 0 failures、書式の差分なし、警告なし。

---

### Task 5: Browser（CDP）ヘルパー

**Files:**
- Create: `spec/support/browser.cr`
- Modify: `spec/spec_helper.cr`（`require "./support/browser"`）
- Test: `spec/shomen/browser_spec.cr`

**Interfaces:**
- Consumes: `Shomen::Server`、`HTTP::Server`、`HTTP::WebSocket`
- Produces:
  - `Browser.executable : String?`
  - `Browser.new(executable : String)`、`#visit(url : String) : Nil`、`#evaluate(expression : String) : JSON::Any`、`#wait_for(event : String) : JSON::Any`、`#close : Nil`
  - `with_browser(& : Browser ->) : Nil`
  - `with_live_server(& : String ->) : Nil`（`"http://127.0.0.1:PORT"` を渡す）

- [ ] **Step 1: 失敗する spec を書く**

`spec/shomen/browser_spec.cr`:

```crystal
require "../spec_helper"

describe Browser do
  if Browser.executable
    it "loads a page served by Shomen and evaluates a script" do
      with_live_server do |origin|
        with_browser do |browser|
          browser.visit("#{origin}/phase1/home")
          browser.evaluate("document.querySelector('h1').textContent").as_s.should eq("Hello")
          browser.evaluate("new Promise((resolve) => resolve(6 * 7))").as_i.should eq(42)
        end
      end
    end

    it "raises when a script throws" do
      with_browser do |browser|
        expect_raises(Exception, /script failed/) do
          browser.evaluate("(() => { throw new Error('boom'); })()")
        end
      end
    end
  else
    pending("drives Chrome (set SHOMEN_CHROME to a Chrome or Chromium binary)") { }
  end
end
```

`spec/spec_helper.cr` の `require "./support/fragment_routes"` の後に足す:

```crystal
require "./support/browser"
```

- [ ] **Step 2: 失敗を確かめる**

Run: `crystal spec spec/shomen/browser_spec.cr`
Expected: コンパイルエラー `can't find file './support/browser'`。

- [ ] **Step 3: Browser を書く**

`spec/support/browser.cr`:

```crystal
require "http/client"
require "http/server"
require "http/web_socket"
require "json"
require "file_utils"

# Drives a headless Chrome over the DevTools protocol with the standard
# library alone. Browser.executable is nil when no Chrome is found.
class Browser
  LIMIT      = 20.seconds
  MAC_CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

  def self.executable : String?
    if path = ENV["SHOMEN_CHROME"]?.presence
      return path
    end
    return MAC_CHROME if File.exists?(MAC_CHROME)
    Process.find_executable("google-chrome") ||
      Process.find_executable("chromium") ||
      Process.find_executable("chromium-browser")
  end

  # Chrome prints the address it listens on to stderr. The rest of its
  # output is read and dropped so the pipe never fills.
  def self.endpoint(error : IO) : {String, Int32}
    while line = error.gets
      if found = line.match(/DevTools listening on ws:\/\/([^\/:]+):(\d+)\//)
        spawn drain(error)
        return {found[1], found[2].to_i}
      end
    end
    raise "Chrome exited before it listened"
  end

  def self.drain(io : IO) : Nil
    while io.gets
    end
  rescue IO::Error
  end

  @inbox = Channel(JSON::Any).new(256)
  @events = [] of JSON::Any
  @next_id = 0

  def initialize(executable : String)
    @profile = File.tempname("shomen-chrome")
    Dir.mkdir(@profile)
    @process = Process.new(executable, [
      "--headless",
      "--disable-gpu",
      "--no-first-run",
      "--no-default-browser-check",
      "--user-data-dir=#{@profile}",
      "--remote-debugging-port=0",
      "about:blank",
    ], error: :pipe)
    host, port = Browser.endpoint(@process.error)
    page = JSON.parse(HTTP::Client.new(host, port).exec("PUT", "/json/new?about:blank").body)
    @socket = HTTP::WebSocket.new(URI.parse(page["webSocketDebuggerUrl"].as_s))
    inbox = @inbox
    @socket.on_message { |message| inbox.send(JSON.parse(message)) }
    socket = @socket
    spawn do
      socket.run
    rescue IO::Error
    end
    command("Page.enable")
  end

  # Loads url and returns after its load event.
  def visit(url : String) : Nil
    @events.clear
    command("Page.navigate", {url: url})
    wait_for("Page.loadEventFired")
  end

  # Runs a script in the page and returns its value. A promise is awaited.
  def evaluate(expression : String) : JSON::Any
    result = command("Runtime.evaluate", {expression: expression, awaitPromise: true, returnByValue: true})
    if details = result["exceptionDetails"]?
      raise "script failed: #{details.to_json}"
    end
    result["result"]["value"]? || JSON::Any.new(nil)
  end

  def wait_for(event : String) : JSON::Any
    if index = @events.index { |message| message["method"]?.try(&.as_s?) == event }
      return @events.delete_at(index)
    end
    loop do
      message = receive
      return message if message["method"]?.try(&.as_s?) == event
      @events << message
    end
  end

  def command(method : String, params = NamedTuple.new) : JSON::Any
    @next_id += 1
    id = @next_id
    @socket.send({id: id, method: method, params: params}.to_json)
    loop do
      message = receive
      if message["id"]?.try(&.as_i?) == id
        if error = message["error"]?
          raise "#{method} failed: #{error.to_json}"
        end
        return message["result"]
      end
      @events << message
    end
  end

  def close : Nil
    @socket.close
  rescue IO::Error
  ensure
    @process.terminate unless @process.terminated?
    @process.wait
    FileUtils.rm_rf(@profile)
  end

  private def receive : JSON::Any
    select
    when message = @inbox.receive
      message
    when timeout(LIMIT)
      raise "no message from Chrome within #{LIMIT}"
    end
  end
end

def with_browser(& : Browser ->) : Nil
  browser = Browser.new(Browser.executable || raise "no Chrome found; set SHOMEN_CHROME")
  begin
    yield browser
  ensure
    browser.close
  end
end

# Serves Shomen::Server on an ephemeral port on 127.0.0.1 for a browser.
def with_live_server(& : String ->) : Nil
  server = HTTP::Server.new([Shomen::Server.new])
  address = server.bind_tcp("127.0.0.1", 0)
  spawn { server.listen }
  begin
    yield "http://127.0.0.1:#{address.port}"
  ensure
    server.close
  end
end
```

- [ ] **Step 4: 通ることを確かめる**

Run: `crystal spec spec/shomen/browser_spec.cr`
Expected: 2 examples, 0 failures, 0 pending（開発機には Chrome がある）。Chrome のプロセスが残っていない（`pgrep -f shomen-chrome` が何も出さない）。

Run: `crystal spec && crystal tool format --check`
Expected: 0 failures、書式の差分なし。

---

### Task 6: shomen.js の置き換え

**Files:**
- Modify: `src/shomen/assets/shomen.js`（中身を書く）
- Create: `spec/support/browser_routes.cr`
- Modify: `spec/spec_helper.cr`（`require "./support/browser_routes"`）
- Test: `spec/shomen/script_spec.cr`

**Interfaces:**
- Consumes: Task 2〜5 のすべて（`Shomen::Fragment`、`embed`、`render_fragment`、`target`、`shomen_script`、`Browser`、`with_browser`、`with_live_server`）、`Shomen::Server::CONFLICT_DETAIL`
- Produces: `shomen.js` の挙動（D3、D4）。`BrowserRoutes::RECEIVED : Array(String)`（`"METHOD path target"`、target が無ければ `-`）

- [ ] **Step 1: ブラウザ spec のページとルートを書く**

`spec/support/browser_routes.cr`:

```crystal
module BrowserRoutes
  # "METHOD path target" for each request a spec needs to count.
  RECEIVED = [] of String

  class SlotFragment < Shomen::Fragment
    def initialize(@message : String)
    end

    def content : Nil
      message = @message
      div(id: "slot") do
        p message
      end
    end
  end

  class FormFragment < Shomen::Fragment
    def initialize(@name : String, @token : String, @error : String?)
    end

    def content : Nil
      name = @name
      token = @token
      error = @error
      div(id: "box") do
        if message = error
          p message, role: "alert"
        end
        form(action: "/phase4/browser/form", method: "post", "data-shomen-post": "box", id: "box-form") do
          csrf_field(token)
          label("Name", for: "name")
          input(id: "name", name: "name", type: "text", value: name)
          button "Save", type: "submit", id: "save"
        end
      end
    end
  end

  class PageView < Shomen::View
    def initialize(@token : String)
    end

    def to_html : String
      token = @token
      html lang: "en" do
        head do
          title "Browser"
          shomen_script
        end
        body do
          main do
            p "outside", id: "outside"
            div(id: "slot") do
              a "Load", href: "/phase4/browser/slot", "data-shomen-get": "slot", id: "load"
            end
            a "Plain", href: "/phase4/browser/plain", "data-shomen-get": "slot", id: "plain"
            embed FormFragment.new("", token, nil)
            form(action: "/phase4/browser/conflict", method: "post", "data-shomen-post": "slot") do
              csrf_field(token)
              button "Clash", type: "submit", id: "clash"
            end
          end
        end
      end
    end
  end

  class PlainView < Shomen::View
    def to_html : String
      html lang: "en" do
        head do
          title "Plain"
        end
        body do
          h1 "Plain"
        end
      end
    end
  end

  class Page < Shomen::Route
    method GET
    path "/phase4/browser"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render PageView.new(csrf_token)
    end
  end

  class Slot < Shomen::Route
    method GET
    path "/phase4/browser/slot"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      RECEIVED << "GET /phase4/browser/slot #{target || "-"}"
      if id = target
        render_fragment SlotFragment.new("loaded #{id}")
      else
        render PlainView.new
      end
    end
  end

  class Plain < Shomen::Route
    method GET
    path "/phase4/browser/plain"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      RECEIVED << "GET /phase4/browser/plain #{target || "-"}"
      render PlainView.new
    end
  end

  class Save < Shomen::Route
    method POST
    path "/phase4/browser/form"

    struct Input
      getter name : String

      def initialize(@name : String)
      end
    end

    def call(input : Input) : Shomen::Response
      RECEIVED << "POST /phase4/browser/form #{target || "-"}"
      return redirect("/phase4/browser/plain") if input.name.strip.size >= 2
      form_view = FormFragment.new(input.name, csrf_token, "Name is too short")
      return render_fragment(form_view, status: 422) if target
      render PageView.new(csrf_token), status: 422
    end
  end

  class Clash < Shomen::Route
    method POST
    path "/phase4/browser/conflict"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      raise Shomen::Conflict.new("stream browser-1 is at version 1, expected 0")
    end
  end
end
```

`spec/spec_helper.cr` の `require "./support/browser"` の後に足す:

```crystal
require "./support/browser_routes"
```

- [ ] **Step 2: 失敗する spec を書く**

`spec/shomen/script_spec.cr`:

```crystal
require "../spec_helper"

# waitFor(check) resolves with check()'s first value other than
# undefined, looking again after every change to the document.
private def wait_for_js : String
  <<-JS
    const waitFor = (check) => new Promise((resolve) => {
      const observer = new MutationObserver(() => {
        const value = check();
        if (value !== undefined) {
          observer.disconnect();
          resolve(value);
        }
      });
      observer.observe(document, {subtree: true, childList: true, attributes: true, characterData: true});
    });
    JS
end

private def run_js(browser : Browser, body : String) : JSON::Any
  browser.evaluate("(async () => {\n#{wait_for_js}\n#{body}\n})()")
end

private def on_page(& : Browser, String ->) : Nil
  BrowserRoutes::RECEIVED.clear
  with_live_server do |origin|
    with_browser do |browser|
      browser.visit("#{origin}/phase4/browser")
      yield browser, origin
    end
  end
end

describe "shomen.js" do
  if Browser.executable
    it "replaces only the element named by data-shomen-get" do
      on_page do |browser, _|
        result = run_js(browser, <<-JS)
          document.getElementById("outside").shomenMarker = "kept";
          const done = waitFor(() => document.getElementById("slot").textContent.includes("loaded") ? true : undefined);
          document.getElementById("load").click();
          await done;
          return {
            marker: document.getElementById("outside").shomenMarker,
            slot: document.getElementById("slot").outerHTML,
            path: location.pathname,
          };
          JS
        result["marker"].as_s.should eq("kept")
        result["slot"].as_s.should eq("<div id=\"slot\"><p>loaded slot</p></div>")
        result["path"].as_s.should eq("/phase4/browser")
        BrowserRoutes::RECEIVED.should eq(["GET /phase4/browser/slot slot"])
      end
    end

    it "replaces only the form on 422 and keeps the focus" do
      on_page do |browser, _|
        result = run_js(browser, <<-JS)
          document.getElementById("outside").shomenMarker = "kept";
          document.getElementById("name").value = "A";
          const save = document.getElementById("save");
          save.focus();
          const done = waitFor(() => document.querySelector("#box [role=alert]") ? true : undefined);
          save.click();
          await done;
          return {
            marker: document.getElementById("outside").shomenMarker,
            alert: document.querySelector("#box [role=alert]").textContent,
            value: document.getElementById("name").value,
            focused: document.activeElement.id,
            slot: document.getElementById("slot").textContent,
            busy: document.getElementById("box").hasAttribute("aria-busy"),
            path: location.pathname,
          };
          JS
        result["marker"].as_s.should eq("kept")
        result["alert"].as_s.should eq("Name is too short")
        result["value"].as_s.should eq("A")
        result["focused"].as_s.should eq("save")
        result["slot"].as_s.should eq("Load")
        result["busy"].as_bool.should be_false
        result["path"].as_s.should eq("/phase4/browser")
        BrowserRoutes::RECEIVED.should eq(["POST /phase4/browser/form box"])
      end
    end

    it "loads the new page after a redirect" do
      on_page do |browser, _|
        run_js(browser, <<-JS)
          document.getElementById("name").value = "Ada";
          document.getElementById("save").click();
          JS
        browser.wait_for("Page.loadEventFired")
        browser.evaluate("location.pathname").as_s.should eq("/phase4/browser/plain")
        browser.evaluate("document.title").as_s.should eq("Plain")
        BrowserRoutes::RECEIVED.first.should eq("POST /phase4/browser/form box")
      end
    end

    it "shows a response without the element as the whole page after a POST" do
      on_page do |browser, _|
        result = run_js(browser, <<-JS)
          const done = waitFor(() => document.title === "Conflict" ? true : undefined);
          document.getElementById("clash").click();
          await done;
          return {path: location.pathname, text: document.body.textContent, slots: document.querySelectorAll("#slot").length};
          JS
        result["path"].as_s.should eq("/phase4/browser")
        result["text"].as_s.should contain(Shomen::Server::CONFLICT_DETAIL)
        result["slots"].as_i.should eq(0)
      end
    end

    it "loads the URL when a GET response lacks the element" do
      on_page do |browser, _|
        run_js(browser, %(document.getElementById("plain").click();))
        browser.wait_for("Page.loadEventFired")
        browser.evaluate("location.pathname").as_s.should eq("/phase4/browser/plain")
        BrowserRoutes::RECEIVED.should eq(["GET /phase4/browser/plain slot", "GET /phase4/browser/plain -"])
      end
    end

    it "leaves cross-origin, modified, and new-window clicks to the browser" do
      on_page do |browser, origin|
        far = origin.sub("127.0.0.1", "localhost")
        result = run_js(browser, <<-JS)
          const prevented = (element, init) => {
            let seen = null;
            window.addEventListener("click", (event) => { seen = event.defaultPrevented; event.preventDefault(); }, {once: true});
            element.dispatchEvent(new MouseEvent("click", {bubbles: true, cancelable: true, ...init}));
            return seen;
          };
          const farLink = document.createElement("a");
          farLink.href = "#{far}/phase4/browser/slot";
          farLink.setAttribute("data-shomen-get", "slot");
          farLink.textContent = "Far";
          document.body.append(farLink);
          const load = document.getElementById("load");
          const blank = load.cloneNode(true);
          blank.id = "blank";
          blank.target = "_blank";
          document.body.append(blank);
          return [
            prevented(farLink, {}),
            prevented(load, {ctrlKey: true}),
            prevented(load, {metaKey: true}),
            prevented(load, {button: 1}),
            prevented(blank, {}),
          ];
          JS
        result.as_a.map(&.as_bool).should eq([false, false, false, false, false])
        BrowserRoutes::RECEIVED.should be_empty
      end
    end

    it "sends one request when a form is submitted twice before the answer" do
      on_page do |browser, _|
        result = run_js(browser, <<-JS)
          document.getElementById("name").value = "A";
          const form = document.getElementById("box-form");
          const done = waitFor(() => document.querySelector("#box [role=alert]") ? true : undefined);
          form.requestSubmit();
          form.requestSubmit();
          await done;
          return document.querySelectorAll("#box [role=alert]").length;
          JS
        result.as_i.should eq(1)
        BrowserRoutes::RECEIVED.should eq(["POST /phase4/browser/form box"])
      end
    end
  else
    pending("runs in Chrome (set SHOMEN_CHROME to a Chrome or Chromium binary)") { }
  end
end
```

- [ ] **Step 3: 失敗を確かめる**

Run: `crystal spec spec/shomen/script_spec.cr`
Expected: 7 examples のうち、"leaves cross-origin, modified, and new-window clicks to the browser" 以外が失敗する（骨組みの `shomen.js` は何もしないので、リンクとフォームが普通に移動し、`Browser` の 20 秒の上限か値の不一致で落ちる）。

- [ ] **Step 4: shomen.js を書く**

`src/shomen/assets/shomen.js` を次にする:

```js
// shomen.js: the official JavaScript of Shomen. No build step and no
// dependencies. A link with data-shomen-get or a post form with
// data-shomen-post names the id of an element, and the response replaces
// that element. Without this file the same link and form load a page.
(() => {
  "use strict";

  const TARGET_HEADER = "Shomen-Target";

  const sameOrigin = (url) => url.origin === location.origin;

  // An element of the same id in the response replaces the target. A
  // redirect loads its page. Otherwise a GET loads the URL, and a POST,
  // which must not be sent twice, shows the response as the page.
  const load = async (target, url, init) => {
    const active = document.activeElement;
    const focused = active && target.contains(active) ? active.id : "";
    target.setAttribute("aria-busy", "true");
    try {
      let response;
      try {
        response = await fetch(url, { ...init, headers: { [TARGET_HEADER]: target.id } });
      } catch (error) {
        if (init.method === "GET") location.assign(url);
        throw error;
      }
      if (response.redirected) {
        location.assign(response.url);
        return;
      }
      const html = await response.text();
      const template = document.createElement("template");
      template.innerHTML = html;
      const next = template.content.getElementById(target.id);
      if (next) {
        target.replaceWith(next);
        if (focused) document.getElementById(focused)?.focus();
      } else if (init.method === "GET") {
        location.assign(url);
      } else {
        const page = new DOMParser().parseFromString(html, "text/html");
        document.documentElement.replaceWith(page.documentElement);
      }
    } finally {
      target.removeAttribute("aria-busy");
    }
  };

  // Returns the element to replace, or null to leave the event alone.
  const targetOf = (event, element, name) => {
    const target = document.getElementById(element.getAttribute(name));
    if (!target) return null;
    event.preventDefault();
    return target.getAttribute("aria-busy") === "true" ? null : target;
  };

  document.addEventListener("click", (event) => {
    if (event.defaultPrevented || event.button !== 0) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    if (!(event.target instanceof Element)) return;
    const link = event.target.closest("a[href][data-shomen-get]");
    if (!link || link.hasAttribute("download")) return;
    const frame = link.getAttribute("target");
    if (frame && frame !== "_self") return;
    const url = new URL(link.href);
    if (!sameOrigin(url)) return;
    const target = targetOf(event, link, "data-shomen-get");
    if (target) load(target, url, { method: "GET" });
  });

  document.addEventListener("submit", (event) => {
    const form = event.target;
    if (event.defaultPrevented || !(form instanceof HTMLFormElement)) return;
    if (!form.hasAttribute("data-shomen-post")) return;
    if ((form.getAttribute("method") || "get").toLowerCase() !== "post") return;
    const enctype = (form.getAttribute("enctype") || "application/x-www-form-urlencoded").toLowerCase();
    if (enctype !== "application/x-www-form-urlencoded") return;
    const frame = form.getAttribute("target");
    if (frame && frame !== "_self") return;
    const submitter = event.submitter;
    const overrides = ["formaction", "formmethod", "formenctype", "formtarget"];
    if (submitter && overrides.some((name) => submitter.hasAttribute(name))) return;
    const url = new URL(form.getAttribute("action") || "", document.baseURI);
    if (!sameOrigin(url)) return;
    const target = targetOf(event, form, "data-shomen-post");
    if (!target) return;
    const body = new URLSearchParams(new FormData(form, submitter));
    load(target, url, { method: "POST", body });
  });
})();
```

- [ ] **Step 5: 通ることを確かめる**

Run: `crystal spec spec/shomen/script_spec.cr spec/shomen/island_spec.cr`
Expected: 11 examples, 0 failures, 0 pending。

Run: `wc -c src/shomen/assets/shomen.js`
Expected: 10240 未満（目安は 4,000 前後）。

Run: `crystal spec && crystal tool format --check && crystal build src/shomen.cr --error-trace && rm -f shomen`
Expected: 0 failures、0 pending、書式の差分なし、警告なし。

---

### Task 7: examples/hello の Greeting

**Files:**
- Modify: `examples/hello/src/hello.cr`（`module Greeting` の中）
- Test: `examples/hello/spec/greeting_fetch_spec.cr`
- 変えない: `examples/hello/spec/greeting_spec.cr`（JS 無しの受入としてそのまま通す）

**Interfaces:**
- Consumes: `Shomen::Fragment`、`embed`、`render_fragment`、`target`、`shomen_script`
- Produces: `Greeting::FormView < Shomen::Fragment`（`#initialize(name : String, token : String, error : String?)`）、`Greeting::EditView#initialize(form : FormView)`

- [ ] **Step 1: 失敗する spec を書く**

`examples/hello/spec/greeting_fetch_spec.cr`:

```crystal
require "./spec_helper"
require "http/client"

private def request_with(server : Shomen::Server, method : String, path : String, target : String? = nil, cookie : String? = nil, body : String? = nil) : HTTP::Client::Response
  headers = HTTP::Headers.new
  headers["Shomen-Target"] = target if target
  headers["Cookie"] = cookie if cookie
  headers["Content-Type"] = "application/x-www-form-urlencoded" if body
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  server.call(HTTP::Server::Context.new(HTTP::Request.new(method, path, headers, body), response))
  response.close
  HTTP::Client::Response.from_io(IO::Memory.new(io.to_s))
end

private def open_page(server : Shomen::Server) : {String, String}
  response = request_with(server, "GET", "/greeting")
  cookie = response.headers["Set-Cookie"].split(';').first
  token = response.body.match(/name="_csrf" value="([^"]+)"/).not_nil![1]
  {cookie, token}
end

describe "Greeting with shomen.js" do
  it "loads the script and marks the change link" do
    response = request_with(Shomen::Server.new, "GET", "/greeting/Ada")
    response.body.should contain("<script src=\"/shomen.js\" defer></script>")
    response.body.should contain("<div id=\"greeting-form\"><a href=\"/greeting\" data-shomen-get=\"greeting-form\">Change</a></div>")
  end

  it "wraps the form of the page in the element the script replaces" do
    response = request_with(Shomen::Server.new, "GET", "/greeting")
    response.body.should start_with("<!DOCTYPE html>")
    response.body.should contain("<script src=\"/shomen.js\" defer></script>")
    response.body.should contain("<h1>Greeting</h1><div id=\"greeting-form\"><form action=\"/greeting\" method=\"post\" data-shomen-post=\"greeting-form\">")
  end

  it "answers the change link with only the form" do
    response = request_with(Shomen::Server.new, "GET", "/greeting", target: "greeting-form")
    response.status_code.should eq(200)
    response.body.should start_with("<div id=\"greeting-form\"><form action=\"/greeting\" method=\"post\" data-shomen-post=\"greeting-form\">")
    response.body.should contain("<button type=\"submit\" id=\"greeting-save\">Save</button>")
    response.body.should_not contain("<html")
  end

  it "redisplays only the form with 422" do
    server = Shomen::Server.new
    cookie, token = open_page(server)
    body = URI::Params.encode({"_csrf" => token, "name" => "<"})
    response = request_with(server, "POST", "/greeting", "greeting-form", cookie, body)
    response.status_code.should eq(422)
    response.body.should start_with("<div id=\"greeting-form\"><p role=\"alert\">Name must be at least 2 characters</p>")
    response.body.should contain("value=\"&lt;\"")
    response.body.should_not contain("<html")
  end

  it "redirects a valid name with or without the script" do
    server = Shomen::Server.new
    cookie, token = open_page(server)
    body = URI::Params.encode({"_csrf" => token, "name" => "Ada"})
    response = request_with(server, "POST", "/greeting", "greeting-form", cookie, body)
    response.status_code.should eq(303)
    response.headers["Location"].should eq("/greeting/Ada")
  end

  it "serves shomen.js" do
    response = request_with(Shomen::Server.new, "GET", "/shomen.js")
    response.status_code.should eq(200)
    response.headers["Content-Type"].should eq("text/javascript; charset=utf-8")
  end
end
```

- [ ] **Step 2: 失敗を確かめる**

Run: `cd examples/hello && shards install && crystal spec spec/greeting_fetch_spec.cr`
Expected: "serves shomen.js" 以外が失敗する（`<script` が無い、断片でなく文書が返る）。

- [ ] **Step 3: Greeting を書き換える**

`examples/hello/src/hello.cr` の `module Greeting` の中の `EditView`、`ShowView`、`Edit`、`Update` を次にする（`Show` はそのまま）:

```crystal
module Greeting
  class FormView < Shomen::Fragment
    def initialize(@name : String, @token : String, @error : String?)
    end

    def content : Nil
      name = @name
      token = @token
      error = @error
      div(id: "greeting-form") do
        if message = error
          p message, role: "alert"
        end
        form(action: Greeting::Update.path, method: "post", "data-shomen-post": "greeting-form") do
          csrf_field(token)
          label("Name", for: "name")
          input(id: "name", name: "name", type: "text", value: name)
          button "Save", type: "submit", id: "greeting-save"
        end
      end
    end
  end

  class EditView < Shomen::View
    def initialize(@form : FormView)
    end

    def to_html : String
      form_view = @form
      html lang: "en" do
        head do
          title "Greeting"
          shomen_script
        end
        body do
          main do
            h1 "Greeting"
            embed form_view
          end
        end
      end
    end
  end

  class ShowView < Shomen::View
    def initialize(@name : String)
    end

    def to_html : String
      name = @name
      html lang: "en" do
        head do
          title "Greeting"
          shomen_script
        end
        body do
          main do
            h1 "Hello, #{name}"
            div(id: "greeting-form") do
              a "Change", href: Greeting::Edit.path, "data-shomen-get": "greeting-form"
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
      form_view = FormView.new("", csrf_token, nil)
      return render_fragment(form_view) if target
      render EditView.new(form_view)
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
      name = input.name.strip
      return redisplay(input.name, "Name must be at least 2 characters") if name.size < 2
      # The path helper refuses these characters in a path parameter.
      if name.includes?('/') || name.includes?('?') || name.includes?('#')
        return redisplay(input.name, "Name must not contain /, ?, or #")
      end
      # The path helper refuses .. too, since a browser resolves /greeting/.. to /.
      return redisplay(input.name, "Name must not be ..") if name == ".."
      redirect Show.path(name: name)
    end

    private def redisplay(name : String, error : String) : Shomen::Response
      form_view = FormView.new(name, csrf_token, error)
      return render_fragment(form_view, status: 422) if target
      render EditView.new(form_view), status: 422
    end
  end
```

- [ ] **Step 4: 通ることを確かめる**

Run: `cd examples/hello && crystal spec`
Expected: 0 failures。`greeting_spec.cr`（JS 無しのフェーズ 2 の受入）も変更なしで通る。

- [ ] **Step 5: 手でブラウザを確かめる**

Run: `cd examples/hello && HELLO_DATABASE_URL=sqlite3://$(mktemp -d)/hello.sqlite3 crystal run src/hello.cr`

Chrome で `http://127.0.0.1:3000/greeting/Ada` を開き、次を確かめる（Playwright MCP で操作してよい）:

1. 「Change」を押すと、URL と見出し「Hello, Ada」はそのままで、リンクの場所にフォームが出る
2. 「A」で保存すると、フォームだけが 422 のエラー付きで差し替わり、フォーカスが保存ボタンに残る
3. 「Bob」で保存すると、`/greeting/Bob` のページに移る
4. DevTools で JavaScript を無効にして 1〜3 をやり直すと、「Change」は `/greeting` のページに移り、エラーは文書全体の再表示になり、「Bob」は `/greeting/Bob` に移る

確かめたらサーバを止める。

Run: `cd examples/hello && crystal tool format --check`
Expected: 書式の差分なし。

---

### Task 8: README、CONTRIBUTING、最終確認

**Files:**
- Modify: `README.md:7`、`README.md:9-15`（Requirements）、`README.md:77`、`README.md:105`（「Phase 3 adds these」の後）
- Modify: `README.ja.md` の対応する箇所（7 行目、「必要なもの」、77 行目、97〜105 行目）
- Modify: `CONTRIBUTING.md:47`、`CONTRIBUTING.ja.md:46`

**Interfaces:**
- Consumes: Task 2〜7 の公開 API の名前
- Produces: 文書だけ。コードは変えない

- [ ] **Step 1: README.md を直す**

7 行目を次にする:

```markdown
Version 0.0.0. Phases 1 to 4 are in the tree: typed routes, a typed HTML DSL, an HTTP server, form binding, a signed session cookie, CSRF protection, commands and events, an append-only SQLite event store, in-memory projections, HTML fragments, the official `shomen.js`, and JSON responses. Later phases are specified and not implemented. There is no release tag yet.
```

Requirements の箇条書きの末尾に足す:

```markdown
- Google Chrome or Chromium, only to run the `shomen.js` specs. Without it they are pending. `SHOMEN_CHROME` names the binary
```

「## Phases 1 to 3 are what run」を「## Phases 1 to 4 are what run」にし、「Phase 3 adds these:」の箇条書きの後に足す:

```markdown
Phase 4 adds these:

- `Shomen::Fragment`: a view of one element. It implements `content`, and writing `html` in it fails at compile time. A document view puts it in with `embed`
- `render_fragment(fragment)`: sends the fragment alone. `render` with a fragment fails at compile time
- `shomen.js`, served at `/shomen.js`. `shomen_script` writes its `script` element. `<a href="..." data-shomen-get="ID">` and `<form method="post" action="..." data-shomen-post="ID">` fetch with the `Shomen-Target: ID` header and replace the element with that id. A redirect loads the new page. Without JavaScript the same link and form load pages as before
- `target`: the id from `Shomen-Target`, or `nil`. A route answers `target ? render_fragment(...) : render(...)`. Every response has `Vary: Shomen-Target`
- `json(value, status = 200)`: `application/json`. The server never chooses JSON on its own, and errors stay HTML documents
- In `examples/hello`, the greeting form is a fragment: "Change" opens it in place, and a 422 replaces only the form
```

「These are specified for later phases …」の行を次にする:

```markdown
These are specified for later phases and are not in the code: SSE, islands, Postgres, and running many identical processes on one database.
```

- [ ] **Step 2: README.ja.md を同じ内容で直す**

7 行目:

```markdown
バージョンは 0.0.0 です。リポジトリに入っているのはフェーズ 4 までで、型付きルート、型付き HTML、HTTP サーバ、フォームの束縛、署名付きセッション Cookie、CSRF 対策、コマンドとイベント、追記のみの SQLite イベントストア、メモリ上のプロジェクション、HTML 断片、公式の `shomen.js`、JSON 応答が動きます。それより後のフェーズは仕様にあり、実装はまだありません。リリースタグもまだありません。
```

「必要なもの」の箇条書きの末尾に足す:

```markdown
- Google Chrome か Chromium（`shomen.js` の spec を走らせるときだけ。無ければその spec は pending になります。`SHOMEN_CHROME` で実行ファイルを指定できます）
```

「## いま動くのはフェーズ 1 から 3」を「## いま動くのはフェーズ 1 から 4」にし、「フェーズ 3 で足したもの:」の箇条書きの後に足す:

```markdown
フェーズ 4 で足したもの:

- `Shomen::Fragment`: 要素 1 つのビュー。`content` を実装します。中で `html` を書くとコンパイルエラーです。文書ビューには `embed` で埋め込みます
- `render_fragment(fragment)`: 断片だけを返します。`render` に断片を渡すとコンパイルエラーです
- `/shomen.js` で配る `shomen.js`。`script` 要素は `shomen_script` が書きます。`<a href="..." data-shomen-get="ID">` と `<form method="post" action="..." data-shomen-post="ID">` は `Shomen-Target: ID` ヘッダを付けて fetch し、その `id` の要素を差し替えます。リダイレクトは新しいページを読み込みます。JavaScript が無ければ、同じリンクとフォームが今までどおりページを読み込みます
- `target`: `Shomen-Target` の `id`、無ければ `nil`。ルートは `target ? render_fragment(...) : render(...)` で答えます。すべての応答に `Vary: Shomen-Target` が付きます
- `json(value, status = 200)`: `application/json` を返します。サーバが自分で JSON を選ぶことはなく、エラーは HTML 文書のままです
- `examples/hello` の挨拶フォームは断片です。「Change」でその場にフォームが開き、422 ではフォームだけが差し替わります
```

105 行目:

```markdown
SSE、島、Postgres、1 つの DB の上で同じプロセスを多数動かすことは、後のフェーズの仕様であり、コードにはありません。
```

- [ ] **Step 3: CONTRIBUTING を直す**

`CONTRIBUTING.md` の「Specs call the handler directly or build a fixture. They do not bind a fixed public port.」を次にする:

```markdown
Specs call the handler directly or build a fixture. They do not bind a fixed public port. The `shomen.js` specs serve on an ephemeral port on 127.0.0.1 and drive a headless Chrome. Without Chrome they are pending; `SHOMEN_CHROME` names the binary.
```

`CONTRIBUTING.ja.md` の「spec はハンドラを直接呼ぶか、フィクスチャをビルドします。固定の公開ポートは取りません。」を次にする:

```markdown
spec はハンドラを直接呼ぶか、フィクスチャをビルドします。固定の公開ポートは取りません。`shomen.js` の spec は 127.0.0.1 の一時ポートで待ち受け、ヘッドレスの Chrome を動かします。Chrome が無ければ pending になります。`SHOMEN_CHROME` で実行ファイルを指定できます。
```

- [ ] **Step 4: 受入を 1 つずつ確かめる**

Run: `crystal spec && crystal tool format --check && crystal build src/shomen.cr --error-trace && rm -f shomen && (cd examples/hello && shards install && crystal spec && crystal tool format --check) && git status --short && pgrep -f shomen-chrome`
Expected: 0 failures、0 pending、警告なし、`git status` に `shomen` や `var/`、`.sqlite3` のファイルが無い、`pgrep` が何も出さない（Chrome が残っていない）。

受入との対応:

| 受入 | 確かめる spec |
|---|---|
| JS 無効でもフェーズ 2 のフォームは動く | `examples/hello/spec/greeting_spec.cr`（変更なし）、`greeting_fetch_spec.cr` の "wraps the form…"、"redirects a valid name…"、Task 7 Step 5 の 4 |
| JS 有効では、指定要素だけが差し替わる | `script_spec.cr` の "replaces only the element named by data-shomen-get"、"replaces only the form on 422…"、Task 7 Step 5 の 1〜2 |
| 公式 JS に npm 依存が無い | `island_spec.cr` の "has no npm dependency and stays under 10 KB" |
| `render_fragment` | `fragment_spec.cr`、`fragment_request_spec.cr` |
| JSON はルートが明示したときだけ | `json_spec.cr` |

- [ ] **Step 5: 停止する**

フェーズ 4 の受入を満たしたら、AGENTS.md と `docs/en/02-PHASES.md` のとおり停止し、ユーザーの次の指示を待つ。commit はユーザーが頼んだときだけ行う。
