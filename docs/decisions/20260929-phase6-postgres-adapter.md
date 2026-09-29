# 状況

`20260929-scale-event-order.md` は、Postgres への追記を固定キーの `pg_advisory_xact_lock` で直列にし、`id` の identity を `CACHE 1` にすると決めた。キーの値、表を作るときの扱い、接続プールの大きさは決めていない。仕様 10 は、プロセスごとの接続プールに上限を置き、その大きさを DB の URL で決めるとしている。`crystal-db` の `max_pool_size` の既定は 0（上限なし）、`max_idle_pool_size` の既定は 1 である。

# 決定

- 表は `id BIGINT GENERATED ALWAYS AS IDENTITY (CACHE 1) PRIMARY KEY`、`version BIGINT`、ほかの列は `TEXT`、`UNIQUE (stream, version)` にする
- ロックのキーは `BIGINT` の `0x73686f6d656e`（`"shomen"` の ASCII）1 つにする
- `CREATE TABLE IF NOT EXISTS` も、同じキーのロックを取ったトランザクションの中で行う
- 追記は `BEGIN`、ロック、現在の版の確認、イベントの数だけの `INSERT ... RETURNING id`、`COMMIT` の順に行う。版が合わなければ何も挿入せずに `ROLLBACK` し、`Shomen::Conflict` を投げる。ほかの失敗でも `ROLLBACK` し、元の例外を投げ直す。`ROLLBACK` 自体の失敗は元の例外を隠さない
- URL に `max_pool_size` が無ければ 10 にする。`max_idle_pool_size` が無ければ `max_pool_size` と同じにする
- URL の DB 名が空なら、接続する前に `ArgumentError` にする

# 理由

空の DB に複数のプロセスが同時に起動すると、`CREATE TABLE IF NOT EXISTS` どうしがカタログの一意制約でぶつかることがある。追記と同じロックで直列にすれば、後から来たプロセスは表があるのを見るだけになる。上限の無いプールは、プロセスを増やすと Postgres の `max_connections` を使い切る。10 本あれば、ロックで直列になる追記を待たせながら読み出しを並べられる。アイドルの上限を 1 のままにすると、負荷の高いときに接続を閉じては開き直す。キーを 1 つに固定すれば、アプリの他のアドバイザリロックとぶつかるのは同じ値を使ったときだけになる。

# 破棄した案

- `BIGSERIAL` を使う（identity より古い書き方で、`id` に直接値を書けてしまう）
- 表を作るときはロックを取らない
- プールの大きさを `crystal-db` の既定（上限なし）のままにする
- キーを `hashtext('shomen')` のように計算で決める
