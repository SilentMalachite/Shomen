# 状況

仕様 1 が依存を許す shard は、フェーズ 3 以降の `crystal-sqlite3` だけだった。フェーズ 6 の Postgres アダプタと、フェーズ 7 の `LISTEN/NOTIFY` には Postgres のドライバが要る。仕様 1 は、それ以外の shard を足す前に決定ファイルを求めている。

# 決定

フェーズ 6 から `crystal-pg`（shard 名 `pg`、GitHub `will/crystal-pg`）を依存に足す。`crystal-sqlite3`（shard 名 `sqlite3`）と同じく `crystal-db`（shard 名 `db`）の上に作られているので、Store の境界は `crystal-db` の `DB::Database` にする。`db` は Store が直接使うので、フェーズ 3 で `shard.yml` に明示し、下限を書く。接続プールは `crystal-db` のものを使い、プロセスごとの上限は DB の URL（`max_pool_size` など）で決める。`LISTEN` には `PG.connect_listen` を使う。

確認した時点（2026-09-29）の版とライセンスは次のとおり。`pg` 0.30.0（BSD-3-Clause）、`sqlite3` 0.23.0（MIT）、`db` 0.14.0（MIT）。`pg` と `sqlite3` は、どちらも `db ~> 0.14.0` に依存する。

# 理由

`crystal-pg` は 2026 年 9 月にも更新が続いている。SQLite と同じ `crystal-db` の上にあるので、2 つのアダプタの違いは SQL 文と列の型、通知の有無にとどまり、プールとトランザクションの扱いを共有できる。BSD-3-Clause は、MIT の本体から依存として使える。

# 破棄した案

- Postgres のワイヤプロトコルを標準ライブラリだけで書く
- `crystal-db` を通さず、アダプタごとにドライバの API を直接呼ぶ
- 接続プールを Shomen 側で作る
