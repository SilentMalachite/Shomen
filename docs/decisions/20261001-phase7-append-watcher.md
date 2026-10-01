# 状況

`20260929-scale-notify.md` は、Postgres が追記の後に通知を送り、各プロセスが `LISTEN` 専用の接続を 1 本持ち、一定間隔（既定 5 秒）でもポーリングすると決めた。`20260929-phase5-append-signal.md` は、待つ側の API を `Shomen::Store#last_appended` と `#wait_for_append` に閉じ、フェーズ 7 では同じ API の裏で通知とポーリングが `AppendSignal#announce` を呼べばよいとした。いつ受信とポーリングを始めて止めるか、間隔をどこで決めるか、接続が切れたときの扱いは決めていない。

# 決定

`Shomen::AppendWatcher` を置く。アダプタと `AppendSignal` と間隔を受け取り、生成では DB に触れず、次の 2 つのファイバーを始める。

- ポーリング: 始まるとすぐに、その後は間隔ごとに `last_id` を読んで `announce` する。問い合わせが失敗したら `shomen` のログに warn を書き、次の間隔で続ける
- 受信（`StoreAdapter#notifies?` が真の DB だけ）: `last_id` を読んで `announce` してから `StoreAdapter#listen` で通知を待ち、届いた `id` を `announce` する。接続が切れたら warn を書き、100 ミリ秒後につなぎ直す。続けて失敗するたびに待ちを倍にし、間隔を上限にする。前の接続がその時点の待ちより長く続いていたら、待ちを 100 ミリ秒に戻す

`stop` はポーリングを止め、受信中の接続を `StoreAdapter#interrupt_listen` で切り、受信のファイバーが終わるのを待つ。接続を開いている途中で 1 回目の切断が空振りすることがあるので、50 ミリ秒ごとに切断を繰り返し、5 秒で諦めて warn を書く。

`Shomen::Store` は、最初の `wait_for_append` で watcher を作る。watcher はアダプタの `key` ごとにプロセスで 1 つにし、同じ DB を開いたほかの Store は作られた watcher を使う。間隔は、watcher を作った Store の `poll_interval`（`Shomen::Store.new(url, poll_interval: 5.seconds)`、正でなければ `ArgumentError`）にする。watcher を作った Store の `close` が watcher を止めて一覧から外す。ほかの Store は、次の `wait_for_append` で watcher を作り直す。閉じた Store の `wait_for_append` は watcher を作らない。

`last_appended` は「このプロセスが知っている最大の `id`」になる。このプロセスの追記はコミットの直後に、ほかのプロセスの追記は通知かポーリングで知る。

# 理由

待つものが無いプロセスでは、接続もファイバーも問い合わせも増えない。SSE を使わないアプリは、フェーズ 5 と同じく何も増えない。受信の前に最大の `id` を読むので、接続が切れていた間の追記はつなぎ直した時点で知らせる。読んでから `LISTEN` が効くまでの間の追記は、次のポーリングで知らせる。`crystal-pg` の `LISTEN` は接続を開いてから読み取りに入るまでを 1 つの呼び出しで行い、その間に割り込む口が無いので、この隙間はポーリングに任せる。生成で DB に触れないので、DB に届かないときも最初の `wait_for_append` は例外を投げず、プロセス全体のロックの中で問い合わせを待たない。同じ DB ごとに 1 つにすれば、仕様 10 の「LISTEN 専用の接続を 1 本」を守れる。間隔を Store の引数にしたのは、spec と、通知の無い SQLite を複数プロセスで使うアプリが短くできるようにするためである。

# 破棄した案

- Store を開いたときに必ず受信とポーリングを始める（SSE もコンシューマも使わないプロセスが接続と問い合わせを持つ）
- Store ごとに watcher を持つ（同じ DB を 2 つの Store で開くと `LISTEN` の接続が 2 本になる）
- watcher を参照の数で共有し、最後の Store が閉じるまで止めない（数え違いで接続が残る。閉じた Store のアダプタで問い合わせ続けることもある）
- つなぎ直しを一定間隔にする（DB が落ちている間、接続の試みが続く）
- 待つ側が毎回 DB の最大の `id` を読む（待つたびに問い合わせが増える）
