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
