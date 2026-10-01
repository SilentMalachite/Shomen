# 00 指示書 — Shomen

> 日本語訳です。正本は [docs/en/00-INSTRUCTION.md](en/00-INSTRUCTION.md) です。食い違ったら英語に合わせ、このファイルを直します。

## 結論

Shomen は Crystal 製の Web フレームワークである。既定はサーバーが HTML 文書を返す。JavaScript は島だけ。画面と API の契約はルート宣言ひとつ。ドメインの正本は追記イベント。アクセシビリティの基本違反はコンパイルエラーにする。アプリは、同じプロセスを増やして 1 つの DB の上で規模を広げる。

最初に作るのは「型付きルート + 型付き HTML + 開発サーバ + spec」まで。ORM 互換、リアルタイム全面、プラグイン機構は作らない。

## 前提

- 言語: Crystal `>= 1.20`
- パッケージ: shards
- テスト: Crystal `spec`
- HTTP: 標準の `HTTP::Server`
- テンプレート文字列（ECR）をビューの正本にしない。HTML は Crystal の式
- 既存フレームワーク（Amber / Lucky / Kemal / Marten / Spider-Gazelle）に依存しない
- 仕様の正本は `docs/en/00-INSTRUCTION.md` と `docs/en/`。このファイルは日本語訳。チャットは正本ではない
- 想定用途: 業務画面、記録、アクセシビリティが必要なアプリ。アプリは SQLite の 1 プロセスで始まり、ロードバランサの後ろに並ぶ同じプロセス群と、Postgres の primary とその replica まで育つ。その途中でルート、ビュー、コマンド、イベントは変わらない
- 規模の広げ方: 1 つのアプリとしてデプロイし、サービスに分けない。プロセスは、他のプロセスが必要とする状態を持たない。セッションは署名付きクッキー、事実は DB にある。アプリが必要とする裏側のサービスは DB だけ。複数ホストになったら前段にロードバランサを置く（`docs/decisions/20260929-scale-target.md`）

## 範囲

### やる（フレームワークとして約束する）

- ルート宣言からハンドラ・path helper・入力型を生成する
- 型付き HTML DSL
- 文書レスポンスと HTML 断片レスポンス
- コンパイル時の最低限 a11y 検査
- 開発サーバ（再コンパイルは手動または簡易 watch でよい。高度な HMR は範囲外）
- コマンド / イベント / リードモデルの最小コア
- SQLite を最初の永続化にし、複数プロセスには Postgres を使う（フェーズ 6）
- セッションクッキーの最小実装
- SSE による任意画面の更新（WebSocket 常時接続は範囲外）
- 島用の公式ランタイムは 1 ファイル、依存ゼロ、10KB 級を目標
- 1 つの DB の上で同じプロセスを多数動かす（フェーズ 6–7）: 必須の秘密鍵、ポート共有、グレースフルシャットダウン、非同期のイベントコンシューマ、プロセス間の通知、HTTP キャッシュ、replica からの読み取り

### やらない（明示的に除外）

- Rails / Phoenix / Lucky 互換
- GraphQL、tRPC、RSC
- 既定の SPA、クライアントルーター
- 管理画面、テーマエンジン、プラグインマーケット
- Devise 級の巨大認証一式（最小セッションのみ）
- ActiveRecord 的な汎用モデル層を正本にすること
- マイクロサービス前提の分割
- DB 以外に必須の裏側のサービス（Redis、メッセージブローカ、専用キャッシュなど）
- DB のシャーディング、複数リージョンからの書き込み
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
  router.cr
  response.cr
  sse.cr                      # フェーズ 5
  view.cr
  fragment.cr
  html.cr
  a11y.cr
  session.cr
  command.cr
  event.cr
  store.cr
  projection.cr
  consumer.cr                 # フェーズ 7
  island.cr
  assets/shomen.js
  server.cr
