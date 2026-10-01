# Shomen

[![CI](https://github.com/SilentMalachite/Shomen/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/SilentMalachite/Shomen/actions/workflows/ci.yml)
[![Crystal](https://img.shields.io/badge/Crystal-%3E%3D%201.20-000000?logo=crystal&logoColor=white)](https://crystal-lang.org/)

[English](README.md) | [日本語](README.ja.md)

Shomen は Crystal の Web フレームワークです。サーバが HTML 文書を返し、画面の契約はルート宣言ひとつに置きます。基本的なアクセシビリティ違反は、実行前のコンパイルで失敗します。

バージョンは 0.0.0 です。リポジトリに入っているのはフェーズ 6 までで、型付きルート、型付き HTML、HTTP サーバ、フォームの束縛、署名付きセッション Cookie、CSRF 対策、コマンドとイベント、SQLite か Postgres の上の追記のみのイベントストア、メモリ上のプロジェクション、HTML 断片、公式の `shomen.js`、JSON 応答、SSE、島、本番に要るもの（必須の鍵、Content-Security-Policy、ポートの共有、グレースフルシャットダウン）が動きます。フェーズ 7 は始まっていて、追記がすべてのプロセスの SSE を起こします。フェーズ 7 の残りは仕様にあり、実装はまだありません。リリースタグもまだありません。

## 必要なもの

- Crystal 1.20 以上
- shards
- SQLite 3 のライブラリ（`libsqlite3`）
- Postgres（使うアプリと、Postgres の spec を走らせるときだけ）
- Google Chrome か Chromium（ブラウザの spec、つまり `shomen.js` と `examples/hello` のカウンターの spec を走らせるときだけ。無ければその spec は pending になります。`SHOMEN_CHROME` で実行ファイルを指定できます）

フレームワーク本体の shard は、crystal-lang の `sqlite3` と `db`、will/crystal-pg の `pg` に依存します。`pg` は Crystal で書かれていて、C のライブラリは要りません。

## サンプルを動かす

```sh
cd examples/hello
shards install
crystal run src/hello.cr
```

<http://127.0.0.1:3000> を開きます。`GET /` は `<h1>Hello</h1>` を含む文書を返します。

## アプリから使う

`shard.yml`:

```yaml
dependencies:
  shomen:
    github: SilentMalachite/Shomen
    branch: main
```

`examples/hello` は公開ブランチではなく、隣のチェックアウトを `path: ../..` で参照します。

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

`Hello::Show.path` は `"/"` を返します。テキストはエスケープされます。`html` には `"en"` のような `lang` の文字列リテラルが必要で、文書中の `title` はちょうど 1 つです。`button` の `type` は `"submit"`、`"button"`、`"reset"` のいずれかです。`img` には `alt` の文字列リテラルが必要で、装飾画像は `alt: ""` と書きます。

サーバの待受は `127.0.0.1:3000` です。一致したルートは 200 の HTML、パスパラメータの変換失敗は 400、未知のパスと `Shomen::NotFound` は 404 の HTML、処理されない例外はメッセージをエスケープした 500 の HTML です。`SHOMEN_ENV=production` ではメッセージを出しません。例外は環境によらず `Log` の `shomen` に書きます。すべての応答に `X-Content-Type-Options: nosniff`、`Referrer-Policy: no-referrer`、`X-Frame-Options: DENY`、`Content-Security-Policy`（下のフェーズ 6）が付きます。

## いま動くのはフェーズ 1 から 6

フェーズ 1 で入っているもの:

- 仕様にある HTML 要素と、テキストのエスケープ
- `html` の `lang`、`title` が 1 つ、`button` の `type`、`img` の `alt` というコンパイル時検査
- ルート宣言、登録、path helper
- 200 / 400 / 404 / 500
- `examples/hello`

フェーズ 2 で足したもの:

- urlencoded の form POST から `Input` のフィールドを組む。欠けたフィールドや不正な値は 400
- フォームを描き直すための `render(view, status: 422)`
- 署名付きの `shomen_session` Cookie。鍵は `SHOMEN_SECRET` で、未設定なら再起動まで有効なランダムな鍵を使う。サーバはセッションの状態を持たないので、鍵を固定すれば再起動してもセッションが続く。HTTPS の後ろで動かすときは `Shomen::Server.start(https: true)` で起動すると、Cookie に `Secure` も付く
- セッションに入った CSRF トークン。`csrf_field(csrf_token)` でフォームに書く。一致する `_csrf` が無い POST、PUT、PATCH、DELETE は 403
- 1 MiB を超えるフォーム本文は 413
- すべての `input` に、同じビューの中のラベルを求めるコンパイル時検査。`for:` が `input` の `id:` と一致する `label`（どちらも文字列リテラル）、囲む `label`、空でない `"aria-label"` か `"aria-labelledby"` のいずれか。ビューの別メソッド、親のビュー、include したモジュールも数える。`type: "hidden"` は対象外。送信には `button` を使う
- `examples/hello` の `GET /greeting`、`POST /greeting`、`GET /greeting/:name`

フェーズ 3 で足したもの:

- `Shomen::Event`: `event_type "name"` を宣言する struct。名前は `type` 列に入るので、Crystal の型名を変えても古い行を読めます。名前の書き忘れと重複はコンパイルエラーです
- `Shomen::Command`: `call` は `Array(Shomen::Event)` か、422 のフォームに出すメッセージを持つ `Shomen::Rejected` を返します
- `Shomen::Store.new("sqlite3://./var/shomen.sqlite3")`: `append(stream, expected_version, events)` と `read(after:, limit:)`。ファイルは WAL です。ストリームの現在の版と違う版での追記は、何も書かずに `Shomen::Conflict` を投げます。捕まえなかった衝突は 409 の HTML 文書になります
- `Shomen::Projection`: 各イベントを `apply` します。`catch_up` はチェックポイントより後のイベントを、別のプロセスが追記したものも含めて適用します。ビューが読む前に呼び、起動時の再構築には `Shomen::Server.start` の前に 1 回呼びます
- `examples/hello` の `GET /users/:id/edit`、`POST /users/:id`、`GET /users/:id`

フェーズ 4 で足したもの:

- `Shomen::Fragment`: 要素 1 つのビュー。`content` を実装します。中で `html` を書くとコンパイルエラーです。文書ビューには `embed` で埋め込みます
- `render_fragment(fragment)`: 断片だけを返します。`render` に断片を渡すとコンパイルエラーです
- `/shomen.js` で配る `shomen.js`。`script` 要素は `shomen_script` が書きます。`<a href="..." data-shomen-get="ID">` と `<form method="post" action="..." data-shomen-post="ID">` は `Shomen-Target: ID` ヘッダを付けて fetch し、その `id` の要素を差し替えます。リダイレクトは新しいページを読み込みます。JavaScript が無ければ、同じリンクとフォームが今までどおりページを読み込みます
- `target`: `Shomen-Target` の `id`、無ければ `nil`。ルートは `target ? render_fragment(...) : render(...)` で答えます。すべての応答に `Vary: Shomen-Target` が付きます
- `json(value, status = 200)`: `application/json` を返します。サーバが自分で JSON を選ぶことはなく、エラーは HTML 文書のままです
- `examples/hello` の挨拶フォームは断片です。「Change」でその場にフォームが開き、422 ではフォームだけが差し替わります

フェーズ 5 で足したもの:

- `sse(store) { 断片 }`: イベントストリームです。断片を今描き、このプロセスで `store` に追記があるたびに描き直し、HTML が変わったときに送ります。`<div data-shomen-sse="URL">` があると `shomen.js` がストリームを開き、断片はその要素の中の同じ `id` の要素を置き換えます。他のプロセスの追記も届きます（下のフェーズ 7）
- `Shomen::Island.script "name", "file.js"`: アプリの ES モジュールをコンパイル時に読み、`/islands/name.js` で配ります。`shomen.js` は `data-shomen-island="name"` の要素ごとに、その要素を渡してモジュールの既定のエクスポートを呼びます。フレームワークは島の外の要素にイベントリスナーを付けません
- `examples/hello` の `GET /counter` にカウンターの島があります

フェーズ 6 で足したもの:

- `Shomen::Store.new("postgres://localhost/app")`: 同じストアを Postgres の上で使います。URL のスキームで SQLite（`sqlite3`）か Postgres（`postgres`、`postgresql`）を選び、コマンド、イベント、プロジェクションは変わりません。追記は 1 つのアドバイザリロックを取るので、id は順に見えます。URL に `max_pool_size` が無ければ、1 プロセスの接続は 10 本までです
- `SHOMEN_ENV=production`: `SHOMEN_SECRET` が 32 バイト以上でなければ起動に失敗し、500 では例外のメッセージを出しません
- `SHOMEN_SECRET_VERIFY`: 検証だけに使う 2 つ目の鍵です。この鍵で通った Cookie は `SHOMEN_SECRET` で出し直し、どちらの鍵で描いたフォームも送れます。鍵の入れ替えは 3 回のデプロイで行います。新しい鍵を `SHOMEN_SECRET_VERIFY` に入れる、2 つを入れ替える、`SHOMEN_SECRET_VERIFY` を消す、の順です
- すべての応答に `Content-Security-Policy: default-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; object-src 'none'` が付きます。ルートが自分で `Content-Security-Policy` を付けた応答は、その値のままです
- `Shomen::Server.start(reuse_port: true)`: 1 ホストの複数のプロセスが 1 つのポートを共有します。Linux では `net.ipv4.tcp_migrate_req=1` を設定すると、止まるプロセスで待っている接続がほかのプロセスへ移ります
- SIGTERM か SIGINT を受けると、サーバは受け付けをやめ、アイドルの接続と SSE を閉じ、処理中の要求を `Connection: close` 付きで終えます。`start` は `shutdown_timeout`（既定 25 秒）以内に戻ります。2 回目の合図でプロセスはすぐ終わります
- `examples/hello` は SQLite のままです。`HELLO_DATABASE_URL=postgres://localhost/hello crystal run src/hello.cr` で、既存の Postgres の DB の上で動きます

フェーズ 7 でここまでに足したもの:

- どのプロセスで追記しても、すべてのプロセスの `sse` と `wait_for_append` が起きます。Postgres では追記が通知を送り、待っているプロセスはプールの外の専用の接続 1 本でそれを受けます。プロセスは DB ごとに最大の id をポーリングするので（既定 5 秒。待ちを始めた Store を `Shomen::Store.new(url, poll_interval:)` で作れば変えられます）、通知が落ちても遅れるだけです。SQLite はポーリングだけを使います。受信とポーリングは、その Store で何かが待ってから始まります

フェーズ 7 の残りは仕様にあり、コードにはありません。要求の外で動くコンシューマ、HTTP キャッシュ、replica からの読み出しです。

フェーズの一覧は [docs/en/02-PHASES.md](docs/en/02-PHASES.md) にあります。日本語訳は [docs/02-PHASES.md](docs/02-PHASES.md) です。

## 仕様

正本は英語です。

| | English | 日本語 |
|---|---|---|
| 仕様 | [docs/en/00-INSTRUCTION.md](docs/en/00-INSTRUCTION.md) | [docs/00-INSTRUCTION.md](docs/00-INSTRUCTION.md) |
| 構造 | [docs/en/01-ARCHITECTURE.md](docs/en/01-ARCHITECTURE.md) | [docs/01-ARCHITECTURE.md](docs/01-ARCHITECTURE.md) |
| フェーズ | [docs/en/02-PHASES.md](docs/en/02-PHASES.md) | [docs/02-PHASES.md](docs/02-PHASES.md) |
| 規約 | [docs/en/03-CONVENTIONS.md](docs/en/03-CONVENTIONS.md) | [docs/03-CONVENTIONS.md](docs/03-CONVENTIONS.md) |

決定ログは日本語のまま [docs/decisions/](docs/decisions/) に置きます。

## 開発

手順は [CONTRIBUTING.ja.md](CONTRIBUTING.ja.md) です。リポジトリ直下では次を実行します。

```sh
shards install
crystal spec
crystal build src/shomen.cr --error-trace
cd examples/hello && shards install && crystal spec
```

`SHOMEN_SPEC_POSTGRES` が無いと、Postgres の spec は pending になります。走らせるときは、DB を作れるユーザーの Postgres の URL を入れます（例 `SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec`）。例ごとに DB を作り、終わったら消します。

GitHub Actions（[`.github/workflows/ci.yml`](.github/workflows/ci.yml)）は、すべてのプルリクエストと `main` への push で、`crystal tool format --check`、ビルド、Postgres 17 のサービスとヘッドレスの Chrome を使った `crystal spec`（pending になる spec はありません）、`examples/hello` の spec を走らせます。

`crystal build` は `./shomen` を書き出します。このバイナリはコミットしません。

## ライセンス

[MIT](LICENSE)。Copyright 2026 Silent Malachite。条文の正本は英語の LICENSE です。
