# 状況

`20260929-scale-consumers.md` は、コンシューマのチェックポイントの置き場、バッチの手順、再試行の約束を決めた。仕様 10 とアーキテクチャ文書は `Shomen::Consumer` を「要求の外でプロジェクションや反応を動かす」とした。型の形、アプリが何を書くか、誰が動かして誰が止めるか、バッチの大きさ、再試行の間隔、失敗の記録先は決めていない。

# 決定

`abstract class Shomen::Consumer` 1 つで、表に置くプロジェクションと反応の両方を表す。

- `initialize(store : Shomen::Store, retry_first : Time::Span = 1.second, retry_limit : Time::Span = 1.minute)`。`retry_first` が正でなければ、`retry_limit` が `retry_first` より小さければ `ArgumentError`
- `abstract def name : String` がチェックポイントの行の名前。空なら、最初に DB に触れるときに `ArgumentError`。表の形を変えるときは新しい名前にする（`20260929-scale-projection-rebuild.md`）
- アプリが上書きするフックは 3 つで、既定は何もしない。`write(recorded, connection : DB::Connection)` はコンシューマの表に書き、新しいチェックポイントと同じトランザクションでコミットされる。`react(recorded)` は DB の外への副作用（メールなど）で、少なくとも 1 回実行される。`create_tables(connection)` はインスタンスごとに 1 回、最初のバッチ、読み、`checkpoint` の前に、`consumers` の行を作るのと同じトランザクションで表を作る
- SQL は `crystal-db` の `DB::Connection` に直接書く。SQLite と Postgres の両方で動かすときは、パラメータを `$1`、`$2`、… と初出の順に番号付けし、型は `BIGINT` と `TEXT` を使う
- `run_once : Int32` は 1 バッチ（`BATCH = 100` 件まで）を実行し、コミットした件数を返す。イベントが無いとき、別のプロセスがチェックポイントを持っているか動かしたときは 0。イベントが失敗したら、その手前までをコミットしてから例外を上げる
- `start` は 1 本のファイバーで `run_once` を繰り返す。満杯のバッチの後はすぐ次を実行する。そうでなければ、バッチの前に読んだ `store.last_appended` より後の追記を、`store.poll_interval` を上限に `wait_for_append` で待つ（`stop` でも起きる）。別のプロセスがバッチの途中で死んだときは、この上限ごとの試みで続きを拾う
- `run_once` が例外を上げたら、`shomen` のログに warn で「`consumer 名前 failed on the event after チェックポイント; retrying in N ms`」と例外を書き、`retry_first` 待つ。続けて失敗するたびに待ちを倍にし、`retry_limit` を上限にする。例外なく終わったバッチで `retry_first` に戻す。失敗を記録する表は作らない
- `stop(within : Time::Span = 5.seconds)` はループに止まるよう知らせ、実行中のバッチが終わるのを上限まで待つ。上限を過ぎたら warn を書いて戻る。追記や再試行を待っている間なら、すぐに止まる。`start` していなければ何もしない
- アプリは `Shomen::Server.start` の前にコンシューマの `start` を呼び、`Shomen::Server.start` から戻った後に `stop` を呼び、それから Store を `close` する。サーバはコンシューマを知らない

# 理由

表に置くプロジェクションも反応も、チェックポイントの後のイベントを順に処理する点は同じで、違うのは DB に書くか外に出すかだけである。フックを 2 つに分ければ、SQLite では副作用を書き込みトランザクションの外で先に実行でき（`20260929-scale-sqlite-writes.md`）、Postgres では両方をバッチのトランザクションの中で実行できる。両方を持つコンシューマも書ける。SQL を Shomen の型で包むと、`crystal-db` の問い合わせの API を写すことになる。初出の順の `$N` は SQLite も Postgres も同じ意味に読むので、包まなくても同じ SQL が両方で動く。

失敗したイベントの手前までをコミットすれば、再試行のたびに手前のイベントの副作用を繰り返さない。待ちを倍にすれば、DB が落ちている間の試みと警告が増え続けない。上限を 1 分にすれば、DB が戻ってから追いつくまでの遅れは最長でも 1 分ほどになる。サーバの外で `start` と `stop` を呼ぶので、サーバは Store を知らないまま、コンシューマだけを動かすプロセスも同じ書き方で作れる。

# 破棄した案

- 反応とプロジェクションを別の型にする（同じループ、チェックポイント、再試行を 2 回書く）
- フックを `apply(recorded, connection)` 1 つにする（SQLite で副作用を書き込みトランザクションの外に出せない）
- `Shomen::Server.start(consumers: [...])` に渡して、サーバに起動と停止を任せる（サーバが Store とコンシューマを知る。コンシューマだけのプロセスを作れない）
- 接続を Shomen の型で包み、`?` と `$N` を書き換える
- 失敗を表に記録する（記録の書き込みも失敗しうる。ログで足りる）
- イベントが失敗したらバッチ全体を巻き戻す（手前のイベントの副作用を再試行のたびに繰り返す）
- 満杯のバッチの後も追記を待つ（溜まったイベントに追いつくのが、バッチごとにポーリングの間隔ぶん遅れる）