spec/
examples/hello/               # 最小アプリ。本体に機能を置かない
docs/
```

`shard.yml` の name は `shomen`。license は MIT。

本体が初期に依存してよい shard は次だけ。

- なし（フェーズ 0–2）
- `crystal-sqlite3`（shard 名 `sqlite3`）と、その土台の `crystal-db`（shard 名 `db`）（フェーズ 3 以降、必要になった時点で追加）
- `crystal-pg`（shard 名 `pg`）（フェーズ 6 以降、`docs/decisions/20260929-scale-postgres-shard.md`）

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
- レスポンスは HTML 文書または HTML 断片。JSON はルートが `json` で明示したときだけ（フェーズ 4）

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
- `json(value, status = 200)` → `application/json` + `value.to_json`。サーバが自分で JSON を選ぶことはない
- `sse(store, heartbeat = 15.seconds) { 断片 }` → イベントストリーム（`text/event-stream`）。断片を今描き、`store` への追記のたびに描き直し、HTML が変わったときだけ送る。このプロセスの追記に加え、ほかのプロセスの追記も通知とポーリングで届く（`docs/decisions/20260929-phase5-sse-response.md`、`docs/decisions/20261001-phase7-append-watcher.md`）
- `redirect(path, status = 303)`

セキュリティヘッダはサーバ既定で付ける。

- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: no-referrer`
- `X-Frame-Options: DENY`

フェーズ 6 からは `Content-Security-Policy: default-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'` も付ける。ルートの応答がすでに `Content-Security-Policy` を持っていれば、そちらを残す（`docs/decisions/20260929-phase6-csp.md`）。

### 5. サーバ

`Shomen::Server` は `HTTP::Server` を包む。

- 既定 bind: `127.0.0.1:3000`
- ルート照合 → Input 構築 → `call` → Response 書き出し
- 未照合は 404 の HTML 文書（空の JSON ではない）
- 未処理例外は 500 の HTML 文書。開発時はメッセージを出してよい。`SHOMEN_ENV=production` では文書に出さない。例外は環境によらずログに書く（フェーズ 6、`docs/decisions/20260929-phase6-production.md`）
- 1 ホスト上の同じプロセス群は `reuse_port: true` でポートを共有する（フェーズ 6、`docs/decisions/20260929-scale-reuse-port.md`）
- SIGTERM または SIGINT を受けたら、新しい接続を受けるのをやめ、待機中のキープアライブ接続を閉じ、処理中の要求を上限時間内に `Connection: close` 付きで終えてから終了する（フェーズ 6、`docs/decisions/20260929-scale-graceful-shutdown.md`）

### 6. セッション（フェーズ 2）

- クッキー名: `shomen_session`
- HttpOnly, Secure（HTTPS 時）, SameSite=Lax
- 値は署名付き。秘密鍵は環境変数 `SHOMEN_SECRET`。`SHOMEN_ENV=production` のとき、未設定か 32 バイト未満なら起動に失敗する（フェーズ 6、`docs/decisions/20260929-scale-production-secret.md`）。production 以外では、未設定ならランダムな鍵を使う（`docs/decisions/20260929-phase2-secret-fallback.md`）
- `SHOMEN_SECRET_VERIFY` を設定すると、署名には使わず検証だけに使う 2 つ目の鍵になる。クッキーと CSRF トークンを検証する。この鍵で通ったクッキーは `SHOMEN_SECRET` で出し直す。鍵の入れ替えは 3 回のデプロイで行う。切れるのは、2 回目と 3 回目の間に使われなかったセッションと、2 回目より前に描画されて 3 回目の時点でまだ送信されていないフォームだけ（フェーズ 6、`docs/decisions/20260929-scale-secret-rotation.md`）
- 中身は小さな Key-Value。署名付きクッキーか DB に置き、1 プロセスのメモリには置かない。フェーズ 2 のセッションが持つのは id と、id から導ける値（CSRF トークン）だけ。map は、上限と期限とあわせて、ルートがセッションへ値を書く API を入れるときに置く（`docs/decisions/20260929-phase2-session-store.md`）
- 2 つ目の署名付きクッキー `shomen_append` が、セッションが最後に追記した `id` を 60 秒覚える。追記するルートは `remember store.append(...)` と書き、セッションが覚えている `id` を `must_see` で読む（フェーズ 7、`docs/decisions/20261001-phase7-remember-append.md`）
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
- イベントは 1 つのストリームに属する。ストリームは時間とともに変わる 1 つの対象（1 人のユーザーなど）。名前は文字列（`"user-42"`）
- ストリームのイベントは `version` で 1 から数える。追記は、ストリームがいまどの版にあると期待するかを渡す。ストリームがそれ以外の版にあれば、何も書かずに `Shomen::Conflict` を投げる。ストアは再試行しない（`docs/decisions/20260929-scale-event-stream.md`）
- `id` はストリームをまたいだ順序。`id` N まで読んだ読み手が、後から `id` が N 以下の新しいイベントを見つけることはない
- 保存済みのイベントは書き換えない。形を変えるときは、新しいイベント型か、既定値のあるフィールドを足す。`type` 列にはイベント型が宣言する名前を入れる。Crystal の型名を変えても保存済みの行は読める（`docs/decisions/20260929-scale-event-evolution.md`）
- リードモデルはイベント適用で作る。最初のストアは SQLite 1 ファイル
- プロジェクションがリードモデルを作る。`id` 順にイベントを適用し、最後に適用した `id` をチェックポイントとして持つ。メモリ上のプロジェクションは、ビューが読む前に、チェックポイントより後のイベントをすべて適用して追いつく。そのため、別のプロセスが追記したイベントも見える。表に置いたプロジェクション（フェーズ 7）はコンシューマが更新し、読む側はそれを待つ（仕様 10）（`docs/decisions/20260929-scale-projection-checkpoint.md`）
- テーブル（Postgres では整数の列を `BIGINT` にし、どちらのアダプタも `Int64` で読む）:

  ```
  events(
    id      INTEGER PRIMARY KEY,  -- ストリームをまたいだ順序、Int64
    stream  TEXT    NOT NULL,
    version INTEGER NOT NULL,
    type    TEXT    NOT NULL,
    payload TEXT    NOT NULL,     -- JSON
    at      TEXT    NOT NULL,     -- UTC、RFC 3339
    UNIQUE (stream, version)
  )
  ```

