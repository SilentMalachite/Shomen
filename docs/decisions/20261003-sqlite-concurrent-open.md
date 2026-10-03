# 状況

`20260929-phase3-store-api.md` は、SQLite の URL に `journal_mode` が無ければ `journal_mode=wal` を足すと決めた。crystal-sqlite3 は、接続を開くたびに URL の pragma を実行する。まだ無いファイルを 2 つのプロセスが同時に開くと、片方の `PRAGMA journal_mode=wal` が待たずに `SQLITE_BUSY`（database is locked）で終わり、`Shomen::Store.new` が `DB::ConnectionRefused` を上げる。WAL への切り替えは、両方の接続が読みのロックを持ったまま書きのロックを待つとデッドロックになるので、SQLite はビジーハンドラを呼ばずに `SQLITE_BUSY` を返す。`busy_timeout` は効かない。`examples/records` を新しい SQLite ファイルで 2 プロセス起動すると、毎回どちらかが起動に失敗した。すでに WAL のファイルなら起きない。

# 決定

- URL に `journal_mode` が無ければ、URL には足さない。Store を開いた後、`events` 表を作る前に、1 つの接続で `PRAGMA journal_mode=wal` を 1 回実行する。WAL はファイルに残るので、プールが後で開く接続は pragma を実行しなくてよい
- その pragma が `SQLITE_BUSY` で失敗したら、失敗した文をリセットし、10 ミリ秒（ファイバーの sleep）おいて繰り返す。最初の試みから `busy_timeout`（URL の値、無ければ 5000 ミリ秒）を過ぎたら、最後の例外を上げる。`SQLITE_BUSY` 以外の失敗はすぐに上げる
- URL に `journal_mode` があれば、これまでどおり URL のまま crystal-sqlite3 に渡す
- `spec/shomen/store_concurrency_spec.cr` は、まだ無いファイルに 4 つのプロセスを同時に起動して追記させることを 5 回繰り返し、すべて成功することを確かめる

# 理由

ビジーハンドラが呼ばれない失敗なので、待つのは呼ぶ側でしかできない。ファイバーの sleep で待てば、待つ間も同じプロセスのほかのファイバーが動く。上限を `busy_timeout` にすれば、ほかのロック待ちと同じ時間で諦める。pragma を開いた後に 1 回だけ実行すれば、接続ごとに WAL への切り替えを試みる競合も起きない。

# 破棄した案

- `DB::ConnectionRefused` を受けて Store を開き直す（crystal-sqlite3 は原因を捨てるので、`SQLITE_BUSY` と、権限などのすぐに諦めるべき失敗を区別できない）
- プロセスをまたぐファイルロック（`flock`）で開く処理を直列にする（ロック用のファイルが増え、SQLite 自身のロックと別の仕組みになる）
- 手順書で「1 つ目のプロセスが起動してから 2 つ目を起動する」と求める（フレームワークの不具合を利用者に回す）
