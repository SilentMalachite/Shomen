# 00 指示書 — Shomen

## 結論

Shomen は Crystal 製の Web フレームワークである。既定はサーバーが HTML 文書を返す。JavaScript は島だけ。画面と API の契約はルート宣言ひとつ。ドメインの正本は追記イベント。アクセシビリティの基本違反はコンパイルエラーにする。

最初に作るのは「型付きルート + 型付き HTML + 開発サーバ + spec」まで。ORM 互換、リアルタイム全面、プラグイン機構は作らない。

## 前提

- 言語: Crystal `>= 1.20`
- パッケージ: shards
- テスト: Crystal `spec`
- HTTP: 標準の `HTTP::Server`
- テンプレート文字列（ECR）をビューの正本にしない。HTML は Crystal の式
- 既存フレームワーク（Amber / Lucky / Kemal / Marten / Spider-Gazelle）に依存しない
- 正本は本ファイルと `docs/`。チャットは正本ではない
- 想定利用者: 少人数または一人。業務画面、記録、アクセシビリティが必要なアプリ

## 範囲

### やる（フレームワークとして約束する）

- ルート宣言からハンドラ・path helper・入力型を生成する
- 型付き HTML DSL
- 文書レスポンスと HTML 断片レスポンス
- コンパイル時の最低限 a11y 検査
- 開発サーバ（再コンパイルは手動または簡易 watch でよい。高度な HMR は範囲外）
- コマンド / イベント / リードモデルの最小コア
- SQLite を最初の永続化にする（Postgres アダプタは後のフェーズ）
- セッションクッキーの最小実装
- SSE による任意画面の更新（WebSocket 常時接続は範囲外）
- 島用の公式ランタイムは 1 ファイル、依存ゼロ、10KB 級を目標

### やらない（明示的に除外）

- Rails / Phoenix / Lucky 互換
- GraphQL、tRPC、RSC
- 既定の SPA、クライアントルーター
- 管理画面、テーマエンジン、プラグインマーケット
- Devise 級の巨大認証一式（最小セッションのみ）
- ActiveRecord 的な汎用モデル層を正本にすること
- マイクロサービス前提の分割
- JS バンドラを本体に内蔵すること
- エッジ実行を既定にすること

## 仕様

### 1. パッケージ構成

リポジトリルートはフレームワーク本体。

```
shard.yml
src/shomen.cr                 # ライブラリ入口
src/shomen/
  route.cr
  handler.cr
  html.cr
  a11y.cr
  session.cr
  command.cr
  event.cr
  store.cr
  server.cr
spec/
examples/hello/               # 最小アプリ。本体に機能を置かない
docs/
```

`shard.yml` の name は `shomen`。license は MIT。

本体が初期に依存してよい shard は次だけ。

- なし（フェーズ 0–2）
- `crystal-sqlite3`（フェーズ 3 以降、必要になった時点で追加）

それ以外の shard を足すときは `docs/decisions/` に決定ファイルを書いてから。

### 2. ルート宣言

ルートはクラス 1 つ = エンドポイント 1 つ。マクロまたは注釈で HTTP メソッドと path を固定する。

要求する形（細部の構文は実装側で決めてよいが、意味は変えない）:

```crystal
class Hello::Show < Shomen::Route
  method GET
  path "/"

  struct Input
  end

  def call(input : Input) : Shomen::Response
    render Hello::ShowView.new
  end
end
```

規則:

- 具象ルートクラスは起動時またはコンパイル時に登録される。登録漏れは起動失敗またはコンパイル失敗
- `path` の `:id` は `Input` の同名フィールドに束縛する。型変換に失敗したら 400
- 同じ method + path の二重登録はコンパイル失敗または起動失敗
- path helper はルートクラスから呼べる（例: `Hello::Show.path` → `"/"`）
- レスポンスは HTML 文書または HTML 断片。JSON はフェーズ 4 以降で、ルートが明示したときだけ

### 3. ビュー / HTML

ビューは `Shomen::View` を継承するオブジェクト。`to_html : String` を持つ。

DSL は HTML 要素に対応するメソッドを提供する。最低限:

- 文書: `html`, `head`, `title`, `meta`, `body`
- 文書骨格: `header`, `main`, `footer`, `nav`
- 文書構造: `h1`–`h3`, `p`, `div`, `span`, `ul`, `ol`, `li`, `a`
- フォーム: `form`, `label`, `input`, `button`, `textarea`
- その他: `img`

検査（コンパイル時。マクロで実現）:

