# Shomen

[English](README.md) | [日本語](README.ja.md)

Shomen は Crystal の Web フレームワークです。サーバが HTML 文書を返し、画面の契約はルート宣言ひとつに置きます。基本的なアクセシビリティ違反は、実行前のコンパイルで失敗します。

バージョンは 0.0.0 です。リポジトリに入っているのはフェーズ 2 までで、型付きルート、型付き HTML、HTTP サーバ、フォームの束縛、署名付きセッション Cookie、CSRF 対策が動きます。それより後のフェーズは仕様にあり、実装はまだありません。リリースタグもまだありません。

## 必要なもの

- Crystal 1.20 以上
- shards

フレームワーク本体の shard に依存パッケージはありません。

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

サーバの待受は `127.0.0.1:3000` です。一致したルートは 200 の HTML、パスパラメータの変換失敗は 400、未知のパスと `Shomen::NotFound` は 404 の HTML、処理されない例外はメッセージをエスケープした 500 の HTML です。すべての応答に `X-Content-Type-Options: nosniff`、`Referrer-Policy: no-referrer`、`X-Frame-Options: DENY` が付きます。

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
- 署名付きの `shomen_session` Cookie。鍵は `SHOMEN_SECRET` で、未設定なら再起動まで有効なランダムな鍵を使う。サーバはセッションの状態を持たないので、鍵を固定すれば再起動してもセッションが続く。HTTPS の後ろで動かすときは `Shomen::Server.start(https: true)` で起動すると、Cookie に `Secure` も付く
- セッションに入った CSRF トークン。`csrf_field(csrf_token)` でフォームに書く。一致する `_csrf` が無い POST、PUT、PATCH、DELETE は 403
- 1 MiB を超えるフォーム本文は 413
- すべての `input` に、同じビューの中のラベルを求めるコンパイル時検査。`for:` が `input` の `id:` と一致する `label`（どちらも文字列リテラル）、囲む `label`、空でない `"aria-label"` か `"aria-labelledby"` のいずれか。ビューの別メソッド、親のビュー、include したモジュールも数える。`type: "hidden"` は対象外。送信には `button` を使う
- `examples/hello` の `GET /greeting`、`POST /greeting`、`GET /greeting/:name`

SQLite、コマンドとイベント、HTML 断片、公式 JavaScript、SSE、島、Postgres、1 つの DB の上で同じプロセスを多数動かすことは、後のフェーズの仕様であり、コードにはありません。

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

`crystal build` は `./shomen` を書き出します。このバイナリはコミットしません。

## ライセンス

[MIT](LICENSE)。Copyright 2026 Silent Malachite。条文の正本は英語の LICENSE です。
