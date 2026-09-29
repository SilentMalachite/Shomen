# Phase 5 SSE and Islands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** フェーズ 5 の受入まで届ける。オプトインの SSE（`sse(store) { 断片 }` と `data-shomen-sse`）、`data-shomen-island` の島、島の例（カウンター）。

**Architecture:** Store は実パスごとにプロセスで 1 つの `Shomen::AppendSignal` を持ち、`COMMIT` の後に最後の `id` を知らせる（D2）。ルートは `sse(store) { Fragment }` で `Shomen::SSE < Shomen::Response` を返す。最初の描画はルートの中で行い、サーバはヘッダの後で `SSE#run` にストリームを書かせる。`run` はこのプロセスの追記で起き、描き直した HTML が前回と違うときだけ 1 メッセージ送り、何も書かない時間がハートビートを超えたらコメントを書く。書き込みの失敗（`HTTP::Server::ClientError`）でストリームを終える（D1）。`shomen.js` は `data-shomen-sse` の要素（ホルダー）ごとに `EventSource` を開き、断片の根と同じ `id` の要素をホルダーの中でだけ置き換える。置き換えはフェーズ 4 の fetch と同じ関数で行い、入れた要素を「落ち着かせる」（外れたホルダーを閉じ、入ったホルダーと島を動かす）（D3）。島のモジュールはアプリのファイルで、`Shomen::Island.script "name", "file.js"` がコンパイル時に読んで `/islands/name.js` のルートにする。`shomen.js` は `import()` して `default(element)` を 1 回呼ぶ（D4）。受入「島の外にリスナーを撒かない」は、CDP でページのスクリプトより先に `addEventListener` と `EventSource` を包み、ブラウザ spec で確かめる。サーバ側の SSE は `IO.pipe` 越しに読む（D5）。

**Tech Stack:** Crystal `>= 1.20.0`（開発機は 1.21.1）、標準ライブラリの `spec`、`http/server`、`http/web_socket`、`json`、`yaml`。外部 shard は増やさない（`sqlite3` と `db` のまま）。JavaScript は素の ES2020 と `EventSource`、動的 `import()`。npm なし、ビルドなし。ブラウザ spec は開発機の Google Chrome を使う。

**Spec:** `docs/en/00-INSTRUCTION.md` の「1. Package layout」「4. Responses」「8. Fragment updates and islands」「10. Scale out」（フェーズ 7 の通知が SSE を起こす）、`docs/en/01-ARCHITECTURE.md` の「Where state lives」「Module boundaries」「Official JavaScript」、`docs/en/02-PHASES.md` のフェーズ 5、`docs/en/03-CONVENTIONS.md`、`docs/decisions/20260929-scale-notify.md`（フェーズ 5 の SSE は 1 プロセスの中の変更だけを配る）、`docs/decisions/20260929-phase4-*.md`。細部は次の決定ファイルに従う。この計画の Task 1 で足すもの:

- `docs/decisions/20260929-phase5-sse-response.md`（D1）
- `docs/decisions/20260929-phase5-append-signal.md`（D2）
- `docs/decisions/20260929-phase5-sse-script.md`（D3）
- `docs/decisions/20260929-phase5-island-script.md`（D4）
- `docs/decisions/20260929-phase5-listener-spec.md`（D5）
- `docs/decisions/20260929-phase5-counter-example.md`（D6）

D1 はユーザーが選んだ案（2026-09-29 の計画時の質問: SSE は「追記で断片を再描画」）。

## Global Constraints

- 言語は Crystal 1.20 以上。`shard.yml` の下限は `>= 1.20.0` のまま。依存 shard を足さない（仕様 1、受入「SSE を使わないアプリに依存が増えない」）。
- 公式 JavaScript は `src/shomen/assets/shomen.js` の 1 ファイル。npm パッケージ、`package.json`、静的な `import` / `export`、`require(`、ビルド手順を持たない。動的な `import(` は島のモジュールを読む 1 か所だけ。10,240 バイト未満。
- `shomen.js` が読む独自属性は `data-shomen-*` だけ。`dataset` を使わない。コメントにも `import`、`export` という語を書かない（Task 7 の spec が文字列で検査する）。
- `shomen.js` が付けるリスナーは `document` の `click` と `submit`、`window` の `pageshow`、各 `EventSource` の `message` だけ。要素には付けない。`on*` プロパティにハンドラを入れない。
- SSE は `sse` を呼んだルートだけが開く。フレームワークは SSE のルートを登録しない。WebSocket を作らない。
- SSE のストリームを起こすのは、このプロセスの追記だけ。他のプロセスの追記、ポーリング、Postgres の `NOTIFY` はフェーズ 7。
- モジュール境界: Store と AppendSignal は HTML を知らない。SSE、Command、Event、Projection は SQLite を名指ししない。HTML（`view.cr`、`a11y.cr`、`fragment.cr`）は Server、Island、SSE を知らない。
- 公開 API は `Shomen::` 配下だけ。1 ファイル 1 主要型。ファイル名は機能名。
- CSP、Postgres、グレースフルシャットダウン、`ETag`、断片キャッシュ、コンシューマを作らない（フェーズ 6 以降）。
- 色コード、デザイントークン、国際化の仕組みを作らない。
- コードと識別子は英語。この計画と決定ログは日本語。
- ユーザーが指示するまで commit しない。この計画に commit 手順は無い。
- `crystal tool format` を通し、警告を残して完了にしない。
- テストは固定ポートを bind しない。ブラウザ spec だけが `127.0.0.1` の一時ポートを使う。SSE のサーバ側 spec はポートを使わず `IO.pipe` で読む。sleep で同期しない。待ちは Channel、`MutationObserver`、DevTools のイベントで行い、上限（5 秒、20 秒）は失敗の検出だけに使う。spec のルートのハートビート 50 ms はコードの引数で、同期には使わない。ポート 3000 を使うのは Task 9 の手動確認だけ。
- 検証でリポジトリルートにできる実行ファイル `shomen` は `docs/decisions/20260928-build-artifact.md` のとおり削除する。

実行はリポジトリルートで行う。`Shomen::VERSION` は `"0.0.0"` のまま変えない。

## Review Focus

- 去ったクライアント。ブラウザを閉じた、タブを移った、`EventSource` を閉じた。サーバはそのストリームを終え、要求のファイバーと待ち手を残さない。Task 3 の "ends when the client leaves" と Task 2 の "returns false after the limit and forgets the waiter" で固定する。
- 改行を含む断片。利用者の名前に `\n`、`\r\n`、`\r`、`\n\nevent: x` が入っている。メッセージは途中で切れず、別のフィールドも作らない。ブラウザは元の HTML を受け取る。Task 3 の "puts every line of the HTML in its own data line" で固定する。
- 描画と待ちの間の追記。ストリームが断片を描いた直後、待ちに入る前に別の要求が追記する。その変化は次のメッセージで届き、次の追記まで遅れない。Task 3 の "does not lose an append made while the fragment renders" で固定する。
- fetch でホルダーを差し替える。`data-shomen-sse` の要素を含む部分を `data-shomen-get` で差し替える。古いストリームは閉じ、新しいホルダーのストリームが開いて更新を受ける。Task 6 の "closes the stream of a holder a replacement removed and follows the new one" で固定する。
- 置き換えで入った島。fetch や SSE で島を含む断片が入る。その島は 1 回だけ動き、前からある島は動かし直さない（クリック 1 回で 1 増える）。Task 7 の "runs the module of an island a replacement brings, once" と "adds no event listener outside an island" で固定する。

## File Map

| ファイル | 役割 | Task |
|---|---|---|
| `docs/en/02-PHASES.md`、`docs/02-PHASES.md` | 現行フェーズをフェーズ 5 にする（Task 1）、受入済みにする（Task 9） | 1, 9 |
| `docs/en/00-INSTRUCTION.md`、`docs/00-INSTRUCTION.md` | 仕様 1 に `sse.cr`、仕様 4 に `sse`、仕様 8 に SSE と島の仕組み | 1 |
| `docs/en/01-ARCHITECTURE.md`、`docs/01-ARCHITECTURE.md` | モジュール境界に `Shomen::SSE`、Store と Island の責務、公式 JS に島のモジュール | 1 |
| `docs/decisions/20260929-phase5-*.md` | D1〜D6 | 1 |
| `src/shomen/append_signal.cr` | `Shomen::AppendSignal` | 2 |
| `src/shomen/store.cr` | `last_appended`、`wait_for_append`、`COMMIT` 後の知らせ | 2 |
| `src/shomen/sse.cr` | `Shomen::SSE` | 3 |
| `src/shomen/route.cr` | `sse` | 3 |
| `src/shomen/server.cr` | SSE の応答を書く | 3 |
| `src/shomen/island.cr` | `CONTENT_TYPE`、`Shomen::Island.script` | 4 |
| `src/shomen/assets/shomen.js` | SSE（Task 6）、島（Task 7） | 6, 7 |
| `src/shomen.cr` | `append_signal` と `sse` の require | 2, 3 |
| `spec/spec_helper.cr` | 新しい support の require | 3, 4, 6 |
| `spec/support/sse_client.cr` | `SSEClient`、`with_sse_client` | 3 |
| `spec/support/sse_routes.cr` | SSE のルート（Task 3）、SSE のページ（Task 6） | 3, 6 |
| `spec/support/island_routes.cr`、`spec/support/islands/counter.js` | 島の宣言（Task 4）、島のページ（Task 7） | 4, 7 |
| `spec/support/browser.cr` | `Browser#before_load`、`Browser#run` | 5 |
| `spec/support/page_spy.cr` | `PAGE_SPY` | 6 |
| `spec/fixtures/island_bad_name.cr`、`spec/fixtures/island_missing_file.cr` | コンパイル失敗のフィクスチャ | 4 |
| `spec/shomen/append_signal_spec.cr`、`spec/shomen/store_spec.cr` | Task 2 | 2 |
| `spec/shomen/sse_spec.cr`、`spec/shomen/boundary_spec.cr` | Task 3 | 3 |
| `spec/shomen/island_spec.cr` | 島のルート（Task 4）、`shomen.js` の静的検査（Task 7） | 4, 7 |
| `spec/shomen/browser_spec.cr` | Task 5 | 5 |
| `spec/shomen/sse_script_spec.cr` | Task 6 | 6 |
| `spec/shomen/island_script_spec.cr` | Task 7 | 7 |
| `examples/hello/src/counter.cr`、`examples/hello/src/counter.js`、`examples/hello/src/hello.cr` | カウンターの島 | 8 |
| `examples/hello/spec/counter_spec.cr` | 例での受入 | 8 |
| `README.md`、`README.ja.md`、`CONTRIBUTING.md`、`CONTRIBUTING.ja.md` | フェーズ 5 の反映 | 9 |

---

### Task 1: 現行フェーズ、仕様、決定ファイル

**Files:**
- Modify: `docs/en/02-PHASES.md:5-9`、`docs/02-PHASES.md:5-9`
- Modify: `docs/en/00-INSTRUCTION.md:65`、`:157`、`:235`、`:237`
- Modify: `docs/00-INSTRUCTION.md:65`、`:157`、`:235`、`:237`
- Modify: `docs/en/01-ARCHITECTURE.md:40`、`:43`、`:91`
- Modify: `docs/01-ARCHITECTURE.md:40`、`:43`、`:91`
- Create: `docs/decisions/20260929-phase5-sse-response.md`
- Create: `docs/decisions/20260929-phase5-append-signal.md`
- Create: `docs/decisions/20260929-phase5-sse-script.md`
- Create: `docs/decisions/20260929-phase5-island-script.md`
- Create: `docs/decisions/20260929-phase5-listener-spec.md`
- Create: `docs/decisions/20260929-phase5-counter-example.md`

**Interfaces:**
- Consumes: なし
- Produces: 後続タスクが従う決定 D1〜D6。ここで決めた名前（`Shomen::AppendSignal`、`announce`、`wait(after:, within:)`、`last`、`waiting`、`Shomen::Store#last_appended`、`Shomen::Store#wait_for_append(after:, within:)`、`Shomen::SSE`、`Shomen::SSE::HEARTBEAT`、`Shomen::SSE.message`、`Shomen::SSE#run`、`Shomen::Route#sse`、`Shomen::Island::CONTENT_TYPE`、`Shomen::Island.script`、`<Name>Island`、`/islands/<name>.js`、`data-shomen-sse`、`Browser#before_load`、`Browser#run`、`PAGE_SPY`、`SSEClient`）は Task 2〜8 のコードと一致させる。

- [ ] **Step 1: 現行フェーズを書き換える（英語）**

`docs/en/02-PHASES.md` の「## Current phase」の本文を次にする。

```markdown
## Current phase

**Phase 5 — SSE and islands**

Phase 4 acceptance is met. Do not implement past this point (phase 6 and later). When phase 5 acceptance is met, stop and wait for the next instruction.
```

