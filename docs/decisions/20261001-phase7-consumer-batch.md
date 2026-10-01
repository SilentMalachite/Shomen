# 状況

`20260929-scale-consumers.md` は、Postgres ではチェックポイントの行をロックしてバッチ全体を 1 トランザクションにし、SQLite では副作用の後の短いトランザクションでチェックポイントを比べると決めた。手順をどこに置くか、`consumers` 表をいつ作るか、途中のイベントが失敗したときの扱い、ロックがいつ外れるか、アプリの SQL が失敗した後の SQLite の扱いは決めていない。`crystal-sqlite3` は、失敗した文が接続に残ると `close` で同じ例外を投げ直す。

# 決定

`consumers(name TEXT PRIMARY KEY, checkpoint INTEGER NOT NULL)`（Postgres では `BIGINT`）は、Store を開くときに `events` と一緒に `CREATE TABLE IF NOT EXISTS` で作る。

`Shomen::StoreAdapter` に次の 4 つを足す。`Shomen::Store` は同じ名前の公開メソッドで渡し、`consume` では行を `Shomen::Recorded` に戻す。`Shomen::Consumer` はこれらを使う。

- `register(name, &)`: ブロックに接続を渡してコンシューマの表を作らせ、`INSERT INTO consumers (name, checkpoint) VALUES (…, 0) ON CONFLICT (name) DO NOTHING` を実行し、1 つのトランザクションでコミットする。Postgres では追記と同じアドバイザリロックの中で行う。Store は空の名前を `ArgumentError` にする
- `checkpoint(name)`: 行のチェックポイント。行が無ければ 0
- `consume(name, limit, react, write) : Int32`: 1 バッチ。下の手順
- `using_connection(&)`: コンシューマの表を読むための接続を渡す。SQLite ではファイルのロックの中で渡すので、ブロックの中で同じ Store を呼ばない

どちらの DB でも、各イベントを `SAVEPOINT shomen_event` の中で処理し、成功したら `RELEASE SAVEPOINT shomen_event`、失敗したら `ROLLBACK TO SAVEPOINT shomen_event` と `RELEASE SAVEPOINT shomen_event` を実行して止まる。その手前のイベントまでチェックポイントを進めてコミットし、それから例外を上げる。イベントを `Shomen::Recorded` に戻せない（知らない型）のも、そのイベントの失敗として扱う。

Postgres の `consume`:

1. `BEGIN` し、`SET LOCAL idle_in_transaction_session_timeout = '60s'` を実行する
2. `SELECT checkpoint FROM consumers WHERE name = $1 FOR UPDATE SKIP LOCKED`。行が返らなければ、別のプロセスが処理中なのでコミットして 0 を返す
3. チェックポイントより後のイベントを `limit` 件まで読み、1 件ずつ `react` と `write` を実行する
4. 1 件以上成功したら `UPDATE consumers SET checkpoint = $1 WHERE name = $2` を実行し、コミットする

SQLite の `consume`:

1. チェックポイントと、その後のイベント `limit` 件をトランザクションの外で読む
2. 1 件ずつ `react` を実行し、失敗したらそこで止める
3. `react` が成功したイベントが 1 件以上あれば、ファイルのロックを取って `BEGIN IMMEDIATE` し、それらの `write` を実行する
4. 1 件以上書けたら `UPDATE consumers SET checkpoint = ? WHERE name = ? AND checkpoint = ?`（3 つ目は 1 で読んだ値）を実行する。0 行なら、別のプロセスが先にチェックポイントを動かしたので巻き戻し、自分の失敗も捨てて 0 を返す。そうでなければコミットする

SQLite では、`register`、`consume`、`using_connection` が接続を返す前に、例外の有無にかかわらず、その接続のすべての文を `sqlite3_next_stmt` でたどって `sqlite3_reset` する。アプリが自分の SQL の失敗を捕まえて続けても、失敗した文が残らない。`crystal-sqlite3` は `sqlite3_next_stmt` を束縛していないので、`Shomen::LibSQLite` で宣言する。ライブラリはすでにリンクされているので `@[Link]` は付けない。

# 理由

バッチの手順は「誰がいつロックを持つか」で DB ごとに違うので、追記の手順と同じくアダプタに置く。savepoint を置けば、Postgres で SQL が失敗した後もトランザクションを続けて手前のイベントをコミットでき、SQLite と同じ意味になる。Postgres の `idle_in_transaction_session_timeout` は既定で無効なので、バッチのトランザクションにだけ 60 秒を付ける。副作用が返らなくなったプロセスや、落ちたホストのロックは、これで外れる。Store を開くときに `consumers` 表を作れば、コンシューマを動かさないプロセスでもチェックポイントを読める。コンシューマの表を作るのは `CREATE TABLE IF NOT EXISTS` で、Postgres ではこの文どうしが同時に走ると失敗しうるので、`events` 表を作るときと同じロックを取る。SQLite の文のリセットは、Shomen が書いていない SQL にも効くよう、接続のすべての文に対して行う。

# 破棄した案

- 手順を `Shomen::Consumer` に置き、アダプタは SQL だけを持つ（DB の種類で分岐する処理が Consumer に入る）
- コンシューマが最初に動いたときに `consumers` 表を作る（読むだけのプロセスで表が無い）
- 失敗したらバッチ全体を巻き戻す
- `SELECT … FOR UPDATE`（`SKIP LOCKED` なし）で待つ（待つ間プールの接続を 1 本持ち続ける）
- 例外が起きたときだけリセットする（アプリが失敗を捕まえると文が残り、`close` が失敗する）
- ロックの上限を設けず、Postgres の設定に任せる（既定ではホストが落ちたときのロックが外れない）
- SQLite で失敗した文を Shomen が書いた文だけリセットする（アプリの SQL が残り、`close` が失敗する）
- `crystal-sqlite3` のクラスを開き直してメソッドを足す（依存の内部に結びつく）
