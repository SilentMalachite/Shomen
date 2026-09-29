# 状況

グレースフルシャットダウン、`reuse_port`、本番での起動の失敗、2 プロセスでのフォーム、別プロセスからの追記の待ちは、シグナルか別のプロセスを使うので、ハンドラを直接呼ぶ spec では確かめられない。仕様は、spec が固定のポートを取らず、sleep で同期しないことを求めている。

# 決定

- `spec/support/server_worker.cr` と `spec/support/store_worker.cr` をスイートで 1 回ずつビルドし、spec から別プロセスで起動する。ビルドした実行ファイルは、スイートの終わりに消す
- `server_worker` の引数は、ポート（0 で一時ポート）、`reuse` か `single`、`shutdown_timeout` の秒数。Store の URL は環境変数 `WORKER_DATABASE_URL` で渡す
- spec は、STDERR の `shomen: listening on http://127.0.0.1:<port>` からポートを読む。子プロセスの STDOUT と STDERR は行ごとに Channel へ流し、決まった行が来るまで待つ
- 処理中の要求は `/worker/slow` で作る。このルートは STDOUT に `slow` を書き、STDIN から 1 行読むまで返らない。spec は STDIN に 1 行書いて要求を終わらせる
- `store_worker` は 4 つ目の引数 `wait` があると、Store を開いた後に STDOUT に `ready` を書き、STDIN から 1 行読んでから追記する
- 別プロセスが変える Postgres の状態（ロックの待ち、プロジェクションの追いつき）は、`wait_until` で上限つきの繰り返しにして待つ。繰り返しの間は `Fiber.yield` だけで、sleep は使わない

# 理由

子プロセスの出力とパイプは、ファイバーが待てる同期の手段になる。ルートが STDIN を待てば、処理中の要求を好きなだけ保てる。受け付けを止めた後のサーバには、新しい HTTP 要求で合図を送れない。`pg_locks` の問い合わせには待つ相手が無いので、上限つきの繰り返しにし、上限は失敗の検出だけに使う。

# 破棄した案

- 固定のポートで起動する
- 一定時間 sleep してからシグナルを送る
- 処理中の要求を、別の HTTP 要求で終わらせる（受け付けを止めた後は届かない）