- [ ] **Step 2: 現行フェーズを書き換える（日本語訳）**

`docs/02-PHASES.md` の「## 現行フェーズ」の本文を次にする。見出しの表記は同じファイルの「## フェーズ 5 — SSE と島」に合わせる。

```markdown
## 現行フェーズ

**フェーズ 5 — SSE と島**

フェーズ 4 の受入は満たした。ここより先（フェーズ 6 以降）を実装しない。5 の受入を満たしたら停止し、ユーザーの次指示を待つ。
```

- [ ] **Step 3: 仕様 1、4、8 を直す（英語）**

`docs/en/00-INSTRUCTION.md` の「### 1. Package layout」で、`  response.cr` の次の行に足す（`#` の列は `consumer.cr` の行に揃える）:

```
  sse.cr                      # phase 5
```

「### 4. Responses」の Helpers で、`json` の行の次に足す:

```markdown
- `sse(store, heartbeat = 15.seconds) { fragment }` returns an event stream (`text/event-stream`). It renders the fragment now and again after each append to `store` in this process, and sends its HTML whenever it changed. Appends in other processes reach it in phase 7 (`docs/decisions/20260929-phase5-sse-response.md`)
```

「### 8. Fragment updates and islands (phases 4–5)」の 235 行目と 237 行目を次にする:

```markdown
- The default transport is `fetch`. SSE is opt-in: a GET route answers with `sse`, and an element with `data-shomen-sse="URL"` receives its fragments. Each fragment replaces the element with the same `id` inside that element (phase 5, `docs/decisions/20260929-phase5-sse-script.md`)
```

```markdown
- An island loads JavaScript only on an element with `data-shomen-island="name"`. `Shomen::Island.script "name", "file.js"` serves the application's module at `/islands/name.js`, and `shomen.js` calls its default export with the element (phase 5, `docs/decisions/20260929-phase5-island-script.md`)
```

- [ ] **Step 4: 仕様 1、4、8 を直す（日本語訳）**

`docs/00-INSTRUCTION.md` の「### 1. パッケージ構成」で、`  response.cr` の次の行に足す:

```
  sse.cr                      # フェーズ 5
```

「### 4. レスポンス」の「ヘルパ:」で、`json` の行の次に足す:

```markdown
- `sse(store, heartbeat = 15.seconds) { 断片 }` → イベントストリーム（`text/event-stream`）。断片を今描き、このプロセスで `store` に追記があるたびに描き直し、HTML が変わったときだけ送る。他のプロセスの追記が届くのはフェーズ 7（`docs/decisions/20260929-phase5-sse-response.md`）
```

「### 8. 断片更新と島（フェーズ 4–5）」の 235 行目と 237 行目を次にする:

```markdown
- 既定の輸送は `fetch`。SSE はオプトイン: GET のルートが `sse` で答え、`data-shomen-sse="URL"` の要素がその断片を受け取る。断片は、その要素の中の同じ `id` の要素を置き換える（フェーズ 5、`docs/decisions/20260929-phase5-sse-script.md`）
```

```markdown
- 島は `data-shomen-island="name"` の要素にだけ JS を載せる。`Shomen::Island.script "name", "file.js"` がアプリのモジュールを `/islands/name.js` で配り、`shomen.js` がその要素を渡して既定のエクスポートを呼ぶ（フェーズ 5、`docs/decisions/20260929-phase5-island-script.md`）
```

- [ ] **Step 5: アーキテクチャを直す（英語と日本語訳）**

`docs/en/01-ARCHITECTURE.md`:

- 40 行目を `| `Shomen::Store` | Append and read, and wake what waits for an append in this process | Event |` にする
- 43 行目を `| `Shomen::Island` | Serve the official JavaScript and island modules | Route |` にし、その次の行に `| `Shomen::SSE` | Send a fragment again after each append in this process | Response, Store, Fragment |` を足す
- 「## Official JavaScript」の本文（91 行目）の後に、空行を挟んで次の段落を足す:

```markdown
An island module is a file of the application. `Shomen::Island.script` reads it at compile time and serves it at `/islands/<name>.js`. `shomen.js` loads it only for an element with `data-shomen-island` (`docs/decisions/20260929-phase5-island-script.md`).
```

`docs/01-ARCHITECTURE.md`:

- 40 行目を `| `Shomen::Store` | 追記と読取、このプロセスで追記を待つものを起こす | Event |` にする
- 43 行目を `| `Shomen::Island` | 公式 JS と島のモジュールの配信 | Route |` にし、その次の行に `| `Shomen::SSE` | このプロセスの追記のたびに断片を送り直す | Response, Store, Fragment |` を足す
- 「## 公式 JS」の本文の後に、空行を挟んで次の段落を足す:

```markdown
島のモジュールはアプリのファイルである。`Shomen::Island.script` がコンパイル時に読み、`/islands/<name>.js` で配る。`shomen.js` は `data-shomen-island` の要素があるときだけそれを読み込む（`docs/decisions/20260929-phase5-island-script.md`）。
```

- [ ] **Step 6: D1 を書く**

Create `docs/decisions/20260929-phase5-sse-response.md`:

```markdown
# 状況

フェーズ 5 は SSE をオプトインで作る。仕様 8 は既定の輸送を fetch とし、SSE をオプトインとする。仕様 10 では、フェーズ 7 で Postgres の通知とポーリングが SSE ストリームを起こす。受入は、SSE を使わないアプリに依存が増えないこと。フェーズ 4 までの `Shomen::Response` は本文を文字列で持ち、サーバは一度に書く。

# 決定

ルートは `sse(store, heartbeat = 15.seconds) { 断片 }` を返してストリームを開く。`Shomen::SSE < Shomen::Response` が 200、`Content-Type: text/event-stream`、`Cache-Control: no-store` で答える。

1. ルートの中で `store.last_appended` を読み、それから断片を描く。この描画の例外は、ふだんのエラー文書になる
2. サーバはヘッダの後に最初のメッセージを書き、`flush` する
3. `store.wait_for_append` で、このプロセスの追記を待つ。起きたら `last_appended` を読み直してから描き直し、HTML が前回送ったものと違うときだけ 1 メッセージ送る
4. 最後の書き込みから `heartbeat` の間なにも書かなかったら、コメント `:` を書く
5. 書き込みが失敗したら（`HTTP::Server::ClientError`）ストリームを終える。サーバはこの例外を外に出さず、要求を終える。2 回目以降の描画の例外はストリームを切り、`HTTP::Server` のログに出る

メッセージは HTML の行ごとに `data: ` を付ける。行の区切りは `\r\n`、`\r`、`\n`。`event`、`id`、`retry` は送らない。

`sse` を呼ぶルートだけがストリームを開く。フレームワークは SSE のルートを登録しない。ストリームが無ければ、ファイバーも接続も増えない。shard を足さない。

# 理由

描き直した断片をそのまま送れば、ブラウザは fetch と同じ規則で要素を置き換えられ、画面の状態はサーバが持ったままになる。起こし方を Store に閉じておけば、フェーズ 7 で通知とポーリングに替えてもルートは変わらない。`last_appended` を描画の前に読むので、描画と待ちの間に入った追記も取りこぼさない。最初の描画をルートの中で行えば、見つからない対象などのエラーは 404 などの文書になり、`EventSource` は再接続をやめる。同じ HTML は送らないので、関係ない追記で帯域を使わない。接続が切れたことは書き込みが失敗するまで分からないので、ハートビートで気付く。15 秒は、よくあるプロキシのアイドル切断より短い。HTML の改行をそのまま `data:` に入れると、空行でメッセージが切れ、`event:` などの行を注入できる。行ごとに `data: ` を付ければ、クライアントは `\n` でつないで元に戻す（`\r` は `\n` になるが、HTML の解析でも同じに扱われる）。計画時にユーザーがこの案を選んだ。

# 破棄した案

- ルートに書き込み口を渡し、送る時機と中身をアプリに任せる（起こす仕組みをアプリごとに作ることになり、フェーズ 7 の通知とつながらない）
- 変わったという合図だけ送り、`shomen.js` が GET で取り直す（更新のたびに要求が 1 往復増える）
- 追記のたびに断片を無条件に送る
- ストリームの中で最初の描画をする（エラーが 200 の後に起き、`EventSource` が再接続を繰り返す）
- `require "shomen/sse"` で別に読み込ませる（使わないメソッドはコンパイルされないので、分ける利点が無い）
```

- [ ] **Step 7: D2 を書く**

Create `docs/decisions/20260929-phase5-append-signal.md`:

```markdown
# 状況

SSE のストリームは、新しいイベントが入ったら描き直す。フェーズ 7 では Postgres の通知とポーリングがそれを知らせる（`20260929-scale-notify.md`）。フェーズ 5 の SSE は、1 プロセスの中の変更しか配れない。Store はフェーズ 3 から、1 つのファイルへの読み書きにプロセスで 1 つのロックを使っている。

# 決定

`Shomen::AppendSignal` を置く。これまでに知らされた最大の `id`（`last`）と、待っているファイバーの一覧を持つ。

- `announce(id)` は `last` を上げ（下げはしない）、待っているファイバーをすべて起こす
- `wait(after:, within:)` は、`last` が `after` を超えていればすぐ `true` を返す。そうでなければ知らせを待ち、`within` を過ぎたら `false` を返す。待ちが終わると一覧から自分を外す

Store は実パスごとに 1 つの AppendSignal をプロセスで共有する。`append` は `COMMIT` の後に、最後に入れた行の `id` を知らせる。衝突などで書かなかった追記は知らせない。Store が公開するのは `last_appended : Int64` と `wait_for_append(after : Int64, within : Time::Span) : Bool` だけ。

他のプロセスの追記は知らせない。

# 理由

Store が知らせれば、SSE は Store の API だけに依存し、SQLite も Postgres も知らずに済む。フェーズ 7 では、同じ API の裏で通知とポーリングが `announce` を呼べばよい。`COMMIT` の後に知らせるので、起きたストリームが読むとき行はもう見える。1 つのファイルを 2 つの Store で開いても、同じプロセスなら同じ知らせを受ける。待ち手を毎回外すので、終わったストリームが一覧に残らない。

# 破棄した案

- ストリームが一定間隔で `read` する（フェーズ 7 のポーリングを先に作ることになり、ストリームの数だけ問い合わせが増える）
- アプリが追記の後に呼ぶ通知 API を置く（呼び忘れると追記と通知がずれる）
- DB の最大の `id` を毎回読んで比べる（待つたびに問い合わせが増える）
```

- [ ] **Step 8: D3 を書く**

Create `docs/decisions/20260929-phase5-sse-script.md`:

```markdown
# 状況

`shomen.js` はフェーズ 4 で、fetch の応答から対象 `id` の要素を差し替える。SSE はオプトインで、属性は `data-shomen-*` だけ（仕様 8）。受入は、島の外にイベントリスナーを撒かないこと。

# 決定

`data-shomen-sse="URL"` の要素（ホルダー）ごとに、同じオリジンの URL なら `EventSource` を 1 つ開く。別オリジンの URL は開かない。

メッセージは断片とし、`<template>` で解析して最初の要素を取る。その `id` の要素がホルダーの中（ホルダー自身は除く）にあれば置き換える。無ければ捨てる。

置き換えは fetch と同じ関数で行う。置き換えの直前にフォーカスが対象の中にあり、その要素に `id` があれば、置き換えた後に同じ `id` の要素へフォーカスを戻す。

ページに入った要素は「落ち着かせる」。読み込み時のページ、fetch の置き換え、SSE の置き換え、POST で表示した文書全体が対象になる。ページから外れたホルダーのストリームを閉じ、入った要素の中のホルダーを開く。島もここで動かす（`20260929-phase5-island-script.md`）。

再接続は `EventSource` に任せる。サーバは接続のたびに今の断片を最初に送るので、切れていた間の変化も反映される。

`shomen.js` が付けるリスナーは、`document` の `click` と `submit`、`window` の `pageshow`、各 `EventSource` の `message` だけ。要素には付けない。

# 既知の制限

- 他のプロセスの追記は、フェーズ 7 まで届かない
- 入力中のフォームを含む要素を SSE で置き換えると、入力が消える。SSE の対象は表示だけの要素にする
- 戻る／進むキャッシュから復元したページで接続がどうなるかは、ブラウザに任せる

# 理由

断片の `id` で置き換えるので、fetch と同じ規則で読める。ホルダーの中だけを置き換えるので、ストリームはページの他の部分を書き換えない。ホルダー自身を置き換えると、つないでいる要素が消える。別オリジンの HTML は差し込まない（`20260929-phase4-script-attributes.md` と同じ）。外れたホルダーを閉じないと、見えない要素のために接続が残る。フォーカスを置き換えの直前に読むので、fetch の間に利用者がフォーカスを外へ動かしていたら、それを奪い返さない。

# 破棄した案

- ホルダー自身を置き換える（つないでいる要素が消え、つなぎ直しが要る）
- ページのどこでも同じ `id` の要素を置き換える（ストリームがページ全体を書き換えられる）
- `MutationObserver` で外れたホルダーを見張る（ページを書き換えるのは `shomen.js` の置き換えだけなので要らない）
```

