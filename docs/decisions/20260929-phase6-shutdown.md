# 状況

`20260929-scale-graceful-shutdown.md` は、SIGTERM と SIGINT の後の順序（受け付けの停止、`Connection: close`、アイドル接続を閉じる、SSE を閉じる、処理中が 0 になるか上限で終わる）を決めた。標準の `HTTP::Server` は接続の一覧を外に出さず、ハンドラは接続のソケットを受け取らない。

# 決定

- `Shomen::Connections` が、サーバの接続を、それを処理するファイバーごとに覚える。状態は idle、busy（要求の処理中）、streaming（SSE）の 3 つ
- `Shomen::Listener < HTTP::Server` は `dispatch` を上書きし、接続のファイバーの始めに `open(io)`、終わりに `leave` を呼ぶ
- `Shomen::Server#call` は、要求の間を busy にする。SSE の応答を書き始めるときに streaming にする。登録の無いファイバー（ハンドラを直接呼ぶ spec）では何もしない
- 合図を受けたら、`drain`（idle の接続を閉じ、streaming の接続を切り、以後の応答に `Connection: close` を付ける）、`HTTP::Server#close`、STDERR への `shomen: shutting down` の順に行う。drain の後で streaming になった接続は、すぐ切る
- streaming の接続は `close` せず、ソケットを `close_write` / `close_read`（shutdown）で切る。読まなくなったクライアントへの書き込みで SSE のファイバーが止まっていると、`close` は送信バッファの flush を待って drain ごと止まるためである。shutdown で止まっていた書き込みが失敗し、そのファイバーが終わるときにソケットを閉じる
- 最初の合図を受けたハンドラは、SIGTERM と SIGINT のカーネルの動作を `LibC.signal` で既定に戻す。Crystal のハンドラは外さない（`Signal#reset` を使わない）。以後に届いた合図はカーネルがすぐ処理するので、イベントループが止まっていてもプロセスはすぐ終わる。先にパイプに入っていた合図を受けたハンドラは、その合図を既定の動作に戻して自分のプロセスに送り直す。プロセスはその合図ですぐ終わる
- `Shomen::Server.start` は、busy が 0 になるか `shutdown_timeout` を過ぎたら戻る。アプリの main がそこで終われば、終了コードは 0 になる
- 待ち受けを始めたら、STDERR に `shomen: listening on http://<アドレス>:<ポート>` を書く。ポート 0 のときは実際のポートが入る

順序（drain の後に close）は `20260929-scale-graceful-shutdown.md`（先に close する）を具体化したものである。外から見た振る舞いは同じである。

要求は、応答を書いて閉じるまで busy とする。SSE でない応答は、ハンドラが busy の間に応答を閉じる。Crystal の `HTTP::Server` の要求処理は、`call` から戻った後にしか flush も close もしないためである。`Shomen::Connections#wait` は、戻る時点で busy が 0 のときだけ true を返す。戻る前に数え直す。drain が始まった後に接続が busy になることがあるので、1 回きりの合図では足りない。

# 理由

`dispatch` は、標準ライブラリが上書きを想定しているメソッドで、ここで接続のソケットをつかめる。ハンドラは接続を処理するファイバーの中で呼ばれるので、ファイバーから接続を引ける。`drain` を `close` より先にすれば、その間に終わる応答にも `Connection: close` が付く。2 回目の合図ですぐ終わるのは、開発中に Ctrl-C を 2 回押したときの期待に合わせるためである。`start` の中で `exit` しないのは、戻った後にアプリが Store を閉じられるようにするためである。待ち受けのアドレスを書けば、ポート 0 で起動したプロセスのポートを spec が知れる。

アイドルの接続に要求が届いたのと同じ瞬間に drain が閉じると、その要求は応答なしで切れる。キープアライブの接続が閉じられたとき、冪等な要求を新しい接続でやり直すのはクライアントの通常の動きなので、この狭い競合は残す。

# 破棄した案

- `HTTP::Server` を使わず、接続の受け付けから自前で書く
- ソケットを包む IO を作り、要求の読み始めを検知する（仕組みが大きい）
- `start` の最後で `exit 0` する
- 2 回目の合図も無視し、上限まで待つ
- 最初の合図で `Signal#reset` により SIGTERM と SIGINT を既定の動作に戻し、ハンドラも外す。Crystal は合図をパイプで受け、1 つずつハンドラのファイバーを起こす。2 つの合図が同時に届くと、2 つ目のファイバーが閉じ済みのサーバを閉じようとして FATAL（終了コード 1）になる。ハンドラを外した後に読まれた合図も FATAL になる
- ハンドラを最後まで入れたままにし、2 回目の合図もハンドラで処理する。2 回目の合図はイベントループがハンドラのファイバーを動かすまで効かない。CPU を使い続けるファイバーや、SQLite の busy_timeout のような待つ C の呼び出しでループが止まっている間は、Ctrl-C を 2 回押してもすぐには終わらない