- 本文の業務イベントと、フレームワーク内部ログを混ぜない

### 8. 断片更新と島（フェーズ 4–5）

- ルートは通常の HTML 文書のほか、同じ View を断片として返せる
- 公式 JS は `shomen.js` 一つ。属性は `data-shomen-*` のみ
- 既定の輸送は `fetch`。SSE はオプトイン: GET のルートが `sse` で答え、`data-shomen-sse="URL"` の要素がその断片を受け取る。断片は、その要素の中の同じ `id` の要素を置き換える（フェーズ 5、`docs/decisions/20260929-phase5-sse-script.md`）
- WebSocket は作らない
- 島は `data-shomen-island="name"` の要素にだけ JS を載せる。`Shomen::Island.script "name", "file.js"` がアプリのモジュールを `/islands/name.js` で配り、`shomen.js` がその要素を渡して既定のエクスポートを呼ぶ（フェーズ 5、`docs/decisions/20260929-phase5-island-script.md`）

### 9. エラーモデル

ユーザ向け HTML と内部例外を分ける。

- `Shomen::NotFound`
- `Shomen::BadInput`
- `Shomen::Forbidden`（フェーズ 2 以降）
- `Shomen::Conflict`（フェーズ 3 以降）。捕まえられなければ 409 の HTML 文書
- `Shomen::Unavailable`（フェーズ 7 以降）。見る必要がある `id` に上限時間内に届かない読みが投げる。捕まえられなければ 503 の HTML 文書

エラーは、JSON を返すルートでも HTML 文書で返す。JSON のエラー形式は無い（`docs/decisions/20260929-phase4-json-response.md`）。

### 10. スケールアウト（フェーズ 6–7）

