# 状況

`20260929-scale-notify.md` は、Postgres アダプタが追記と同じトランザクションで `NOTIFY` を送り、ペイロードを新しい最大の `id` だけにし、`LISTEN` の接続をプールに入れずに `PG.connect_listen` で直接つなぐと決めた。チャネルの名前、接続の閉じ方、切断の見つけ方は決めていない。`crystal-pg` 0.30.0 の `PG.connect_listen` は、`blocking: false` なら読み取りを自分で spawn したファイバーで行い、切断の例外はそのファイバーで消える。`blocking: true` なら呼んだファイバーで読み続け、切断で例外を上げるが、呼び出しから戻らないので接続を閉じる口が無い。

# 決定

- チャネルは `shomen_events` 1 つにする。`NOTIFY` は DB ごとに届くので、DB をまたいで混ざらない
- 追記は、挿入の後、`COMMIT` の前に、同じ接続で `SELECT pg_notify('shomen_events', 最後の id の 10 進)` を実行する。版が合わずに巻き戻した追記は通知しない
- 受信は `PG.connect_listen(url, "shomen_events", blocking: true)` を watcher のファイバーで呼ぶ。切断は、そのファイバーに上がる例外で知る
- 受信の接続は、Store の URL に `application_name=shomen-listen-` と 16 桁の 16 進を足した URL でつなぐ。URL がすでに `application_name` を持っていても、受信の接続だけはこの名前で上書きする
- 受信の接続を閉じるときは、Store の URL に `application_name=shomen-stop-` と 16 桁の 16 進を足した URL で短い接続を開き、`SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name = $1 AND pid <> pg_backend_pid()` を実行して閉じる。プールは使わないので、プールが埋まっていても閉じていても、切断は待たされず、プールの接続も作り直さない
- ペイロードが `id`（10 進の整数）として読めない通知は無視する。`announce` は `id` を下げないので、古い `id` の通知は何もしない

# 理由

`COMMIT` の前に送った `NOTIFY` は、コミットしたときだけ、コミットの順に届く。追記はアドバイザリロックで直列なので、通知の `id` はコミットの順に増える。切断を例外で知るには、読み取りのループを自分のファイバーで回すしかない。接続を名前で探して終わらせれば、接続の内部に触れずに閉じられる。同じロールの接続は、superuser でなくても `pg_terminate_backend` で終わらせられる。名前に乱数を入れるので、同じ DB を使うほかのプロセスの受信を切らない。チャネルにはアプリの外からも `NOTIFY` を送れるので、読めないペイロードで受信を止めない。

# 破棄した案

- `blocking: false` で受け、切断はポーリングだけで補う（切れたまま気付かず、遅れがいつもポーリングの間隔になる）
- 受信の接続から定期的に問い合わせを送って生きているか確かめる（`crystal-pg` の公開 API では、受信中の接続に問い合わせを送れない）
- `crystal-pg` のクラスを開き直して、受信中の接続を閉じるメソッドを足す（依存の内部に結びつく）
- Store が閉じても受信の接続を残し、プロセスの終了に任せる（spec と、Store を開き直すアプリで接続が残る）
- DB ごとに別の名前のチャネルにする（`NOTIFY` はもともと DB の中にしか届かない）
