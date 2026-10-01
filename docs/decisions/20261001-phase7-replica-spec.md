# 状況

フェーズ 7 の受入「With a replica that lags, a POST, its redirect, and the following GET in one session show the appended change」には、遅れる replica が要る。2026-10-01 にユーザーは、replica の URL に別の Postgres DB を渡し、spec がそこへ `events` を好きな `id` まで写して遅れを作ると決めた。本物のストリーミングレプリケーションは確かめない（`docs/superpowers/plans/2026-10-01-phase7-overview.md`）。

# 決定

- spec は `PostgresSpec.with_database` を入れ子にして、primary と replica の 2 つの DB を作る。replica の DB の表は、その URL で `Shomen::Store` を 1 度開いて閉じて作る
- `PostgresSpec.copy(from, to, table)` は、`to` の `table` を空にしてから、`from` の行をすべて写す。`events` は `id` を保ったまま写す（`OVERRIDING SYSTEM VALUE`）。spec は、追記の後に写さないことで replica を遅らせる
- 受入は 2 つのサーバプロセスで確かめる。プロセス A でフォームを開き、プロセス B に POST し、リダイレクト先をプロセス A で開く。同じセッションでも `shomen_append` を送らなければ変更が見えないことを先に確かめ、replica が遅れていることを示す
- 表のプロジェクションは、同じ 2 つの DB で、プロセスの中から確かめる

# 理由

別の DB に写せば、遅れの大きさを spec が決められ、sleep も replica の設定も要らない。Store は replica を URL でしか知らないので、本物の replica と区別しない。変更が見えない応答を先に確かめないと、replica が遅れていない spec も通ってしまう。

# 破棄した案

- Postgres のストリーミングレプリケーションを spec で組む（開発機と CI に 2 つ目のサーバが要る。遅れを spec が決められない）
- primary と同じ DB を replica として渡す（遅れが無く、受入を確かめられない）
