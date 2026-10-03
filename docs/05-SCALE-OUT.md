# 05 スケールアウト

> 日本語訳です。正本は [docs/en/05-SCALE-OUT.md](en/05-SCALE-OUT.md) です。食い違ったら英語に合わせ、このファイルを直します。

この手順で、[`examples/records`](../examples/records) を、SQLite の 1 プロセスから、1 つの Postgres DB の上の 2 プロセスにします。まず replica なしで、次に replica ありで動かします。変えるのは環境変数だけで、ソースは同じです。コマンドはどれも `examples/records` で実行します。

## 環境変数

| 変数 | 既定 | 意味 |
|---|---|---|
| `RECORDS_DATABASE_URL` | `sqlite3://./var/records.sqlite3` | primary の DB。`sqlite3://…` か `postgres://…` |
| `RECORDS_REPLICA_URL` | なし | 読みに使う Postgres の replica。無いか空なら replica なし |
| `RECORDS_PORT` | `3000` | 127.0.0.1 のポート。1 から 65535 |
| `SHOMEN_SECRET` | 再起動までの乱数の鍵 | セッションのクッキーと CSRF トークンに署名する。すべてのプロセスで同じ値にする |
| `SHOMEN_ENV` | なし | `production` なら、32 バイト以上の `SHOMEN_SECRET` を求め、例外のメッセージを隠す |

## SQLite の 1 プロセス

```sh
shards install
mkdir -p var
crystal run src/records.cr
```

<http://127.0.0.1:3000/items> を開きます。Ctrl-C で止まります。サーバは処理中の要求を終え、台帳のコンシューマが止まり、Store が閉じます。

## Postgres の 2 プロセス

Postgres のサーバ（CI は Postgres 17）と、表を作れるユーザーの既存の DB が要ります。2 つのプロセスは同じ DB と同じ鍵を使います。

```sh
export RECORDS_DATABASE_URL=postgres://localhost/records
export SHOMEN_ENV=production
export SHOMEN_SECRET="$(openssl rand -hex 32)"
```

次のコマンドを実行します。CI は [`scripts/two_processes.sh`](../examples/records/scripts/two_processes.sh) から、これをそのまま走らせます。

```sh
set -eu
mkdir -p bin
crystal build src/records.cr -o bin/records
crystal build scale_out/check.cr -o bin/check
RECORDS_PORT=3001 bin/records &
first=$!
RECORDS_PORT=3002 bin/records &
second=$!
trap 'kill "$first" "$second" 2>/dev/null || true' EXIT
bin/check http://127.0.0.1:3001 http://127.0.0.1:3002
kill -TERM "$first" "$second"
wait "$first"
wait "$second"
trap - EXIT
```

アプリと確認をビルドし、ポート 3001 と 3002 で 2 つのプロセスを起動します。`bin/check` は、両方が `GET /items` に答えるまで待ちます。2 つ目のプロセスの一覧のストリームを開き、1 つ目で備品を登録し、2 つ目がそれを見せることを確かめます。詳細と一覧は 1 つ目が付けたセッションのクッキーで読み、開いたストリームにも届くことを見ます。その後、両方のプロセスに SIGTERM を送り、処理を終えて終了コード 0 で終わるのを待ちます。どこかで失敗すれば、0 以外の終了コードで止まります。

どちらのプロセスも台帳のコンシューマを動かします。バッチは表の行とチェックポイントを一緒にコミットするので、各イベントは、先に届いたプロセスが 1 回だけ適用します。どちらかのプロセスで追記すると、もう一方に通知が届き、そのストリームが起きます。セッションのクッキーはそのセッションの最後の追記の `id` を運ぶので、もう一方のプロセスが返すページは、台帳がそこまで届くのを待ちます。

本番では、プロセスの前にロードバランサを置き、すべてのプロセスに同じ `SHOMEN_SECRET` を渡します。鍵を変えるときは、[00-INSTRUCTION.md](00-INSTRUCTION.md) の `SHOMEN_SECRET_VERIFY` を見てください。

## replica あり

`RECORDS_REPLICA_URL` に primary の hot standby を 1 台指定し、同じコマンドを実行します。

```sh
export RECORDS_REPLICA_URL=postgres://replica.example/records
```

ページとストリームは、replica がセッションの最後の追記に届いていれば replica から、2 秒以内に届かなければ primary から読みます。追記、コンシューマのバッチ、通知は primary のままです。Shomen は replica に何も作りません。台帳の表はレプリケーションで replica に届きます。URL は 1 台の standby を指してください。接続ごとに別の standby へ振り分ける URL は使えません。

CI は `RECORDS_REPLICA_URL` に primary 自身の URL を渡します。これで、ソースを変えずに replica の URL ありで起動して応答することを確かめます。遅れる replica は、フェーズ 7 の spec が確かめています（[決定](decisions/20261001-phase7-replica-spec.md)）。
