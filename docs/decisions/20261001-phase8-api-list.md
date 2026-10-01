# 状況

フェーズ 8 は、`Shomen::` の公開の型とメソッドを `docs/en/04-API.md` と訳に一覧にし、コンパイル時に列挙した公開の型と照合する spec を置くと決めた。何を公開の型と数えるか、一覧の形、アプリケーションが呼ばない型の扱い、照合の範囲は決めていない。

# 決定

- 照合の対象は、`Shomen` から定数をたどって見つかる `TypeNode` のうち `private?` でないもの全部と、`Shomen` 自身。`lib`（`Shomen::LibSQLite`）、`alias`（`Shomen::StoreAdapter::Row` など）、`enum`（`Shomen::Connections::State`）も型として数える。型でない定数（`VERSION`、`BUILD_ID`、`MAX_BYTES` など）は、それを持つ型の項目に書くが、照合しない
- 一覧は `## Application API` と `## Internal` の 2 節。型は `### \`Shomen::Name\`` の見出しで 1 つずつ置く
- Application API の型は、アプリケーションが呼ぶ公開のメソッドとマクロを箇条書きにし、各行に仕様の節か決定ファイルへのリンクを付ける。両方あれば決定ファイルにする。フレームワークの中でしか呼ばないメソッドは載せない
- Internal の型は 1 行の役割だけを書く。節の冒頭で、アプリケーションは呼ばず、どの版でも変わりうると断る
- Application API に置く型: `Shomen`、`Shomen::HTML`、`Shomen::View`、`Shomen::Fragment`、`Shomen::FragmentCache`、`Shomen::Route`、`Shomen::Response`、`Shomen::SSE`、`Shomen::Island`、`Shomen::Server`、`Shomen::Store`、`Shomen::Event`、`Shomen::Command`、`Shomen::Recorded`、`Shomen::Rejected`、`Shomen::Projection`、`Shomen::Consumer`、`Shomen::NotFound`、`Shomen::BadInput`、`Shomen::Forbidden`、`Shomen::Conflict`、`Shomen::Unavailable`
- Internal に置く型: `Shomen::CachedFragment`、`Shomen::ETag`、`Shomen::AppendSignal`、`Shomen::AppendWatcher`、`Shomen::StoreAdapter`、`Shomen::StoreAdapter::Row`、`Shomen::StoreAdapter::Stored`、`Shomen::LibSQLite`、`Shomen::SQLiteAdapter`、`Shomen::PostgresAdapter`、`Shomen::ErrorView`、`Shomen::Session`、`Shomen::SessionStore`、`Shomen::Router`、`Shomen::Router::Entry`、`Shomen::Route::Hooks`、`Shomen::Island::Script`、`Shomen::Island::Script::Input`、`Shomen::Connections`、`Shomen::Connections::State`、`Shomen::Listener`
- 照合する spec は `spec/shomen/api_list_spec.cr`。英語版と訳の両方を読み、見出しの集合が公開の型の集合と等しいこと、同じ型の見出しが 2 つ無いこと、英語版と訳の集合が等しいこと、相対リンクの先のファイルがあることを確かめる。メソッドは照合しない

# 理由

マクロは `TypeNode#constants` と `#private?` で、`Shomen` の下の型を名前の完全な形で集められる。2026-10-01 の試作では 43 個で、`private` の `Shomen::Connections::Entry` は入らなかった。

受入は、公開の型が一覧に無ければ失敗することを求めている。アプリケーションが呼ばない型も、別のファイルから使うので `private` にできない。一覧に載せたうえで Internal に分ければ、照合は全部の型に効き、アプリケーションが頼ってよい範囲も読める。

メソッドまで照合すると、マクロが作るメソッドや継承したメソッドの扱いを決める必要があり、フェーズ 8 の受入を超える。

# 破棄した案

- 公開の型を `:nodoc:` で分ける（マクロから doc コメントを読めない）
- Internal の型を一覧から外す（照合に通すには型を `private` にする必要があり、別のファイルから使えなくなる）
- `crystal docs` の出力を一覧にする（生成物をリポジトリに置かない）