- 同じプロセス群をロードバランサの後ろに並べる。どのプロセスもどの要求を受けてよい
- 各プロセスは、上限つきの DB 接続プールを持つ。大きさは DB の URL で決める
- コンシューマは、要求の外で動くプロジェクションまたは反応。チェックポイントより後のイベントをバッチで読む。バッチは、DB への書き込みと新しいチェックポイントを 1 トランザクションでコミットし、それは先に別のプロセスがチェックポイントを動かしていないときだけ行う。そのため、2 つのプロセスが同じイベントを DB に適用することはない。Postgres ではバッチの間チェックポイント行をロックする。SQLite では副作用を先に実行し、その後の短い書き込みトランザクションでチェックポイントを比べる。DB の外への副作用（メール、HTTP 呼び出しなど）は少なくとも 1 回実行されるので、反応は繰り返しに耐える（`docs/decisions/20260929-scale-consumers.md`）
- バッチの途中でプロセスが死んだら、そのトランザクションは巻き戻り、別のプロセスが保存済みのチェックポイントから続ける
- イベントで失敗したコンシューマは、間隔を伸ばしながら再試行し、そのイベントを飛ばさない。ほかのコンシューマは進む
- `Shomen::Consumer` は両方を表す 1 つの型。`name` がチェックポイントの行を名指す。`write(recorded, connection)` はバッチのトランザクションの中でコンシューマの表に書き、`react(recorded)` は副作用を実行し、`create_tables(connection)` は表を 1 回だけ作る。アプリは `Shomen::Server.start` の前に `start` を呼び、`start` から戻った後、Store を閉じる前に `stop` を呼ぶ。SQLite と Postgres の両方で動かす SQL は、パラメータを `$1`、`$2`、… と初出の順に番号付けする（`docs/decisions/20261001-phase7-consumer-api.md`、`docs/decisions/20261001-phase7-consumer-batch.md`）
- 追記がコミットされたら、Postgres アダプタは新しい最大の `id` を載せた通知を送る。すべてのプロセスのコンシューマと SSE ストリームがそれで起きる。それぞれ一定間隔でもポーリングするので、通知が落ちても遅れるだけで済む。SQLite には通知が無く、ポーリングだけを使う（`docs/decisions/20260929-scale-notify.md`）。プロセスは、ある DB への追記を何かが初めて待ったときに、その DB の通知の受信とポーリングを始め、それを始めた Store が閉じたときに止める。プロセスは DB ごとに 1 回だけポーリングし、間隔は待ちを始めた Store の `poll_interval`（`Shomen::Store.new(url, poll_interval: 5.seconds)`）にする（`docs/decisions/20261001-phase7-append-watcher.md`、`docs/decisions/20261001-phase7-notify-channel.md`）
- 表に置いたプロジェクションを更新するのは、そのコンシューマだけ。ある `id` を見る必要がある要求は、そのプロジェクションのチェックポイントがそこへ届くまで、上限つきで待つ。上限を過ぎたら、古い状態を見せずに `Shomen::Unavailable` を投げる。セッションはその `id` を一定時間後に忘れるので、1 つのイベントが詰まっても、その後のすべてのページが使えなくなることはない。`consumer.read(id, within: 2.seconds) { |connection| … }` はチェックポイントを待ってから、読むための接続を渡す（`docs/decisions/20261001-phase7-consumer-read.md`）
- 読みは replica に回してよい。要求がイベントを追記したら、セッションがその追記の `id` を覚えている間、同じセッションの後の要求は、どのプロセスが受けても、その追記より古い状態を見せない。上の待ち方を使い、replica が遅れたままなら primary から読む（`docs/decisions/20260929-scale-read-your-writes.md`）。`Shomen::Store.new(url, replica: replica_url)` はその読みを Postgres の replica に回す。`projection.catch_up(must_see)` と `consumer.read(must_see) { |connection| … }` が replica を待つ（`docs/decisions/20261001-phase7-replica.md`）
- GET ルートは検証子（`Input` とリードモデルから作る文字列）を返せる。サーバはそれにビルド ID とセッションの CSRF トークンを合わせて弱い `ETag` として送り、`If-None-Match` が一致したらビューを呼ばずに 304 を返す（`docs/decisions/20260929-scale-etag.md`）。ルートは `def validator(input : Input) : String` を定義し、定義できるのは GET ルートだけ。サーバは `call` の前にそれを呼び、ビルド ID はコンパイルのたびに変わる（`docs/decisions/20261001-phase7-etag.md`）
- 描画した断片は、プロセス内の上限つきキャッシュに置ける。キーには、断片が依存するものをすべて含める。入力、見る人によって中身が変わるなら見る人、表示するデータとともに変わる値（ストリームの版やプロジェクションのチェックポイントなど）である。手で無効化するものは無い。キャッシュはプロセス内の全セッションが共有するので、いまの CSRF トークンを含む断片をキャッシュしようとすると例外になる（`docs/decisions/20260929-scale-fragment-cache.md`）。`Shomen::FragmentCache.new(max_bytes:)` が置くバイト数の上限を決め、ルートは `cached(cache, name, *key) { fragment }` を呼ぶ（`docs/decisions/20261001-phase7-fragment-cache.md`）
- シャーディング、複数リージョンからの書き込み、予約実行と遅延実行のジョブは、この節に含めない

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
