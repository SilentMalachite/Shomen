# 状況

フェーズ 3 の `Shomen::Store` は SQLite だけを扱い、URL のスキームが `sqlite3` でなければ `ArgumentError` にしていた。フェーズ 6 は Postgres のアダプタを足し、受入に「SQLite と Postgres で同じ Command API を使う」がある。01-ARCHITECTURE は、2 つのアダプタの違いを SQL、列の型、通知の有無にとどめるとしている。

# 決定

`Shomen::Store` の公開 API（`new(url)`、`append`、`read`、`last_appended`、`wait_for_append`、`close`）は変えない。`Shomen::Store.new(url)` が URL のスキームでアダプタを選ぶ。`sqlite3` なら `Shomen::SQLiteAdapter`、`postgres` か `postgresql` なら `Shomen::PostgresAdapter`、それ以外は `ArgumentError` にする。

アダプタは抽象クラス `Shomen::StoreAdapter` を継ぎ、`key`、`append(stream, expected_version, rows) : Int64`（最後の `id` を返す）、`read(after, limit)`、`close` を持つ。版が合わないときに `Shomen::Conflict` を投げる処理は、基底クラスに 1 つだけ置く。引数の検査（空のストリーム名、負の版、UTC でない時刻）、JSON への変換と復元、`Shomen::AppendSignal` への知らせは `Shomen::Store` に残す。`AppendSignal` はアダプタの `key` ごとにプロセスで 1 つにする。SQLite の `key` は `sqlite3://` に実パスを続けたもの、Postgres の `key` は `postgres://` に、ドライバが接続先として URL、そのクエリ、`PGHOST` / `PGPORT` から解決するホスト、ポート、DB 名（`PQ::ConnInfo` の値）を続けたものである。同じ DB を指す URL は、ポートの書き方が違っても 1 つの `AppendSignal` を共有する。

SQLite のアダプタに `max_pool_size` の上限は設けない。仕様 10 のプールの上限は Postgres の接続の話で、SQLite の書き込みはファイルごとの書き込みロックですでに直列になっている。

# 理由

アプリ、コマンド、プロジェクション、SSE は `Shomen::Store` だけを知っていればよく、DB を替えても URL 以外は変わらない。アダプタごとに違うのは SQL と待ち方だけなので、検査と変換を 2 回書かずに済む。

# 破棄した案

- `Shomen::Store` を抽象クラスにし、アプリに `Shomen::SQLiteStore` か `Shomen::PostgresStore` を直接 `new` させる（DB の種類がアプリのコードに入る）
- 1 つのクラスの中で、メソッドごとに SQLite と Postgres を分岐する