- [ ] **Step 9: D4 を書く**

Create `docs/decisions/20260929-phase5-island-script.md`:

```markdown
# 状況

仕様 8 は、島が `data-shomen-island="name"` の要素にだけ JS を載せるとする。公式 JS は `shomen.js` 1 ファイルで、npm に依存しない。島の中身はアプリのコードで、フレームワークには置かない。`shomen.js` はコンパイル時に埋め込んで配っている（`20260929-phase4-script-serving.md`）。

# 決定

アプリは島ごとに ES モジュールのファイルを書き、`Shomen::Island.script "counter", "counter.js"` と宣言する。マクロは呼んだファイルのディレクトリを基準にファイルをコンパイル時に読み、呼んだ場所に `CounterIsland < Shomen::Route`（`GET /islands/counter.js`、`text/javascript; charset=utf-8`）を定義する。名前は英小文字で始まり、英小文字・数字・`-` だけからなる文字列リテラル。そうでない名前と、読めないファイルはコンパイルエラーにする。同じ名前を 2 回宣言すると、ルートの重複で起動に失敗する。

`shomen.js` は落ち着かせる要素の中の `[data-shomen-island]` ごとに、名前が同じ規則に合えば `import("/islands/" + name + ".js")` し、モジュールの `default` を要素を引数に呼ぶ。同じ要素では 2 回呼ばない。規則に合わない名前は読み込まない。

モジュールがリスナーを付けてよいのは、受け取った要素とその中だけ。

公式 JS の検査は、静的な `import` と `export` を禁じたまま、島を読む動的な `import(` を 1 か所だけ認める。

# 理由

名前からパスが決まるので、属性は名前だけで済み、仕様 8 の書き方のまま動く。コンパイル時に読めば、`shomen.js` と同じく配置先に関係なく配れ、ビルド手順も npm も要らない。ルートとして定義すれば、登録と重複検査が既存の仕組みで済む。`import()` は同じモジュールを 1 度だけ評価し、フェーズ 6 の CSP `script-src 'self'` でも同じオリジンなら動く。名前の規則が無いと、`../` を含む名前で同じオリジンの別のスクリプトを読み込める。

# 破棄した案

- 属性に URL を書く（名前ではなくなり、仕様 8 の書き方から外れる）
- 島のコードを `shomen.js` に入れる（アプリの JS がフレームワークに入る）
- 実行時にディスクからファイルを読む（配置先で壊れる）
- アプリが `script` 要素で島のコードを読み込む（島の無いページにも JS が載る）
```

- [ ] **Step 10: D5 を書く**

Create `docs/decisions/20260929-phase5-listener-spec.md`:

```markdown
# 状況

受入「フレームワークは島の外にイベントリスナーを撒かない」と「SSE を使わないアプリに依存が増えない」は、ブラウザで JS を動かさないと確かめられない。ブラウザ spec が使う CDP のコマンドは決まっている（`20260929-phase4-browser-spec.md`）。SSE の応答は終わらないので、`call_with` のように書き終わるのを待つヘルパーでは読めない。

# 決定

`Browser#before_load(source)` を足す。`Page.addScriptToEvaluateOnNewDocument` で、ページのスクリプトより先に `source` を動かす。spec はこれで `EventTarget.prototype.addEventListener` と `EventSource` を包み、リスナーを付けた相手と種類、開いたストリームを `window.shomenSeen` に記録する（`PAGE_SPY`）。

受入の spec は、島を動かし、fetch で島を足し、SSE で要素を置き換えた後で、リスナーを付けた相手を `window`、`document`、`EventSource`、島の中の要素、島の外の要素に分ける。島の外の要素が 1 つも無く、`window` と `document` には `shomen.js` の 3 つだけが付いていることを確かめる。`data-shomen-sse` の無いページでは、`EventSource` が 1 つも開かないことを確かめる。

`Browser#run(body)` を足す。`body` を async 関数の中で動かし、`waitFor(check)` を使えるようにする。`waitFor` は最初にすぐ確かめ、その後は文書が変わるたびに確かめる。

サーバ側の SSE の spec は、`IO.pipe` に応答を書かせて読む `SSEClient` を使う。応答は HTTP/1.0 にして、本文をチャンクに分けずに読む。読み込みは 5 秒で打ち切る。クライアントが去ったことは、読む側を閉じて表す。

島の例の動作は、`examples/hello` の spec が `spec/support/browser.cr` を読み込み、Chrome で確かめる。

# 理由

ページのスクリプトより前に包まないと、`shomen.js` が読み込み時に付けるリスナーを記録できない。`on*` プロパティへの代入は包めないので、`shomen.js` がそれを使わないことは文字列で検査する。フェーズ 4 の spec の `waitFor` は変化を待つだけなので、Crystal 側で追記した後に始めると、先に届いた更新を見逃す。パイプは実ポートを使わない。読む側を閉じた後の書き込みはすぐ失敗するので、切断を決まった順序で試せる。

# 破棄した案

- ページの `head` にインラインの `script` を書いて包む（DSL が書かない要素を spec でだけ使い、フェーズ 6 の CSP と衝突する）
- 一時ポートの HTTP クライアントで SSE を読む（TCP では切断後の最初の書き込みが成功することがあり、終わる時機が決まらない）
- 島の例の動作を手で確かめるだけにする（回帰を捕まえられない）
```

- [ ] **Step 11: D6 を書く**

Create `docs/decisions/20260929-phase5-counter-example.md`:

```markdown
# 状況

フェーズ 5 は島の例を 1 つ作る（カウンターで十分）。サンプルは `examples/` にだけ置く。`examples/hello` は SSE を使っていない。

# 決定

`examples/hello/src/counter.cr` に `Counter` を置く。`GET /counter` の文書は、`data-shomen-island="counter"` の `div` の中に、数を示す `p`（`aria-live="polite"`）と、`hidden` の「Add one」ボタン（`type="button"`）を置く。`examples/hello/src/counter.js` はボタンを表示し、クリックごとに数を 1 増やす。リスナーはボタンにだけ付ける。`Shomen::Island.script "counter", "counter.js"` で配る。

`examples/hello` は SSE を使わないままにする。

# 理由

数はブラウザの中だけの短い状態なので、島の例に合う。JS が無いとボタンを押しても何も起きないので隠しておき、島が動いたときだけ見せる。`aria-live` で数の変化が読み上げられる。例が SSE を使わなければ、SSE を使わないアプリの依存が増えていないことを、その `shard.lock` で確かめられる。

# 破棄した案

- 数をサーバに POST する（島の例ではなくなる）
- 例に SSE も入れる（受入に要らず、SSE を使わないアプリの確認に使えなくなる）
- 新しい例 `examples/counter` を作る
```

- [ ] **Step 12: 文書だけが変わったことを確かめる**

Run: `git status --short && crystal spec`
Expected: 変更は `docs/` の下だけ。spec はフェーズ 4 の終わりと同じ結果（0 failures、Chrome があれば 0 pending）。

---

### Task 2: 追記の知らせ（AppendSignal と Store）

**Files:**
- Create: `src/shomen/append_signal.cr`
- Modify: `src/shomen/store.cr:1-7`（require）、`:29-33`（クラス変数とインスタンス変数）、`:72-73`（ロックと知らせ）、`:76-101`（`append`）、`:119-128`（`insert`）
- Modify: `src/shomen.cr:13-14`
- Create: `spec/shomen/append_signal_spec.cr`
- Modify: `spec/shomen/store_spec.cr`（末尾の `end` の前に例を足す）

**Interfaces:**
- Consumes: 既存の `Shomen::Store`、`with_store`（`spec/support/store.cr`、`store, path` を yield）、`note(text) : Array(Shomen::Event)`
- Produces:
  - `Shomen::AppendSignal#announce(id : Int64) : Nil`
  - `Shomen::AppendSignal#wait(after : Int64, within : Time::Span) : Bool`
  - `Shomen::AppendSignal#last : Int64`
  - `Shomen::AppendSignal#waiting : Int32`
  - `Shomen::Store#last_appended : Int64`
  - `Shomen::Store#wait_for_append(after : Int64, within : Time::Span) : Bool`

- [ ] **Step 1: AppendSignal の失敗する spec を書く**

Create `spec/shomen/append_signal_spec.cr`:

```crystal
require "../spec_helper"

private def receive_within(channel : Channel(Bool)) : Bool
  select
  when value = channel.receive
    value
  when timeout(5.seconds)
    raise "no answer within 5 seconds"
  end
end

# Lets other fibers run until count of them wait on the signal.
private def until_waiting(signal : Shomen::AppendSignal, count : Int32) : Nil
  deadline = Time.instant + 5.seconds
  until signal.waiting == count
    raise "no fiber waited within 5 seconds" if Time.instant > deadline
    Fiber.yield
  end
end

describe Shomen::AppendSignal do
  it "wakes a fiber that waits for an id above the one it saw" do
    signal = Shomen::AppendSignal.new
    woke = Channel(Bool).new(1)
    spawn { woke.send(signal.wait(after: 0_i64, within: 5.seconds)) }
    until_waiting(signal, 1)
    signal.announce(3_i64)
    receive_within(woke).should be_true
    signal.last.should eq(3_i64)
    signal.waiting.should eq(0)
  end

  it "returns at once when a higher id came before the wait" do
    signal = Shomen::AppendSignal.new
    signal.announce(2_i64)
    signal.wait(after: 1_i64, within: 5.seconds).should be_true
    signal.waiting.should eq(0)
  end

  it "returns false after the limit and forgets the waiter" do
    signal = Shomen::AppendSignal.new
    signal.announce(2_i64)
    signal.wait(after: 2_i64, within: 1.millisecond).should be_false
    signal.waiting.should eq(0)
  end

  it "never lowers the last id" do
    signal = Shomen::AppendSignal.new
    signal.announce(5_i64)
    signal.announce(4_i64)
    signal.last.should eq(5_i64)
  end
end
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `crystal spec spec/shomen/append_signal_spec.cr`
Expected: コンパイルエラー `undefined constant Shomen::AppendSignal`。

- [ ] **Step 3: AppendSignal を書く**

Create `src/shomen/append_signal.cr`:

```crystal
# Wakes the fibers of this process that wait for an append to one
# database file. Appends in other processes do not reach it (phase 7).
class Shomen::AppendSignal
  @last = 0_i64
  @waiters = [] of Channel(Nil)
  @lock = Mutex.new

  # The highest id announced, 0 before the first.
  def last : Int64
    @lock.synchronize { @last }
  end

  def waiting : Int32
    @lock.synchronize { @waiters.size }
  end

  def announce(id : Int64) : Nil
    @lock.synchronize do
      @last = id if id > @last
      @waiters.each do |waiter|
        select
        when waiter.send(nil)
        else
        end
      end
    end
  end

  # True as soon as an id above after is announced, false when within
  # passes first. The waiter leaves the list either way.
  def wait(after : Int64, within : Time::Span) : Bool
    waiter = Channel(Nil).new(1)
    @lock.synchronize do
      return true if @last > after
      @waiters << waiter
    end
    begin
      select
      when waiter.receive
        true
      when timeout(within)
        false
      end
    ensure
      @lock.synchronize { @waiters.delete(waiter) }
    end
  end
end
```

`src/shomen.cr` の `require "./shomen/recorded"` の次に足す:

```crystal
require "./shomen/append_signal"
```

- [ ] **Step 4: 通ることを確かめる**

Run: `crystal spec spec/shomen/append_signal_spec.cr`
Expected: 4 examples, 0 failures。

- [ ] **Step 5: Store の失敗する spec を書く**

`spec/shomen/store_spec.cr` の `describe Shomen::Store do` の最後の `end` の前に足す:

```crystal
  it "tells this process the last id it appended, through any store on the file" do
    with_store do |store, path|
      store.last_appended.should eq(0_i64)
      store.append("a", 0_i64, [SpecEvents::Noted.new("1"), SpecEvents::Noted.new("2")] of Shomen::Event)
      store.last_appended.should eq(2_i64)
      other = Shomen::Store.new("sqlite3://#{path}")
      begin
        other.last_appended.should eq(2_i64)
        other.append("b", 0_i64, note("3"))
        store.last_appended.should eq(3_i64)
      ensure
        other.close
      end
    end
  end

  it "announces nothing for an append that conflicts" do
    with_store do |store|
      store.append("a", 0_i64, note("1"))
      expect_raises(Shomen::Conflict) { store.append("a", 0_i64, note("2")) }
      store.last_appended.should eq(1_i64)
    end
  end

  it "wakes a fiber that waits for an append in this process" do
    with_store do |store|
      woke = Channel(Bool).new(1)
      spawn { woke.send(store.wait_for_append(after: 0_i64, within: 5.seconds)) }
      Fiber.yield
      store.append("a", 0_i64, note("1"))
      select
      when value = woke.receive
        value.should be_true
      when timeout(5.seconds)
        fail "the waiting fiber did not wake"
      end
    end
  end
```

- [ ] **Step 6: 落ちることを確かめる**

Run: `crystal spec spec/shomen/store_spec.cr`
Expected: コンパイルエラー `undefined method 'last_appended' for Shomen::Store`。

- [ ] **Step 7: Store に知らせを足す**

`src/shomen/store.cr` の require に `./append_signal` を足す:

```crystal
require "uri"
require "db"
require "sqlite3"
require "./event"
require "./recorded"
require "./conflict"
require "./append_signal"
```

クラスのコメントの最後に 1 文足す（`IMMEDIATE; other processes wait through the busy timeout.` の次の行）:

```crystal
# Append-only event log in one SQLite file. Appends, reads, and close in a
# process take one fiber-aware lock per file, and appends then BEGIN
# IMMEDIATE; other processes wait through the busy timeout. After a commit
# an append wakes what waits for it in this process.
```

クラス変数とインスタンス変数を次にする:

```crystal
  @@locks = {} of String => Mutex
  @@signals = {} of String => Shomen::AppendSignal
  @@locks_lock = Mutex.new

  @db : DB::Database
  @lock : Mutex
  @signal : Shomen::AppendSignal
```

`initialize` の最後の 2 行（`real = …` と `@lock = …`）を次にする:

```crystal
    real = File.realpath(filename)
    @lock, @signal = @@locks_lock.synchronize do
      {@@locks[real] ||= Mutex.new, @@signals[real] ||= Shomen::AppendSignal.new}
    end
```

`append` の `@lock.synchronize do … end` を次にする（知らせは `COMMIT` の後、ロックの外）:

```crystal
    last_id = @lock.synchronize do
      @db.using_connection do |connection|
        begin
          connection.exec("BEGIN IMMEDIATE")
        rescue ex
          reset(connection, "BEGIN IMMEDIATE")
          raise ex
        end
        begin
          id = insert(connection, stream, expected_version, rows)
          connection.exec("COMMIT")
          id
        rescue ex
          rollback(connection)
          raise ex
        end
      end
    end
    @signal.announce(last_id)
  end

  # The highest id this process appended to the file, 0 before the first.
  def last_appended : Int64
    @signal.last
  end

  # Waits until this process appends an event with an id above after.
  # False when within passes first.
  def wait_for_append(after : Int64, within : Time::Span) : Bool
    @signal.wait(after, within)
  end
```

`insert` を、最後に入れた行の `id` を返すようにする:

```crystal
  private def insert(connection : DB::Connection, stream : String, expected_version : Int64, rows : Array({String, String, String})) : Int64
    current = connection.scalar(SELECT_VERSION, stream).as(Int64)
    unless current == expected_version
      raise Shomen::Conflict.new("stream #{stream} is at version #{current}, expected #{expected_version}")
    end
    last_id = 0_i64
    rows.each_with_index(1) do |row, offset|
      type, payload, at = row
      last_id = connection.exec(INSERT, stream, expected_version + offset, type, payload, at).last_insert_id
    end
    last_id
  end
```

- [ ] **Step 8: 通ることを確かめる**

Run: `crystal spec spec/shomen/store_spec.cr spec/shomen/append_signal_spec.cr spec/shomen/store_concurrency_spec.cr spec/shomen/boundary_spec.cr`
Expected: 0 failures。既存の Store の例も通る。

- [ ] **Step 9: 境界の検査に AppendSignal を足す**

`spec/shomen/boundary_spec.cr` の 2 つのリストを次にする:

```crystal
    %w(store event recorded conflict append_signal).each do |name|
```

```crystal
    %w(command event rejected recorded projection append_signal).each do |name|
```

Run: `crystal spec spec/shomen/boundary_spec.cr && crystal tool format --check`
Expected: 0 failures、差分なし。

---

### Task 3: SSE の応答（Shomen::SSE、Route#sse、Server）

**Files:**
- Create: `src/shomen/sse.cr`
- Modify: `src/shomen/route.cr:183-185`（`json` の後に `sse`）
- Modify: `src/shomen/server.cr:117-122`（本文の書き込み）
- Modify: `src/shomen.cr:16`
- Create: `spec/support/sse_client.cr`
- Create: `spec/support/sse_routes.cr`
- Modify: `spec/spec_helper.cr`
- Create: `spec/shomen/sse_spec.cr`
- Modify: `spec/shomen/boundary_spec.cr`

**Interfaces:**
- Consumes: Task 2 の `Shomen::Store#last_appended`、`Shomen::Store#wait_for_append(after:, within:)`。既存の `Shomen::Fragment`、`SpecEvents::Log`（`lines`）、`SpecEvents::Renamed`、`note`、`with_store`、`call_with`
- Produces:
  - `Shomen::SSE < Shomen::Response`、`Shomen::SSE::HEARTBEAT = 15.seconds`、`Shomen::SSE.message(html : String) : String`、`Shomen::SSE.new(store : Shomen::Store, fragment : -> Shomen::Fragment, heartbeat : Time::Span)`、`Shomen::SSE#run(io : IO) : Nil`
  - `Shomen::Route#sse(store : Shomen::Store, heartbeat : Time::Span = Shomen::SSE::HEARTBEAT, &fragment : -> Shomen::Fragment) : Shomen::Response`
  - spec: `SSEClient.new(server, path)`、`#status : Int32`、`#headers : HTTP::Headers`、`#next_block : String`、`#next_message : String`、`#close`、`#wait_finished`、`with_sse_client(path, &)`
  - spec: `SSERoutes.store=`、`SSERoutes.store!`、`SSERoutes.count : Int32`、`SSERoutes.drain_rendered`、`SSERoutes.next_render : String`、`SSERoutes::HEARTBEAT`、`SSERoutes::TARGET`、`SSERoutes::RENDERED`、`SSERoutes::CountFragment`、`SSERoutes::Live`（`/phase5/live`）、`SSERoutes::Racing`（`/phase5/racing`）、`SSERoutes::Missing`（`/phase5/missing`）

- [ ] **Step 1: spec のクライアントを書く**

SSE の応答は終わらないので、`call_with`（`IO::Memory` に書き終わるのを待つ）で SSE のルートを呼んではいけない。止まる。

Create `spec/support/sse_client.cr`:

```crystal
require "http"

# Sends a GET through Shomen::Server#call with the response going into a
# pipe, and reads it as an event stream. An SSE response does not end by
# itself, so call_with cannot read one. The response is HTTP/1.0, so the
# body arrives unchunked. Each read waits up to LIMIT.
class SSEClient
  LIMIT = 5.seconds

  getter status : Int32
  getter headers = HTTP::Headers.new
  @reader : IO::FileDescriptor
  @finished : Channel(Nil)

  def initialize(server : Shomen::Server, path : String)
    reader, writer = IO.pipe
    reader.read_timeout = LIMIT
    @reader = reader
    @finished = Channel(Nil).new(1)
    finished = @finished
    spawn do
      response = HTTP::Server::Response.new(writer)
      response.version = "HTTP/1.0"
      begin
        server.call(HTTP::Server::Context.new(HTTP::Request.new("GET", path), response))
        response.close
      rescue HTTP::Server::ClientError
      end
      writer.close rescue nil
      finished.send(nil)
    end
    head = reader.gets(chomp: true) || raise "no status line"
    @status = head.split(' ')[1].to_i
    while (line = reader.gets(chomp: true)) && !line.empty?
      name, _, value = line.partition(": ")
      @headers.add(name, value)
    end
  end

  # The next block up to the blank line that ends it: a message's data
  # lines joined with "\n", or ":" for a comment.
  def next_block : String
    data = [] of String
    comment = false
    loop do
      line = @reader.gets(chomp: true) || raise "the stream ended"
      if line.empty?
        return data.join("\n") unless data.empty?
        return ":" if comment
      elsif line.starts_with?(':')
        comment = true
      elsif line.starts_with?("data: ")
        data << line.lchop("data: ")
      else
        raise "unexpected line #{line.inspect}"
      end
    end
  end

  # The next message, past any comments.
  def next_message : String
    loop do
      block = next_block
      return block unless block == ":"
    end
  end

  # Closes the client's end, as a browser that leaves does.
  def close : Nil
    @reader.close
  end

  # Waits until Shomen::Server#call has returned.
  def wait_finished : Nil
    select
    when @finished.receive
    when timeout(LIMIT)
      raise "the server did not finish within #{LIMIT}"
    end
  end
end

# The stream of the routes in SSERoutes ends within a heartbeat after
# close, so wait_finished returns.
def with_sse_client(path : String, & : SSEClient ->) : Nil
  client = SSEClient.new(Shomen::Server.new, path)
  begin
    yield client
  ensure
    client.close
    client.wait_finished
  end
end
```

- [ ] **Step 2: spec のルートを書く**

Create `spec/support/sse_routes.cr`:

```crystal
# Routes for the SSE specs. They read the store a spec sets and beat every
# 50 ms, so a stream whose client left ends quickly.
module SSERoutes
  HEARTBEAT = 50.milliseconds

  # The id the count fragment of Live carries.
  TARGET = ["count"]

  # Live sends the id of each render, so a spec knows a render ran.
  RENDERED = Channel(String).new(64)

  @@store : Shomen::Store? = nil

  def self.store=(store : Shomen::Store?) : Nil
    @@store = store
  end

  def self.store! : Shomen::Store
    @@store || raise "set SSERoutes.store first"
  end

  # The number of Noted events in the store.
  def self.count : Int32
    SpecEvents::Log.new(store!).catch_up.lines.size
  end

  def self.drain_rendered : Nil
    loop do
      select
      when RENDERED.receive
      else
        break
      end
    end
  end

  def self.next_render : String
    select
    when id = RENDERED.receive
      id
    when timeout(5.seconds)
      raise "no render within 5 seconds"
    end
  end

  class CountFragment < Shomen::Fragment
    def initialize(@id : String, @count : Int32)
    end

    def content : Nil
      id = @id
      count = @count
      p count.to_s, id: id
    end
  end

  # The count of Noted events, under the id in TARGET.
  class Live < Shomen::Route
    method GET
    path "/phase5/live"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      log = SpecEvents::Log.new(SSERoutes.store!)
      sse(SSERoutes.store!, heartbeat: SSERoutes::HEARTBEAT) do
        log.catch_up
        id = SSERoutes::TARGET[0]
        select
        when SSERoutes::RENDERED.send(id)
        else
        end
        CountFragment.new(id, log.lines.size)
      end
    end
  end

  # Its first render appends, as another request can between a render
  # and the wait that follows it.
  class Racing < Shomen::Route
    method GET
    path "/phase5/racing"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      store = SSERoutes.store!
      log = SpecEvents::Log.new(store)
      first = true
      sse(store, heartbeat: SSERoutes::HEARTBEAT) do
        log.catch_up
        count = log.lines.size
        if first
          first = false
          store.append("racing", 0_i64, note("during the first render"))
        end
        CountFragment.new("count", count)
      end
    end
  end

  # Its first render finds nothing.
  class Missing < Shomen::Route
    method GET
    path "/phase5/missing"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      sse(SSERoutes.store!, heartbeat: SSERoutes::HEARTBEAT) { find }
    end

    private def find : Shomen::Fragment
      raise Shomen::NotFound.new
    end
  end
end
```

`spec/spec_helper.cr` の `require "./support/browser_routes"` の後に足す:

```crystal
require "./support/sse_client"
require "./support/sse_routes"
```

- [ ] **Step 3: 失敗する spec を書く**

Create `spec/shomen/sse_spec.cr`:

```crystal
require "../spec_helper"
require "yaml"

private def with_sse_routes(& : Shomen::Store ->) : Nil
  with_store do |store|
    SSERoutes.store = store
    SSERoutes::TARGET[0] = "count"
    SSERoutes.drain_rendered
    begin
      yield store
    ensure
      SSERoutes.store = nil
    end
  end
end

describe Shomen::SSE do
  it "puts every line of the HTML in its own data line" do
    Shomen::SSE.message(%(<p>a</p>)).should eq("data: <p>a</p>\n\n")
    Shomen::SSE.message("<p>a\r\nb\rc\nd</p>").should eq("data: <p>a\ndata: b\ndata: c\ndata: d</p>\n\n")
    Shomen::SSE.message("<p>x\n\nevent: boom\ndata: y</p>").should eq(
      "data: <p>x\ndata: \ndata: event: boom\ndata: data: y</p>\n\n"
    )
  end

  it "answers with an event stream that starts with the current fragment" do
    with_sse_routes do
      with_sse_client(SSERoutes::Live.path) do |client|
        client.status.should eq(200)
        client.headers["Content-Type"].should eq("text/event-stream")
        client.headers["Cache-Control"].should eq("no-store")
        client.headers["X-Content-Type-Options"].should eq("nosniff")
        client.next_message.should eq(%(<p id="count">0</p>))
      end
    end
  end

  it "sends the fragment again after this process appends" do
    with_sse_routes do |store|
      with_sse_client(SSERoutes::Live.path) do |client|
        client.next_message.should eq(%(<p id="count">0</p>))
        store.append("sse-1", 0_i64, note("one"))
        client.next_message.should eq(%(<p id="count">1</p>))
      end
    end
  end

  it "sends nothing when an append leaves the fragment as it was" do
    with_sse_routes do |store|
      with_sse_client(SSERoutes::Live.path) do |client|
        client.next_message.should eq(%(<p id="count">0</p>))
        SSERoutes.next_render.should eq("count")
        store.append("sse-1", 0_i64, [SpecEvents::Renamed.new("x")] of Shomen::Event)
        SSERoutes.next_render.should eq("count")
        store.append("sse-1", 1_i64, note("one"))
        client.next_message.should eq(%(<p id="count">1</p>))
      end
    end
  end

  it "does not lose an append made while the fragment renders" do
    with_sse_routes do
      with_sse_client(SSERoutes::Racing.path) do |client|
        client.next_message.should eq(%(<p id="count">0</p>))
        client.next_message.should eq(%(<p id="count">1</p>))
      end
    end
  end

  it "writes a comment when it sent nothing for a heartbeat" do
    with_sse_routes do
      with_sse_client(SSERoutes::Live.path) do |client|
        client.next_message.should eq(%(<p id="count">0</p>))
        client.next_block.should eq(":")
      end
    end
  end

  it "ends when the client leaves" do
    with_sse_routes do
      client = SSEClient.new(Shomen::Server.new, SSERoutes::Live.path)
      client.next_message.should eq(%(<p id="count">0</p>))
      client.close
      client.wait_finished
    end
  end

  it "answers an error in the first render with the error document" do
    with_sse_routes do
      response = call_with(Shomen::Server.new, "GET", SSERoutes::Missing.path)
      response.status_code.should eq(404)
      response.headers["Content-Type"].should eq("text/html; charset=utf-8")
      response.body.should contain("Not found")
    end
  end

  it "adds no shard, so an application without SSE gains no dependency" do
    YAML.parse(File.read("shard.yml"))["dependencies"].as_h.keys.map(&.as_s).should eq(["sqlite3", "db"])
    locked = YAML.parse(File.read("examples/hello/shard.lock"))["shards"].as_h.keys.map(&.as_s)
    locked.sort.should eq(["db", "shomen", "sqlite3"])
  end
end
```

- [ ] **Step 4: 落ちることを確かめる**

Run: `crystal spec spec/shomen/sse_spec.cr`
Expected: コンパイルエラー `undefined method 'sse'`（または `undefined constant Shomen::SSE`）。

- [ ] **Step 5: Shomen::SSE を書く**

Create `src/shomen/sse.cr`:

```crystal
require "http"
require "./response"
require "./store"
require "./fragment"

# An event stream a route opens with sse. It sends the fragment's HTML
# first, then again after each append in this process that changed it.
# Appends in other processes do not wake it (phase 7).
class Shomen::SSE < Shomen::Response
  HEARTBEAT = 15.seconds

  # One message. Each line of the HTML goes in its own data line, so a line
  # break in the text cannot end the message or start another field.
  def self.message(html : String) : String
    String.build do |io|
      html.split(/\r\n|\r|\n/).each { |line| io << "data: " << line << '\n' }
      io << '\n'
    end
  end

  @seen : Int64
  @html : String
  @written : Time::Instant

  # The first render runs here, inside the route, so an error in it is an
  # ordinary error document rather than a broken stream. The last id is
  # read before it, so an append during the render still wakes the stream.
  def initialize(@store : Shomen::Store, @fragment : -> Shomen::Fragment, @heartbeat : Time::Span = HEARTBEAT)
    @seen = @store.last_appended
    @html = @fragment.call.to_html
    @written = Time.instant
    super(200, "text/event-stream", "", HTTP::Headers{"Cache-Control" => "no-store"})
  end

  # Returns only by raising when a write fails, which is how a stream
  # learns that its client left.
  def run(io : IO) : Nil
    write(io, Shomen::SSE.message(@html))
    loop do
      left = @written + @heartbeat - Time.instant
      if left.positive? && @store.wait_for_append(after: @seen, within: left)
        @seen = @store.last_appended
        html = @fragment.call.to_html
        next if html == @html
        @html = html
        write(io, Shomen::SSE.message(html))
      else
        write(io, ":\n\n")
      end
    end
  end

  private def write(io : IO, text : String) : Nil
    io << text
    io.flush
    @written = Time.instant
  end
end
```

`src/shomen.cr` の `require "./shomen/response"` の次に足す:

```crystal
require "./shomen/sse"
```

- [ ] **Step 6: Route#sse を足す**

`src/shomen/route.cr` の `json` の後に足す:

```crystal
  # Opts this GET route into an event stream for an element with
  # data-shomen-sse. fragment renders now and again after each append to
  # store in this process; the stream sends its HTML whenever it changed.
  def sse(store : Shomen::Store, heartbeat : Time::Span = Shomen::SSE::HEARTBEAT, &fragment : -> Shomen::Fragment) : Shomen::Response
    Shomen::SSE.new(store, fragment, heartbeat)
  end
```

- [ ] **Step 7: サーバが SSE を書く**

`src/shomen/server.cr` の `write_response` の最後の `if … else … end` を次にし、その後に `stream` を足す:

```crystal
    if context.request.method == "HEAD"
      context.response.content_length = response.body.bytesize
    elsif response.is_a?(Shomen::SSE)
      stream(context.response, response)
    else
      context.response.print(response.body)
    end
  end

  # A write fails once the client has left, and that ends the stream.
  private def stream(output : HTTP::Server::Response, sse : Shomen::SSE) : Nil
    sse.run(output)
  rescue HTTP::Server::ClientError
  end
```

- [ ] **Step 8: 通ることを確かめる**

Run: `crystal spec spec/shomen/sse_spec.cr`
Expected: 9 examples, 0 failures。

- [ ] **Step 9: 境界の検査に SSE を足す**

`spec/shomen/boundary_spec.cr` の SQLite のリストを次にする（Task 2 で `append_signal` を足したもの）:

```crystal
    %w(command event rejected recorded projection append_signal sse).each do |name|
```

Run: `crystal spec && crystal tool format --check`
Expected: 0 failures、Chrome があれば 0 pending、差分なし。既存の応答の spec（`server_spec.cr`、`fragment_request_spec.cr` など）は変わらず通る。

---

### Task 4: 島のモジュールの配信（Shomen::Island.script）

**Files:**
- Modify: `src/shomen/island.cr`
- Create: `spec/support/islands/counter.js`
- Create: `spec/support/island_routes.cr`
- Modify: `spec/spec_helper.cr`
- Create: `spec/fixtures/island_bad_name.cr`
- Create: `spec/fixtures/island_missing_file.cr`
- Modify: `spec/shomen/island_spec.cr`（`describe` の最後の `end` の前に例を足す）

**Interfaces:**
- Consumes: 既存の `Shomen::Route`（`method`、`path`、`Input`）、`call_with`、`crystal_build_fixture(path) : {Int32, String}`
- Produces:
  - `Shomen::Island::CONTENT_TYPE = "text/javascript; charset=utf-8"`
  - `macro Shomen::Island.script(name, file, dir = __DIR__)`: 呼んだ場所に `<Name>Island < Shomen::Route`（`GET /islands/<name>.js`、定数 `SOURCE`）を定義する。`<Name>` は `name` の `-` を `_` にして camelcase にしたもの（`"counter"` → `CounterIsland`、`"date-picker"` → `DatePickerIsland`）
  - spec: `IslandRoutes::CounterIsland`（`/islands/counter.js`）

- [ ] **Step 1: spec の島のモジュールを書く**

Create `spec/support/islands/counter.js`:

```js
// A counter kept in the browser. The server renders the count and a hidden
// button; this module shows the button and listens on it alone.
export default (island) => {
  const value = island.querySelector("p");
  const button = island.querySelector("button");
  let count = Number(value.textContent);
  button.addEventListener("click", () => {
    count += 1;
    value.textContent = String(count);
  });
  button.hidden = false;
};
```

Create `spec/support/island_routes.cr`:

```crystal
module IslandRoutes
  Shomen::Island.script "counter", "islands/counter.js"
end
```

`spec/spec_helper.cr` の `require "./support/sse_routes"` の後に足す:

```crystal
require "./support/island_routes"
```

- [ ] **Step 2: 失敗する spec とフィクスチャを書く**

Create `spec/fixtures/island_bad_name.cr`:

```crystal
require "../../src/shomen"

Shomen::Island.script "Counter", "../support/islands/counter.js"
```

Create `spec/fixtures/island_missing_file.cr`:

```crystal
require "../../src/shomen"

Shomen::Island.script "counter", "no_such_island.js"
```

`spec/shomen/island_spec.cr` の `describe Shomen::Island do` の最後の `end` の前に足す:

```crystal
  it "serves an island module declared with Shomen::Island.script" do
    response = call_with(Shomen::Server.new, "GET", "/islands/counter.js")
    response.status_code.should eq(200)
    response.headers["Content-Type"].should eq("text/javascript; charset=utf-8")
    response.headers["X-Content-Type-Options"].should eq("nosniff")
    response.body.should eq(File.read("spec/support/islands/counter.js"))
    IslandRoutes::CounterIsland.path.should eq("/islands/counter.js")
  end

  it "answers a module that no island declared with 404" do
    call_with(Shomen::Server.new, "GET", "/islands/nothing.js").status_code.should eq(404)
  end

  it "fails to compile an island name that is not a plain name" do
    status, output = crystal_build_fixture("spec/fixtures/island_bad_name.cr")
    status.should_not eq(0)
    output.should contain("island name must be")
  end

  it "fails to compile an island whose file cannot be read" do
    status, output = crystal_build_fixture("spec/fixtures/island_missing_file.cr")
    status.should_not eq(0)
    output.should contain("island file not found")
  end
```

- [ ] **Step 3: 落ちることを確かめる**

Run: `crystal spec spec/shomen/island_spec.cr`
Expected: コンパイルエラー `undefined macro method 'Shomen::Island.script'`（または `undefined method 'script'`）。

- [ ] **Step 4: マクロを書く**

`src/shomen/island.cr` を次にする:

```crystal
require "./route"

# Serves the official JavaScript and the island modules. Each file is read
# at compile time, so the binary carries it wherever it runs and nothing
# builds it.
module Shomen::Island
  SOURCE       = {{ read_file("#{__DIR__}/assets/shomen.js") }}
  CONTENT_TYPE = "text/javascript; charset=utf-8"

  class Script < Shomen::Route
    method GET
    path "/shomen.js"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.new(200, CONTENT_TYPE, SOURCE)
    end
  end

  # Defines, where it is called, the route <Name>Island that serves the
  # module of the island name at /islands/<name>.js. file is read at
  # compile time, relative to the file that calls this. shomen.js loads the
  # module for an element with data-shomen-island="<name>" and calls its
  # default with the element.
  macro script(name, file, dir = __DIR__)
    {% unless name.is_a?(StringLiteral) && name =~ /\A[a-z][a-z0-9-]*\z/ %}
      {% name.raise "island name must be a string literal of lower-case letters, digits, and '-' that starts with a letter, got #{name}" %}
    {% end %}
    {% unless file.is_a?(StringLiteral) %}
      {% file.raise "island file must be a string literal" %}
    {% end %}
    {% file_path = file.starts_with?("/") ? file : "#{dir.id}/#{file.id}" %}
    {% source = read_file?(file_path) %}
    {% unless source %}
      {% file.raise "island file not found: #{file_path.id}" %}
    {% end %}
    class {{name.tr("-", "_").camelcase.id}}Island < ::Shomen::Route
      method GET
      path {{"/islands/#{name.id}.js"}}

      SOURCE = {{source}}

      struct Input
      end

      def call(input : Input) : ::Shomen::Response
        ::Shomen::Response.new(200, ::Shomen::Island::CONTENT_TYPE, SOURCE)
      end
    end
  end
end
```

- [ ] **Step 5: 通ることを確かめる**

Run: `crystal spec spec/shomen/island_spec.cr`
Expected: 8 examples, 0 failures（既存の 4 と新しい 4）。

Run: `crystal spec && crystal tool format --check`
Expected: 0 failures、差分なし。

---

### Task 5: Browser ヘルパー（before_load、run）

**Files:**
- Modify: `spec/support/browser.cr`（`evaluate` の後）
- Modify: `spec/shomen/browser_spec.cr`（`if Browser.executable` の中に例を足す）
- Modify: `docs/decisions/20260929-phase4-browser-spec.md`（使う CDP のコマンドに 1 つ足す）

**Interfaces:**
- Consumes: 既存の `Browser#command`、`Browser#evaluate`、`with_browser`、`with_live_server`、`/phase1/home`
- Produces:
  - `Browser#before_load(source : String) : Nil`
  - `Browser#run(body : String) : JSON::Any`。`body` の中で `waitFor(check)` が使える。`waitFor` は `check()` が `undefined` 以外を返したらその値で解決する。最初にすぐ確かめ、その後は文書が変わるたびに確かめる

- [ ] **Step 1: 失敗する spec を書く**

`spec/shomen/browser_spec.cr` の `it "raises when a script throws"` の後（`else` の前）に足す:

```crystal
    it "runs a script before the scripts of each page it loads" do
      with_live_server do |origin|
        with_browser do |browser|
          browser.before_load("window.shomenEarly = document.readyState;")
          browser.visit("#{origin}/phase1/home")
          browser.evaluate("window.shomenEarly").as_s.should eq("loading")
        end
      end
    end

    it "runs a body where waitFor returns at once when the check already holds" do
      with_browser do |browser|
        browser.run("return await waitFor(() => 6 * 7);").as_i.should eq(42)
      end
    end
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `crystal spec spec/shomen/browser_spec.cr`
Expected: コンパイルエラー `undefined method 'before_load' for Browser`。

- [ ] **Step 3: ヘルパーを書く**

`spec/support/browser.cr` の `evaluate` の後に足す:

```crystal
  # Declares waitFor(check): it resolves with check()'s first value other
  # than undefined, looking now and again after every change to the page.
  WAIT_FOR = <<-JS
    const waitFor = (check) => new Promise((resolve) => {
      const first = check();
      if (first !== undefined) return resolve(first);
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

  # Runs body as the inside of an async function, with waitFor declared,
  # and returns its value.
  def run(body : String) : JSON::Any
    evaluate("(async () => {\n#{WAIT_FOR}\n#{body}\n})()")
  end

  # Runs source in each document the page loads from now on, before the
  # document's own scripts.
  def before_load(source : String) : Nil
    command("Page.addScriptToEvaluateOnNewDocument", {source: source})
  end
```

- [ ] **Step 4: 通ることを確かめる**

Run: `crystal spec spec/shomen/browser_spec.cr`
Expected: 4 examples, 0 failures（Chrome が無ければ 1 pending）。

- [ ] **Step 5: フェーズ 4 の決定に CDP のコマンドを足す**

`docs/decisions/20260929-phase4-browser-spec.md` の 7 行目の「`Runtime.evaluate`（`awaitPromise`）、」を「`Runtime.evaluate`（`awaitPromise`）、`Page.addScriptToEvaluateOnNewDocument`（ページのスクリプトより先に動かす。`20260929-phase5-listener-spec.md`）、」にする。

Run: `crystal spec && crystal tool format --check`
Expected: 0 failures、差分なし。

---

### Task 6: shomen.js の SSE

**Files:**
- Modify: `src/shomen/assets/shomen.js`（全体を置き換える）
- Create: `spec/support/page_spy.cr`
- Modify: `spec/support/sse_routes.cr`（`Missing` の後にページとルートを足す）
- Modify: `spec/spec_helper.cr`
- Create: `spec/shomen/sse_script_spec.cr`

**Interfaces:**
- Consumes: Task 3 の `SSERoutes`（`Live`、`TARGET`、`next_render`、`drain_rendered`、`count`、`store=`）、Task 5 の `Browser#before_load`、`Browser#run`。既存の `with_store`、`note`、`with_live_server`、`with_browser`、`/phase4/browser`
- Produces:
  - `shomen.js` の内部関数 `within(root, selector)`、`listen(root)`、`settle(root)`、`replace(current, next)`（Task 7 が `settle` に `mount` を足す）
  - spec: `PAGE_SPY`（`window.shomenSeen.listeners` は `{target, type}` の配列、`window.shomenSeen.sources` は開いた `EventSource` の配列）
  - spec: `SSERoutes::AreaFragment`、`SSERoutes::PageView`、`SSERoutes::Page`（`/phase5/live-page`）、`SSERoutes::Swap`（`/phase5/swap`）

- [ ] **Step 1: ページの記録係を書く**

Create `spec/support/page_spy.cr`:

```crystal
# Runs before the scripts of each page (Browser#before_load) and records
# in window.shomenSeen every addEventListener call and every EventSource
# the page opens. Not strict, so a call on the global object records
# window as its target.
PAGE_SPY = <<-JS
  (() => {
    const seen = {listeners: [], sources: []};
    window.shomenSeen = seen;
    const add = EventTarget.prototype.addEventListener;
    EventTarget.prototype.addEventListener = function (type, listener, options) {
      seen.listeners.push({target: this, type});
      return add.call(this, type, listener, options);
    };
    const Source = window.EventSource;
    window.EventSource = class extends Source {
      constructor(url, init) {
        super(url, init);
        seen.sources.push(this);
      }
    };
  })();
  JS
```

`spec/spec_helper.cr` の `require "./support/island_routes"` の後に足す:

```crystal
require "./support/page_spy"
```

- [ ] **Step 2: SSE のページを足す**

`spec/support/sse_routes.cr` の `class Missing … end` の後（`module` の `end` の前）に足す:

```crystal
  # The holder and a link that replaces it with a new one.
  class AreaFragment < Shomen::Fragment
    def initialize(@count : Int32)
    end

    def content : Nil
      count = @count
      div(id: "area") do
        div(id: "live", "data-shomen-sse": Live.path) do
          p count.to_s, id: "count"
        end
        a "Swap", href: Swap.path, "data-shomen-get": "area", id: "swap"
      end
    end
  end

  class PageView < Shomen::View
    def initialize(@area : AreaFragment)
    end

    def to_html : String
      area = @area
      html lang: "en" do
        head do
          title "Live"
          shomen_script
        end
        body do
          main do
            p "outside", id: "outside"
            embed area
            # Another origin: the page is on 127.0.0.1, and nothing listens on port 1.
            div(id: "far", "data-shomen-sse": "http://localhost:1/phase5/live") do
              p "far", id: "far-count"
            end
          end
        end
      end
    end
  end

  class Page < Shomen::Route
    method GET
    path "/phase5/live-page"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render PageView.new(AreaFragment.new(SSERoutes.count))
    end
  end

  class Swap < Shomen::Route
    method GET
    path "/phase5/swap"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      area = AreaFragment.new(SSERoutes.count)
      return render_fragment(area) if target
      render PageView.new(area)
    end
  end
```

- [ ] **Step 3: 失敗する spec を書く**

Create `spec/shomen/sse_script_spec.cr`:

```crystal
require "../spec_helper"

private def on_live_page(& : Browser, Shomen::Store ->) : Nil
  with_store do |store|
    SSERoutes.store = store
    SSERoutes::TARGET[0] = "count"
    SSERoutes.drain_rendered
    begin
      with_live_server do |origin|
        with_browser do |browser|
          browser.before_load(PAGE_SPY)
          browser.visit("#{origin}#{SSERoutes::Page.path}")
          yield browser, store
        end
      end
    ensure
      SSERoutes.store = nil
    end
  end
end

# Waits until the stream at index has its headers. Its first message is
# on the way, and an append from now on reaches it.
private def wait_open(browser : Browser, index : Int32) : Nil
  browser.run(<<-JS)
    const source = await waitFor(() => window.shomenSeen.sources[#{index}]);
    if (source.readyState !== EventSource.OPEN) {
      await new Promise((resolve) => source.addEventListener("open", resolve, {once: true}));
    }
    return true;
    JS
end

describe "shomen.js with SSE" do
  if Browser.executable
    it "replaces the element a message names inside the holder" do
      on_live_page do |browser, store|
        wait_open(browser, 0)
        browser.evaluate(%(document.getElementById("outside").shomenMarker = "kept"; 0))
        store.append("live-1", 0_i64, note("one"))
        result = browser.run(<<-JS)
          await waitFor(() => document.getElementById("count").textContent === "1" ? true : undefined);
          return {
            marker: document.getElementById("outside").shomenMarker,
            holder: document.getElementById("live").outerHTML,
            path: location.pathname,
          };
          JS
        result["marker"].as_s.should eq("kept")
        result["holder"].as_s.should eq(%(<div id="live" data-shomen-sse="/phase5/live"><p id="count">1</p></div>))
        result["path"].as_s.should eq("/phase5/live-page")
      end
    end

    it "drops a message whose element is outside the holder" do
      on_live_page do |browser, store|
        wait_open(browser, 0)
        SSERoutes.next_render.should eq("count")
        SSERoutes::TARGET[0] = "outside"
        store.append("live-1", 0_i64, note("one"))
        SSERoutes.next_render.should eq("outside")
        SSERoutes::TARGET[0] = "count"
        store.append("live-1", 1_i64, note("two"))
        result = browser.run(<<-JS)
          await waitFor(() => document.getElementById("count").textContent === "2" ? true : undefined);
          return document.getElementById("outside").outerHTML;
          JS
        result.as_s.should eq(%(<p id="outside">outside</p>))
      end
    end

    it "closes the stream of a holder a replacement removed and follows the new one" do
      on_live_page do |browser, store|
        wait_open(browser, 0)
        result = browser.run(<<-JS)
          const old = document.getElementById("live");
          const done = waitFor(() => document.getElementById("live") !== old ? true : undefined);
          document.getElementById("swap").click();
          await done;
          return {count: window.shomenSeen.sources.length, first: window.shomenSeen.sources[0].readyState};
          JS
        result["count"].as_i.should eq(2)
        result["first"].as_i.should eq(2)
        wait_open(browser, 1)
        store.append("live-1", 0_i64, note("one"))
        done = browser.run(%(return await waitFor(() => document.getElementById("count").textContent === "1" ? true : undefined);))
        done.as_bool.should be_true
      end
    end

    it "opens no stream for a holder on another origin" do
      on_live_page do |browser, _|
        paths = browser.evaluate("window.shomenSeen.sources.map((source) => new URL(source.url).pathname)")
        paths.as_a.map(&.as_s).should eq(["/phase5/live"])
      end
    end

    it "opens no stream on a page without data-shomen-sse" do
      with_live_server do |origin|
        with_browser do |browser|
          browser.before_load(PAGE_SPY)
          browser.visit("#{origin}/phase4/browser")
          result = browser.evaluate(<<-JS)
            ({
              sources: window.shomenSeen.sources.length,
              clicks: window.shomenSeen.listeners.filter(({target, type}) => target === document && type === "click").length,
            })
            JS
          result["sources"].as_i.should eq(0)
          result["clicks"].as_i.should eq(1)
        end
      end
    end
  else
    pending("runs in Chrome (set SHOMEN_CHROME to a Chrome or Chromium binary)") { }
  end
end
```

- [ ] **Step 4: 落ちることを確かめる**

Run: `crystal spec spec/shomen/sse_script_spec.cr`
Expected: 最初の 3 例が `no answer from Chrome within 20 seconds`（`EventSource` が開かず `waitFor` が解決しない）で失敗し、"opens no stream for a holder on another origin" は `[]` と `["/phase5/live"]` の違いで失敗する。"opens no stream on a page without data-shomen-sse" はこの時点で通る。

- [ ] **Step 5: shomen.js を書き換える**

`src/shomen/assets/shomen.js` の全体を次にする。フェーズ 4 の振る舞いは変えない。置き換えを `replace` に移し、フォーカスは置き換えの直前に読む（D3）。コメントに `import`、`export` という語を書かない。

```js
// shomen.js: the official JavaScript of Shomen. No build step and no
// dependencies. A link with data-shomen-get or a post form with
// data-shomen-post names the id of an element, and the response replaces
// that element. Without this file the same link and form load a page.
// An element with data-shomen-sse holds an event stream whose fragments
// replace elements inside it.
(() => {
  "use strict";

  const TARGET_HEADER = "Shomen-Target";

  // Targets left busy for a navigation. A page restored from the
  // back-forward cache is not navigating any more.
  const handedOff = new Set();

  // The event source of each data-shomen-sse element in the page.
  const sources = new Map();

  const sameOrigin = (url) => url.origin === location.origin;

  // root when it matches selector, then the elements inside it that do.
  const within = (root, selector) => [
    ...(root.matches(selector) ? [root] : []),
    ...root.querySelectorAll(selector),
  ];

  // Only an HTML response is parsed. Other types, such as JSON, may carry
  // markup from user input.
  const isHTML = (response) => {
    const type = response.headers.get("Content-Type") || "";
    return type.split(";")[0].trim().toLowerCase() === "text/html";
  };

  // Each message is a fragment. It replaces the element with the same id
  // inside the holder; a fragment for any other element is dropped.
  const listen = (root) => {
    within(root, "[data-shomen-sse]").forEach((holder) => {
      if (sources.has(holder)) return;
      const url = new URL(holder.getAttribute("data-shomen-sse"), document.baseURI);
      if (!sameOrigin(url)) return;
      const source = new EventSource(url);
      sources.set(holder, source);
      source.addEventListener("message", (event) => {
        const template = document.createElement("template");
        template.innerHTML = event.data;
        const next = template.content.firstElementChild;
        const current = next && next.id ? document.getElementById(next.id) : null;
        if (current && current !== holder && holder.contains(current)) replace(current, next);
      });
    });
  };

  // Closes the stream of each holder no longer in the page, then starts
  // the streams that root brings.
  const settle = (root) => {
    sources.forEach((source, holder) => {
      if (holder.isConnected) return;
      source.close();
      sources.delete(holder);
    });
    listen(root);
  };

  // Puts next in place of current. When the focus was inside current, it
  // goes to the element with the same id.
  const replace = (current, next) => {
    const active = document.activeElement;
    const focused = active && current.contains(active) ? active.id : "";
    current.replaceWith(next);
    if (focused) document.getElementById(focused)?.focus();
    settle(next);
  };

  // An element of the same id in the response replaces the target. A
  // redirect loads its page. Otherwise a GET loads the URL, and a POST,
  // which must not be sent twice, shows the response as the page.
  const load = async (target, url, init) => {
    target.setAttribute("aria-busy", "true");
    // The old page stays live until a navigation commits, so it keeps the
    // target busy and a second submit still sends nothing.
    let navigating = false;
    try {
      let html;
      // A failed fetch, a failed body read, and a response that is not
      // HTML end the same way: a GET loads the URL, a POST leaves the page.
      try {
        const response = await fetch(url, { ...init, headers: { [TARGET_HEADER]: target.id } });
        if (response.redirected) {
          navigating = true;
          location.assign(response.url);
          return;
        }
        if (!isHTML(response)) throw new TypeError(`${url} did not answer HTML`);
        html = await response.text();
      } catch (error) {
        if (init.method === "GET") {
          navigating = true;
          location.assign(url);
        }
        throw error;
      }
      const template = document.createElement("template");
      template.innerHTML = html;
      const next = template.content.getElementById(target.id);
      if (next) {
        replace(target, next);
      } else if (init.method === "GET") {
        navigating = true;
        location.assign(url);
      } else {
        const page = new DOMParser().parseFromString(html, "text/html");
        document.documentElement.replaceWith(page.documentElement);
        settle(document.documentElement);
      }
    } finally {
      if (navigating) handedOff.add(target);
      else target.removeAttribute("aria-busy");
    }
  };

  addEventListener("pageshow", (event) => {
    if (!event.persisted) return;
    handedOff.forEach((target) => target.removeAttribute("aria-busy"));
    handedOff.clear();
  });

  // Returns the element to replace, or null to leave the event alone. The
  // id goes in a header, so an id that is not printable ASCII is left alone.
  const targetOf = (event, element, name) => {
    const target = document.getElementById(element.getAttribute(name));
    if (!target || !/^[\x21-\x2b\x2d-\x7e]+$/.test(target.id)) return null;
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

  settle(document.documentElement);
})();
```

- [ ] **Step 6: 通ることを確かめる**

Run: `crystal spec spec/shomen/sse_script_spec.cr spec/shomen/script_spec.cr spec/shomen/island_spec.cr`
Expected: 0 failures、Chrome があれば 0 pending。フェーズ 4 の `script_spec.cr` も通る（置き換えとフォーカスの規則は変わっていない）。`island_spec.cr` の "has no npm dependency and stays under 10 KB" も通る（まだ `import(` は無い）。

Run: `wc -c src/shomen/assets/shomen.js && crystal spec && crystal tool format --check`
Expected: 10,240 バイト未満、0 failures、差分なし。

---

### Task 7: shomen.js の島と受入（リスナー）

**Files:**
- Modify: `src/shomen/assets/shomen.js`（定数、`mounted`、`mount`、`settle`、冒頭のコメント）
- Modify: `spec/support/island_routes.cr`
- Create: `spec/shomen/island_script_spec.cr`
- Modify: `spec/shomen/island_spec.cr`（"has no npm dependency and stays under 10 KB" を置き換え、例を 2 つ足す）

**Interfaces:**
- Consumes: Task 4 の `IslandRoutes::CounterIsland`、`spec/support/islands/counter.js`。Task 3 と 6 の `SSERoutes::Live`、`SSERoutes.count`、`SSERoutes.store=`、`SSERoutes::TARGET`。Task 5 の `Browser#run`、`Browser#before_load`。Task 6 の `PAGE_SPY`、`within`、`settle`
- Produces:
  - `shomen.js` の `ISLAND_PATH = "/islands/"`、`ISLAND_NAME`、`mount(root)`
  - spec: `IslandRoutes::CounterFragment`、`IslandRoutes::MoreFragment`、`IslandRoutes::PageView`、`IslandRoutes::Page`（`/phase5/islands`）、`IslandRoutes::More`（`/phase5/islands/more`）

- [ ] **Step 1: 島のページを足す**

`spec/support/island_routes.cr` を次にする:

```crystal
module IslandRoutes
  Shomen::Island.script "counter", "islands/counter.js"

  # An island of the counter module: a count and the button it shows.
  class CounterFragment < Shomen::Fragment
    def initialize(@id : String, @name : String, @start : Int32)
    end

    def content : Nil
      id = @id
      name = @name
      start = @start
      div("data-shomen-island": name, id: id) do
        p start.to_s, id: "#{id}-value"
        button "Add", type: "button", id: "#{id}-add", hidden: "hidden"
      end
    end
  end

  class MoreFragment < Shomen::Fragment
    def content : Nil
      div(id: "more") do
        embed CounterFragment.new("second", "counter", 10)
      end
    end
  end

  class PageView < Shomen::View
    def initialize(@count : Int32)
    end

    def to_html : String
      count = @count
      html lang: "en" do
        head do
          title "Islands"
          shomen_script
        end
        body do
          main do
            # Used as a path, this name would lead to /islands/counter.js.
            embed CounterFragment.new("bad", "counter/../counter", 0)
            embed CounterFragment.new("first", "counter", 0)
            div(id: "more") do
              a "More", href: More.path, "data-shomen-get": "more", id: "more-link"
            end
            div(id: "live", "data-shomen-sse": SSERoutes::Live.path) do
              p count.to_s, id: "count"
            end
          end
        end
      end
    end
  end

  class Page < Shomen::Route
    method GET
    path "/phase5/islands"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render PageView.new(SSERoutes.count)
    end
  end

  class More < Shomen::Route
    method GET
    path "/phase5/islands/more"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      return render_fragment(MoreFragment.new) if target
      render PageView.new(SSERoutes.count)
    end
  end
end
```

- [ ] **Step 2: 失敗するブラウザ spec を書く**

Create `spec/shomen/island_script_spec.cr`:

```crystal
require "../spec_helper"

private def on_islands_page(& : Browser, Shomen::Store ->) : Nil
  with_store do |store|
    SSERoutes.store = store
    SSERoutes::TARGET[0] = "count"
    begin
      with_live_server do |origin|
        with_browser do |browser|
          browser.before_load(PAGE_SPY)
          browser.visit("#{origin}#{IslandRoutes::Page.path}")
          yield browser, store
        end
      end
    ensure
      SSERoutes.store = nil
    end
  end
end

# A promise that resolves once the module of the island id has shown its button.
private def shown(id : String) : String
  %(waitFor(() => document.getElementById("#{id}-add")?.hidden === false ? true : undefined))
end

describe "shomen.js islands" do
  if Browser.executable
    it "runs the module of an island on its element" do
      on_islands_page do |browser, _|
        result = browser.run(<<-JS)
          await #{shown("first")};
          const add = document.getElementById("first-add");
          add.click();
          add.click();
          return document.getElementById("first-value").textContent;
          JS
        result.as_s.should eq("2")
      end
    end

    it "runs the module of an island a replacement brings, once" do
      on_islands_page do |browser, _|
        result = browser.run(<<-JS)
          await #{shown("first")};
          document.getElementById("more-link").click();
          await #{shown("second")};
          document.getElementById("second-add").click();
          return [document.getElementById("second-value").textContent, document.getElementById("first-value").textContent];
          JS
        result.as_a.map(&.as_s).should eq(["11", "0"])
      end
    end

    # Both names resolve to one module, which runs its callers in order,
    # so the bad island would show its button before the first one does.
    it "loads no module for an island name that is not a plain name" do
      on_islands_page do |browser, _|
        result = browser.run(<<-JS)
          await #{shown("first")};
          return document.getElementById("bad-add").hidden;
          JS
        result.as_bool.should be_true
      end
    end

    it "adds no event listener outside an island" do
      on_islands_page do |browser, store|
        browser.run(<<-JS)
          await #{shown("first")};
          document.getElementById("first-add").click();
          document.getElementById("more-link").click();
          await #{shown("second")};
          return true;
          JS
        store.append("islands-1", 0_i64, note("one"))
        result = browser.run(<<-JS)
          await waitFor(() => document.getElementById("count").textContent === "1" ? true : undefined);
          document.getElementById("first-add").click();
          const where = (target) => {
            if (target === window) return "window";
            if (target === document) return "document";
            if (target instanceof EventSource) return "source";
            if (target instanceof Element) {
              return target.closest("[data-shomen-island]") ? "island" : `outside ${target.localName}#${target.id}`;
            }
            return `other ${target}`;
          };
          const seen = window.shomenSeen.listeners.map(({target, type}) => `${where(target)} ${type}`);
          return {seen: [...new Set(seen)].sort(), first: document.getElementById("first-value").textContent};
          JS
        result["seen"].as_a.map(&.as_s).should eq([
          "document click", "document submit", "island click", "source message", "window pageshow",
        ])
        result["first"].as_s.should eq("2")
      end
    end
  else
    pending("runs in Chrome (set SHOMEN_CHROME to a Chrome or Chromium binary)") { }
  end
end
```

- [ ] **Step 3: shomen.js の静的な検査を直す**

`spec/shomen/island_spec.cr` の `it "has no npm dependency and stays under 10 KB" do … end` を次にし、その後に 2 例を足す:

```crystal
  it "has no npm dependency and stays under 10 KB" do
    source = File.read(script_file)
    source.bytesize.should be < 10_240
    source.should_not match(/\bimport\b(?!\()|\bexport\b|\brequire\s*\(/)
    source.scan(/\bimport\(/).size.should eq(1)
    source.should contain(%(import(ISLAND_PATH + name + ".js")))
    File.exists?("package.json").should be_false
    Dir.glob("src/shomen/assets/*").should eq([script_file])
  end

  it "loads island modules from the path the island routes serve" do
    File.read(script_file).should contain(%(const ISLAND_PATH = "/islands/";))
    IslandRoutes::CounterIsland.path.should eq("/islands/counter.js")
  end

  it "sets no on-handler property, so every listener goes through addEventListener" do
    File.read(script_file).should_not match(/\.on[a-z]+\s*=[^=]/)
  end
```

- [ ] **Step 4: 落ちることを確かめる**

Run: `crystal spec spec/shomen/island_script_spec.cr spec/shomen/island_spec.cr`
Expected: ブラウザ spec の 4 例のうち "loads no module…" 以外は `no answer from Chrome within 20 seconds` で失敗する（ボタンが表示されない）。"loads no module…" も同じ理由で失敗する。`island_spec.cr` の "has no npm dependency…" は `import(` が 0 か所で、"loads island modules…" は `ISLAND_PATH` が無いので失敗する。"sets no on-handler property…" は通る。

- [ ] **Step 5: shomen.js に島を足す**

`src/shomen/assets/shomen.js` を次のとおり直す。

冒頭のコメントの最後の 2 行を次にする:

```js
// An element with data-shomen-sse holds an event stream whose fragments
// replace elements inside it, and an element with data-shomen-island runs
// the island module of that name.
```

`const TARGET_HEADER = "Shomen-Target";` の次に足す:

```js
  const ISLAND_PATH = "/islands/";
  const ISLAND_NAME = /^[a-z][a-z0-9-]*$/;
```

`const sources = new Map();` の次に、空行を挟んで足す:

```js
  // Islands whose module has run.
  const mounted = new WeakSet();
```

`listen` の後（`settle` の前）に足す:

```js
  // Runs the module of each island once, with the island. The name must be
  // a plain name, so it cannot lead the path anywhere else.
  const mount = (root) => {
    within(root, "[data-shomen-island]").forEach((island) => {
      const name = island.getAttribute("data-shomen-island");
      if (mounted.has(island) || !ISLAND_NAME.test(name)) return;
      mounted.add(island);
      import(ISLAND_PATH + name + ".js").then((module) => module.default(island));
    });
  };
```

`settle` を次にする:

```js
  // Closes the stream of each holder no longer in the page, then starts
  // the streams and islands that root brings.
  const settle = (root) => {
    sources.forEach((source, holder) => {
      if (holder.isConnected) return;
      source.close();
      sources.delete(holder);
    });
    listen(root);
    mount(root);
  };
```

- [ ] **Step 6: 通ることを確かめる**

Run: `crystal spec spec/shomen/island_script_spec.cr spec/shomen/island_spec.cr spec/shomen/sse_script_spec.cr spec/shomen/script_spec.cr`
Expected: 0 failures、Chrome があれば 0 pending。

Run: `wc -c src/shomen/assets/shomen.js && crystal spec && crystal tool format --check`
Expected: 10,240 バイト未満、0 failures、差分なし。

---

### Task 8: examples/hello の Counter

**Files:**
- Create: `examples/hello/src/counter.js`
- Create: `examples/hello/src/counter.cr`
- Modify: `examples/hello/src/hello.cr:2`
- Create: `examples/hello/spec/counter_spec.cr`

**Interfaces:**
- Consumes: Task 4 の `Shomen::Island.script`、Task 5 の `Browser#run`（`../../../spec/support/browser.cr` から）、Task 7 の `shomen.js` の島
- Produces: `Counter::Show`（`GET /counter`）、`Counter::ShowView`、`Counter::CounterIsland`（`/islands/counter.js`）

- [ ] **Step 1: 失敗する spec を書く**

Create `examples/hello/spec/counter_spec.cr`:

```crystal
require "./spec_helper"
require "http/client"
require "../../../spec/support/browser"

private def get(path : String) : HTTP::Client::Response
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  Shomen::Server.new.call(HTTP::Server::Context.new(HTTP::Request.new("GET", path), response))
  response.close
  HTTP::Client::Response.from_io(IO::Memory.new(io.to_s))
end

describe "Counter island" do
  it "renders the count and a hidden button inside the island" do
    response = get("/counter")
    response.status_code.should eq(200)
    response.body.should contain(%(<script src="/shomen.js" defer></script>))
    response.body.should contain(
      %(<div data-shomen-island="counter" id="counter"><p id="counter-value" aria-live="polite">0</p>) +
      %(<button type="button" id="counter-add" hidden="hidden">Add one</button></div>)
    )
  end

  it "serves the island module" do
    response = get("/islands/counter.js")
    response.status_code.should eq(200)
    response.headers["Content-Type"].should eq("text/javascript; charset=utf-8")
    response.body.should eq(File.read("src/counter.js"))
    Counter::CounterIsland.path.should eq("/islands/counter.js")
  end

  if Browser.executable
    it "counts clicks in the browser" do
      with_live_server do |origin|
        with_browser do |browser|
          browser.visit("#{origin}/counter")
          result = browser.run(<<-JS)
            const add = await waitFor(() => {
              const button = document.getElementById("counter-add");
              return button.hidden ? undefined : button;
            });
            add.click();
            add.click();
            add.click();
            return document.getElementById("counter-value").textContent;
            JS
          result.as_s.should eq("3")
        end
      end
    end
  else
    pending("counts clicks in Chrome (set SHOMEN_CHROME to a Chrome or Chromium binary)") { }
  end
end
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `cd examples/hello && crystal spec spec/counter_spec.cr`
Expected: コンパイルエラー `undefined constant Counter::CounterIsland`。

- [ ] **Step 3: 例を書く**

Create `examples/hello/src/counter.js`:

```js
// The counter island: a number kept in the browser. The server renders the
// count and a hidden button; this module shows the button and listens on it
// alone.
export default (island) => {
  const value = island.querySelector("p");
  const button = island.querySelector("button");
  let count = Number(value.textContent);
  button.addEventListener("click", () => {
    count += 1;
    value.textContent = String(count);
  });
  button.hidden = false;
};
```

Create `examples/hello/src/counter.cr`:

```crystal
module Counter
  Shomen::Island.script "counter", "counter.js"

  class ShowView < Shomen::View
    def to_html : String
      html lang: "en" do
        head do
          title "Counter"
          shomen_script
        end
        body do
          main do
            h1 "Counter"
            # Without JavaScript the button would do nothing, so it stays
            # hidden until the island runs.
            div("data-shomen-island": "counter", id: "counter") do
              p "0", id: "counter-value", "aria-live": "polite"
              button "Add one", type: "button", id: "counter-add", hidden: "hidden"
            end
          end
        end
      end
    end
  end

  class Show < Shomen::Route
    method GET
    path "/counter"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      render ShowView.new
    end
  end
end
```

`examples/hello/src/hello.cr` の `require "./users"` の次に足す:

```crystal
require "./counter"
```

- [ ] **Step 4: 通ることを確かめる**

Run: `cd examples/hello && shards install && crystal spec && crystal tool format --check`
Expected: 0 failures、Chrome があれば 0 pending、差分なし。`git diff --stat examples/hello/shard.lock` が何も出さない（依存は増えていない）。

---

### Task 9: README、CONTRIBUTING、現行フェーズ、最終確認

**Files:**
- Modify: `README.md:7`、`:14`、`:78`、`:113` の後、`:115`
- Modify: `README.ja.md:7`、`:14`、`:78`、`:113` の後、`:115`
- Modify: `CONTRIBUTING.md:47`、`CONTRIBUTING.ja.md:47`
- Modify: `docs/en/02-PHASES.md:9`、`docs/02-PHASES.md:9`

**Interfaces:**
- Consumes: Task 2〜8 の公開 API の名前
- Produces: 文書だけ。コードは変えない

- [ ] **Step 1: README.md を直す**

7 行目を次にする:

```markdown
Version 0.0.0. Phases 1 to 5 are in the tree: typed routes, a typed HTML DSL, an HTTP server, form binding, a signed session cookie, CSRF protection, commands and events, an append-only SQLite event store, in-memory projections, HTML fragments, the official `shomen.js`, JSON responses, SSE, and islands. Later phases are specified and not implemented. There is no release tag yet.
```

14 行目を次にする:

```markdown
- Google Chrome or Chromium, only to run the browser specs (`shomen.js` and the counter of `examples/hello`). Without it they are pending. `SHOMEN_CHROME` names the binary
```

「## Phases 1 to 4 are what run」を「## Phases 1 to 5 are what run」にし、「Phase 4 adds these:」の箇条書きの後に足す:

```markdown
Phase 5 adds these:

- `sse(store) { fragment }`: an event stream. The fragment renders now and again after each append to `store` in this process, and the stream sends its HTML when it changed. With `<div data-shomen-sse="URL">`, `shomen.js` opens the stream, and each fragment replaces the element with the same id inside that element. Appends in other processes reach it in a later phase
- `Shomen::Island.script "name", "file.js"`: reads an ES module of the application at compile time and serves it at `/islands/name.js`. For each element with `data-shomen-island="name"`, `shomen.js` calls the module's default export with the element. The framework adds no event listener to an element outside an island
- In `examples/hello`, `GET /counter` has a counter island
```

「These are specified for later phases …」の行を次にする:

```markdown
These are specified for later phases and are not in the code: Postgres, and running many identical processes on one database.
```

- [ ] **Step 2: README.ja.md を同じ内容で直す**

7 行目:

```markdown
バージョンは 0.0.0 です。リポジトリに入っているのはフェーズ 5 までで、型付きルート、型付き HTML、HTTP サーバ、フォームの束縛、署名付きセッション Cookie、CSRF 対策、コマンドとイベント、追記のみの SQLite イベントストア、メモリ上のプロジェクション、HTML 断片、公式の `shomen.js`、JSON 応答、SSE、島が動きます。それより後のフェーズは仕様にあり、実装はまだありません。リリースタグもまだありません。
```

14 行目:

```markdown
- Google Chrome か Chromium（ブラウザの spec、つまり `shomen.js` と `examples/hello` のカウンターの spec を走らせるときだけ。無ければその spec は pending になります。`SHOMEN_CHROME` で実行ファイルを指定できます）
```

「## いま動くのはフェーズ 1 から 4」を「## いま動くのはフェーズ 1 から 5」にし、「フェーズ 4 で足したもの:」の箇条書きの後に足す:

```markdown
フェーズ 5 で足したもの:

- `sse(store) { 断片 }`: イベントストリームです。断片を今描き、このプロセスで `store` に追記があるたびに描き直し、HTML が変わったときに送ります。`<div data-shomen-sse="URL">` があると `shomen.js` がストリームを開き、断片はその要素の中の同じ `id` の要素を置き換えます。他のプロセスの追記が届くのは後のフェーズです
- `Shomen::Island.script "name", "file.js"`: アプリの ES モジュールをコンパイル時に読み、`/islands/name.js` で配ります。`shomen.js` は `data-shomen-island="name"` の要素ごとに、その要素を渡してモジュールの既定のエクスポートを呼びます。フレームワークは島の外の要素にイベントリスナーを付けません
- `examples/hello` の `GET /counter` にカウンターの島があります
```

115 行目:

```markdown
Postgres と、1 つの DB の上で同じプロセスを多数動かすことは、後のフェーズの仕様であり、コードにはありません。
```

- [ ] **Step 3: CONTRIBUTING を直す**

`CONTRIBUTING.md` の 47 行目を次にする:

```markdown
Specs call the handler directly or build a fixture. They do not bind a fixed public port. The `shomen.js` specs and the counter spec of `examples/hello` serve on an ephemeral port on 127.0.0.1 and drive a headless Chrome. Without Chrome they are pending; `SHOMEN_CHROME` names the binary. The SSE specs read the stream through a pipe.
```

`CONTRIBUTING.ja.md` の 47 行目を次にする:

```markdown
spec はハンドラを直接呼ぶか、フィクスチャをビルドします。固定の公開ポートは取りません。`shomen.js` の spec と `examples/hello` のカウンターの spec は 127.0.0.1 の一時ポートで待ち受け、ヘッドレスの Chrome を動かします。Chrome が無ければ pending になります。`SHOMEN_CHROME` で実行ファイルを指定できます。SSE の spec はストリームをパイプ越しに読みます。
```

- [ ] **Step 4: 手で確かめる**

Run: `cd examples/hello && crystal run src/hello.cr` を別の端末で起動し、次を実行する。

Run: `curl -s localhost:3000/counter | grep -o 'data-shomen-island="counter"' && curl -sI localhost:3000/islands/counter.js | grep -i content-type`
Expected: `data-shomen-island="counter"` と `content-type: text/javascript; charset=utf-8`。ブラウザで `http://127.0.0.1:3000/counter` を開き、「Add one」を押すと数が増える。確かめたらサーバを止める。

- [ ] **Step 5: 受入を 1 つずつ確かめる**

Run: `crystal spec && crystal tool format --check && crystal build src/shomen.cr --error-trace && rm -f shomen && (cd examples/hello && shards install && crystal spec && crystal tool format --check) && git status --short && pgrep -f shomen-chrome`
Expected: 0 failures、0 pending、警告なし。`git status` に `shomen` や `var/`、`.sqlite3` のファイルが無い。`pgrep` が何も出さない（Chrome が残っていない）。

受入との対応:

| 受入 | 確かめる spec |
|---|---|
| SSE を使わないアプリに依存が増えない | `sse_spec.cr` の "adds no shard, so an application without SSE gains no dependency"、`sse_script_spec.cr` の "opens no stream on a page without data-shomen-sse" |
| フレームワークは島の外にイベントリスナーを撒かない | `island_script_spec.cr` の "adds no event listener outside an island"、`island_spec.cr` の "sets no on-handler property…" |
| オプトインの SSE | `sse_spec.cr`、`sse_script_spec.cr` |
| `data-shomen-island` | `island_spec.cr`、`island_script_spec.cr` |
| 島の例（カウンター） | `examples/hello/spec/counter_spec.cr` |

- [ ] **Step 6: 現行フェーズを受入済みにする**

`docs/en/02-PHASES.md` の「## Current phase」の本文の最後の段落を次にする:

```markdown
Phase 5 acceptance is met. Do not implement past this point (phase 6 and later). Wait for the next instruction.
```

`docs/02-PHASES.md` の「## 現行フェーズ」の本文の最後の段落を次にする:

```markdown
フェーズ 5 の受入は満たした。ここより先（フェーズ 6 以降）を実装しない。ユーザーの次指示を待つ。
```

- [ ] **Step 7: 停止する**

フェーズ 5 の受入を満たしたら、AGENTS.md と `docs/en/02-PHASES.md` のとおり停止し、ユーザーの次の指示を待つ。commit はユーザーが頼んだときだけ行う。
