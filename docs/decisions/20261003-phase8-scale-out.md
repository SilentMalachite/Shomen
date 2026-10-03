# 状況

フェーズ 8 の受入は、`examples/records` の spec が Postgres でも通ること、ソースを変えずに環境変数だけで 1 プロセスの SQLite にも 2 プロセスの Postgres（replica の URL なしとあり）にもなること、CI で 2 プロセスの一方に POST した記録がもう一方のページと SSE に届くこと、`05-SCALE-OUT.md` のコマンドが CI の 2 プロセスの確認と同じであることを求める。spec の DB の選び方、2 プロセスの立て方と確かめ方、手順書と CI を同じに保つ仕組み、replica の URL ありを CI でどう確かめるかは決めていない。2026-10-03 にユーザーは、replica の URL に primary と同じ DB を渡すこと、スクリプトと照合 spec で手順書と CI を同じに保つことを選んだ。

# 決定

- `examples/records` の spec は、`RECORDS_SPEC_POSTGRES` が DB を作れるユーザーの Postgres の URL なら、`records_spec_<16 桁の hex>` という DB を作って走り、終わったら消す。無ければ一時ファイルの SQLite で走る。`SHOMEN_SPEC_POSTGRES` とは別の名前にし、CI は同じ URL を渡して SQLite と Postgres で 1 回ずつ走らせる
- 2 プロセスのコマンドは `examples/records/scripts/two_processes.sh` に置く。`bin/records` と `bin/check` をビルドし、`RECORDS_PORT=3001` と `3002` で 2 つのプロセスを裏で起動し、`bin/check http://127.0.0.1:3001 http://127.0.0.1:3002` を走らせ、両方に SIGTERM を送って終了コード 0 を待つ。DB、replica、鍵は呼ぶ側の環境変数で渡す
- 確認 `bin/check`（`scale_out/check.cr`、本体は `scale_out/two_processes.cr` の `TwoProcesses.run`）は標準ライブラリの HTTP だけで話す。両方の `GET /items` が 200 になるまで最大 60 秒待つ。2 つ目の `/items/live` を開いて最初のメッセージを読み、1 つ目で `TP-<8 桁の hex>` の備品を登録し、1 つ目が付けたクッキーで 2 つ目の詳細と一覧に備品が出ること、開いたストリームに備品が届くことを確かめる。待ちはどれも最大 10 秒。失敗は理由を標準エラーに書いて終了コード 1
- CI は、records の spec の後に、`SHOMEN_ENV=production`、32 バイト以上の `SHOMEN_SECRET`、`RECORDS_DATABASE_URL` をサービスの DB にして、スクリプトを `sh scripts/two_processes.sh` で 2 回走らせる。2 回目は `RECORDS_REPLICA_URL` に primary と同じ URL を渡す
- `docs/en/05-SCALE-OUT.md` と訳は、スクリプトの本文と 1 文字も違わない ` ```sh ` のコードブロックを持つ。`examples/records/spec/scale_out_spec.cr` が、英日の手順書のブロック、スクリプト、`ci.yml` の `run: sh scripts/two_processes.sh` の 2 行を照合する

# 理由

スクリプトを 1 つにすれば、CI が走らせるのは手順書のコマンドそのものになる。照合を spec にすれば、手順書かスクリプトの片方だけを直したときに `crystal spec` が落ちる。Markdown を CI が抜き出して実行する案より、CI の動きが Markdown の書き方に左右されない。

確認を Crystal で書けば、CSRF のトークン、クッキー、SSE を curl と sed で扱うより短く確かで、2 つの HTTP サーバを同じプロセスに立てる spec で確認そのものを試せる。ストリームの最初のメッセージを読み切ってから登録するので、登録前の一覧で「届いた」と判定しない。2 つ目では 1 つ目が付けたクッキーで読むので、ロードバランサの後ろで同じセッションが別のプロセスに回ったときと同じく、`must_see` まで待つ読みと、鍵が両方で同じことを確かめる。

replica に primary と同じ URL を渡すと遅れは無いが、replica の接続で読み、replica のチェックポイントを待つ経路を、ソースを変えずに環境変数だけで通せる。遅れる replica での read-your-writes はフェーズ 7 の spec（`20261001-phase7-replica-spec.md`）が確かめている。本物のストリーミングレプリケーションを CI に組むと、手順書のコマンドも増える。

spec の DB を `SHOMEN_SPEC_POSTGRES` で切り替えると、CI のジョブ全体にそれが設定されているので、CI で SQLite の spec が走らなくなる。

# 破棄した案

- CI で Postgres の hot standby を docker で立てる（CI と手順書のコマンドが長くなる。遅れはフェーズ 7 で確かめた）
- 2 プロセスの確認を replica なしだけにする（受入の「with and without a replica URL」を 2 プロセスで見ない）
- CI が手順書のコードブロックを抜き出して実行する（Markdown の書き方が CI の動きに直結する）
- 確認を curl と sed で書く（CSRF のトークンとクッキーと SSE の扱いが壊れやすく、確認そのものを spec で試せない）
- 2 プロセスで `reuse_port` を使い同じポートを共有する（`examples/records` は `Shomen::Server.start(port:)` だけを呼び、ソースを変えることになる）
