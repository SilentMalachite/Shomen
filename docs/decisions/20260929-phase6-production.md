# 状況

仕様 5 は、未処理例外の 500 で、本番相当のフラグのときはメッセージを出さないとしている。フェーズ 6 はそのフラグを `SHOMEN_ENV=production` に決め、あわせて `SHOMEN_SECRET` を必須にする（`20260929-scale-production-secret.md`）。いまの 500 の文書は例外の `message` をそのまま出し、例外をどこにも記録していない。

# 決定

- `SHOMEN_ENV` の値がちょうど `production` のときを本番とする。`Shomen::Server.new` のときに 1 回読む
- 本番では、`SHOMEN_SECRET` が未設定か 32 バイト未満なら、`ArgumentError`（"SHOMEN_SECRET must be set to at least 32 bytes when SHOMEN_ENV=production"）を投げる。`secret:` を直接渡したときも、32 バイト未満なら "secret must be at least 32 bytes when SHOMEN_ENV=production" で投げる。`SHOMEN_SECRET_VERIFY` と `verify_secret:` も同じ下限で確かめる（`20260929-phase6-secret-verify.md`）
- 本番の 500 は、見出し "Error" だけの文書にし、例外のメッセージを出さない。400 の説明（"invalid id" など）は利用者への案内なので、本番でも出す
- 未処理例外は、環境によらず `Log.for("shomen")` に error で、例外ごと書く。メッセージは "unhandled exception"
- `Shomen::Server.start` は鍵を確かめてから待ち受ける。鍵が足りなければ、未処理の `ArgumentError` として終了コード 1 で終わる

# 理由

本番でメッセージを隠すなら、運用者が原因を見る場所が要る。標準の `HTTP::Server` も `Log` に書くので、同じ出口にそろえる。400 の説明は入力のどこが悪いかを伝えるもので、内部の情報を含まない。生成時に 1 回読めば、要求のたびに環境変数を読まずに済み、プロセスの途中で振る舞いが変わらない。

# 破棄した案

- 本番の判定に `CRYSTAL_ENV` や `--release` を使う
- 本番では 400 の説明も隠す
- 例外を記録しない、または本番だけ記録する
- 起動の失敗を `STDERR` への 1 行と `exit 1` にする（ライブラリの中で終了すると spec で確かめられない）
