# 状況

仕様 10 と `20260929-scale-read-your-writes.md` は、読みを replica に回してよいこと、セッションが覚えている `id` より古い状態を見せないこと、replica が上限（既定 2 秒）までに届かなければ primary から読むこと、primary でも表のプロジェクションが届かなければ `Shomen::Unavailable` にすることを決めた。replica の渡し方、どの読みが replica に行くか、メモリ上のプロジェクションと表のプロジェクションの待ち方は決めていない。

# 決定

- `Shomen::Store.new(url, poll_interval:, replica : String? = nil)`。`replica` は Postgres の URL で、primary も Postgres のときだけ受け付ける。ほかは `ArgumentError`。replica の DB には表を作らず、追記、通知の受信、チェックポイントの書き換えをしない。接続の数の既定は primary と同じ 10
- `Shomen::Store#replica? : Bool`。`read(after, limit, replica: true)`、`checkpoint(name, replica: true)`、`using_connection(replica: true) { … }` は、replica があればそこを、無ければ primary を使う。引数の既定は `false`（primary）。追記、コンシューマのバッチ、`last_id` のポーリング、`LISTEN` はいつも primary
- `Shomen::Projection#catch_up(id : Int64 = 0, within : Time::Span = 2.seconds) : self`。replica が無ければ、これまでどおり primary から追いつき、`id` と `within` は使わない（primary は覚えた `id` を必ず持つ）。replica があれば、replica から追いつく。チェックポイントが `id` に届かなければ、replica から追いつき直す。間隔は 10 ミリ秒から倍にし、200 ミリ秒を上限にする（`Shomen::Projection::CHECK_FIRST`、`CHECK_LIMIT`）。`within` を過ぎたら primary から追いつく。待つ間はプロジェクションのロックを持たない
- `Shomen::Consumer#read(id, within)` は、replica があれば、`id` が 0 以下ならすぐに replica で読む。そうでなければ、replica のチェックポイントが `id` に届くまで、これまでと同じ間隔で `within` まで待ち、届けば replica で読む。届かなければ、primary のチェックポイントを 1 回、`CHECK_LIMIT`（200 ミリ秒）を上限に読み、届いていれば primary で読む。届いていなければ `Shomen::Unavailable` を投げる。replica が無ければ 7b のまま
- replica につながらない、replica の問い合わせが失敗する、は例外のまま上げる。primary に切り替えない
- `replica` の URL は 1 台の standby を指す。接続ごとに別の standby へ振り分ける URL（負荷分散器の後ろの複数台）は使わない。Shomen はこれを確かめない。`Consumer#read` はチェックポイントを読む接続と、読みに貸す接続が別なので、遅れた standby に当たると、届いたはずの `id` より古い状態を読む

# 理由

replica を Store の引数にすれば、アプリのプロジェクションとコンシューマは、Store を作る 1 行のほかは変わらない。primary が SQLite のときに replica を受け付けると、何も読めない設定を黙って許す。replica は読み取り専用で動くので、表を作る文を送ると失敗する。

メモリ上のプロジェクションは、覚えた `id` を primary が必ず持つので、上限を過ぎても 503 にならない。表のプロジェクションは、primary のコンシューマも遅れているときがあるので、primary のチェックポイントを確かめる。replica の待ちで上限を使い切った後なので、primary の確かめは 1 回にし、接続の待ちで止まらないよう短い上限を付ける。待つ間にロックを持たなければ、覚えた `id` を持たない要求が、遅れた要求の待ちに巻き込まれない。

replica の故障を primary で黙って補うと、primary が故障に気づかれないまま重くなる。

1 台の standby は WAL を順に適用するので、チェックポイントを読んだ後に取った接続は、それより古い状態を見せない。

# 破棄した案

- replica を別の Store にして、アプリが 2 つを使い分ける（プロジェクションとコンシューマが、どちらで読むかを毎回書く）
- `read` の既定を replica にする（SSE、コンシューマ、既存のアプリの読みが、知らないうちに遅れたデータを見る）
- replica の待ちと primary の確かめを毎回交互に行う（replica が少し遅れるたびに primary で読み、replica の意味が薄れる）
- primary の確かめにも `within` を使う（最長の待ちが 2 倍になる）
- replica が失敗したら primary で読む
- `Consumer#read` がチェックポイントの確かめと読みを同じ接続で行い、複数台の standby を許す（待つ間、最長 `within` まで 1 本の接続を持ち続け、プールが尽きやすい。上限で打ち切った問い合わせが、まだその接続を使っている）