- `html` 文書は `lang` 必須
- `button` は `type` 必須（`submit` | `button` | `reset`）
- `img` は `alt` 必須（空文字は可。装飾画像は `alt: ""` を明示）
- `input` は対応する `label`（`for` / ラップ）または `aria-label` が同一ビュー内に無いと失敗
- `html` を返す文書ビューは `title` を 1 つ持つ

生の HTML 文字列埋め込みは `raw` のみ。通常のテキストはエスケープする。

### 4. レスポンス

`Shomen::Response` は少なくとも:

- status
- content_type
- body
- headers

ヘルパ:

- `render(view)` → 200 + `text/html; charset=utf-8`
- `render_fragment(view)` → 200 + 断片。文書の `<html>` を含めない
- `redirect(path, status = 303)`

セキュリティヘッダはサーバ既定で付ける。

- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: no-referrer`
- `X-Frame-Options: DENY`

CSP の厳密化は後のフェーズ。フェーズ 1 では付けてもよいが必須ではない。

### 5. サーバ

`Shomen::Server` は `HTTP::Server` を包む。

- 既定 bind: `127.0.0.1:3000`
- ルート照合 → Input 構築 → `call` → Response 書き出し
- 未照合は 404 の HTML 文書（空の JSON ではない）
- 未処理例外は 500 の HTML 文書。開発時はメッセージを出してよい。本番相当フラグでは出さない

### 6. セッション（フェーズ 2）

- クッキー名: `shomen_session`
- HttpOnly, Secure（HTTPS 時）, SameSite=Lax
- 値は署名付き。秘密鍵は環境変数 `SHOMEN_SECRET`
- 中身は小さな Key-Value。サーバ側ストアは最初メモリでよい
- 認証一式（登録・パスワードリセット・OAuth）は範囲外

### 7. コマンドとイベント（フェーズ 3）

```crystal
struct RenameUser
  include Shomen::Command
  getter user_id : String
  getter name : String
end

struct UserRenamed
  include Shomen::Event
  getter user_id : String
  getter name : String
  getter at : Time
end
```

規則:

- コマンドは検証してイベント列を返す。直接 DB 行を UPDATE する API を公開しない
- イベントは追記のみ。更新・削除 API を持たない
- リードモデルはイベント適用で作る。最初のストアは SQLite 1 ファイル
- テーブル例: `events(id INTEGER PK, type TEXT, payload TEXT, at TEXT)`
- 本文の業務イベントと、フレームワーク内部ログを混ぜない

### 8. 断片更新と島（フェーズ 4–5）

- ルートは通常の HTML 文書のほか、同じ View を断片として返せる
- 公式 JS は `shomen.js` 一つ。属性は `data-shomen-*` のみ
- 既定の輸送は `fetch`。SSE はオプトイン
- WebSocket は作らない
- 島は `data-shomen-island="name"` の要素にだけ JS を載せる

### 9. エラーモデル

ユーザ向け HTML と内部例外を分ける。

- `Shomen::NotFound`
- `Shomen::BadInput`
- `Shomen::Forbidden`（フェーズ 2 以降）

JSON エラー形式はフェーズ 4 まで定義しない。

## TDD

テストは実装より先か、同時。実装だけ先に置いてテスト無しでフェーズを完了扱いにしない。

必須 spec（フェーズ 0–1）:

1. ルート `GET /` が 200 と HTML を返す
2. 未知 path が 404 HTML を返す
3. HTML 特殊文字がエスケープされる
4. `button` に `type` が無いビューはコンパイルに失敗する（`crystal build` の失敗を検証するか、マクロ spec で検証）
5. path helper が宣言どおりの文字列を返す
6. 二重ルート登録が失敗する

後のフェーズのテストは `docs/02-PHASES.md` の受入条件に書く。

テストから本物のネットワークポートを独占しない。`HTTP::Server` は ephemeral port か、ハンドラを直接呼ぶ。

## 制約

- 追加の「設計改善」より、受入条件を最短で満たす
- 公開 API は `Shomen::` 配下に限定する
- ファイル名は機能名と一致させる
- カラーコードやデザイントークン機構をフェーズ 0–3 で作らない
- 国際化機構をフェーズ 0–3 で作らない。文書 `lang` はビューが明示する
- Windows 専用 API を使わない
- 依存のバージョンは shard.yml に下限を書く

## 受入条件（全体の完了定義ではない。リポジトリとして歩き出せること）

指示書としての完成条件:

- [ ] `AGENTS.md` と `CLAUDE.md` が同じ正本を指す
- [ ] フェーズ 0 をエージェントが迷わず始められる
- [ ] 除外事項が書いてある
- [ ] 言語・テスト・ディレクトリが固定されている

フレームワーク実装の完了条件は `docs/02-PHASES.md` の各フェーズをすべて満たしたとき。
