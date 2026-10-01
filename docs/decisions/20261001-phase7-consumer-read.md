# 状況

仕様 10 と `20260929-scale-read-your-writes.md` は、ある `id` を見る必要がある要求が、表に置いたプロジェクションのチェックポイントがそこへ届くまで上限つき（既定 2 秒）で待ち、届かなければ `Shomen::Unavailable` を投げ、捕まえられなければ 503 の HTML 文書にすると決めた。待つ API、待ち方、503 の文面は決めていない。見る必要のある `id` をセッションから得る仕組みは 7c で決める。

# 決定

- `Shomen::Consumer#read(id : Int64 = 0, within : Time::Span = 2.seconds, & : DB::Connection -> T) : T` は、チェックポイントが `id` 以上になるまで待ち、`Shomen::Store#using_connection` の接続をブロックに渡して、その値を返す。`id` が 0 以下なら待たず、チェックポイントも読まない
- 待つ間は `consumers` の行を読み直す。間隔は 10 ミリ秒から倍にし、200 ミリ秒を上限にする。`within` を過ぎても届かなければ、`Shomen::Unavailable` を「`名前 did not reach event id within 上限`」で投げる
- `Shomen::Server` は捕まえられなかった `Shomen::Unavailable` を、見出し `Unavailable` と `Shomen::Server::UNAVAILABLE_DETAIL`（`This page cannot show the latest changes yet. Try again in a moment.`）の 503 の HTML 文書にする。例外のメッセージは出さない。`Retry-After` は付けない
- 7b では、見る必要のある `id` はルートが渡す

# 理由

コンシューマは別のプロセスで動いていることがあるので、チェックポイントは DB から読むしかない。待つのは、コンシューマが遅れているときに、見る必要のある `id` を持つ要求だけである。間隔を倍にすれば、2 秒の待ちでも問い合わせは 15 回ほどで済み、同じプロセスのコンシューマがすぐ追いついたときは 10 ミリ秒ほどで返る。チェックポイントは下がらないので、確かめた後に読めば、少なくともその `id` までが表に入っている。読みと接続を 1 つのメソッドにしておけば、7c で replica から読むときも、チェックポイントを確かめた DB と読む DB を同じにできる。

# 破棄した案

- チェックポイントのコミットごとに `NOTIFY` を送り、待つ側が受ける（`LISTEN` の接続とチャネルが増える。待つのはまれ）
- 同じプロセスのコンシューマの知らせだけで待つ（別のプロセスのコンシューマを待てない）
- 待つだけのメソッド（`wait_for(id)`）と読みを分ける（7c で replica を使うと、確かめた DB と読む DB が分かれる）
- 上限なしで待つ
- 上限を過ぎたら古い状態のまま読む
