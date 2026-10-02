# 状況

フェーズ 8 は、業務画面の `examples/records` を作り、フェーズ 1–7 のうちアプリケーションが呼ぶ部品（型付きルートとパスヘルパ、CSRF 付きのフォーム、コマンドとイベント、コンシューマが表に保つプロジェクション、`remember`、断片、SSE、島、検証子のある GET ルート、キャッシュした断片）を使うとした。題材は備品台帳（2026-10-01 にユーザーが選んだ）。イベント、ストリーム、拒否の条件、画面とルート、部品の置き場所、設定を読む環境変数、spec の書き方は決めていない。

# 決定

- 備品はタグで呼ぶ。タグは英大文字か数字で始まり、英大文字、数字、`-` だけからなる 1–20 文字。名前と借り手は前後の空白を除いて 1–80 文字
- 備品 1 つが 1 ストリーム `item-<tag>`。イベントは `ItemRegistered`（`item_registered`、タグ、名前）、`ItemLent`（`item_lent`、タグ、借り手）、`ItemReturned`（`item_returned`、タグ）。どれも `at` を持つ
- コマンドは `RegisterItem`、`LendItem`、`ReturnItem`。`RegisterItem` は形の合わないタグ、名前、登録済みのタグを拒む。`LendItem` は貸出中の備品と形の合わない借り手を、`ReturnItem` は貸出中でない備品を拒む。今の状態はルートが表から読んで渡す
- コンシューマ `Items::Ledger`（名前 `records_ledger`）が表 `records_items`（`tag`、`name`、`borrower`、`version`、`event_id`）と `records_loans`（`event_id`、`tag`、`borrower`、`lent_at`、`returned_at`）を保つ。`version` はストリームの版、`event_id` は備品を最後に変えたイベントの `id`。ページはすべて `read(must_see)` で表を読む
- 登録は版 0 で追記する。貸出と返却は、フォームが運んだ版で追記する。表の版がフォームの版と違えば、コマンドを呼ばず、今の状態のフォームを 409 で返す。表を読んでから追記するまでに別の追記が入れば、`append` の `Shomen::Conflict` が 409 にする
- 追記したルートは `remember` し、303 で詳細に移る
- ルート: `GET /items`（一覧、検証子は表の `MAX(event_id)`）、`GET /items/live`（一覧の SSE）、`GET /items/new`（登録フォーム、島 `name-length`）、`POST /items`（登録）、`GET /items/:tag`（詳細、断片 `div#loan-form`、キャッシュした断片 `div#history`）、`POST /items/:tag/loans`（貸出）、`POST /items/:tag/return`（返却）
- 貸出履歴の断片は、`cached(Records::CACHE, "history", tag, event_id)` で置く。備品が変わると `event_id` が変わり、キーが変わる
- 島 `name-length` は、名前の欄の残りの文字数を見せる。JavaScript が無ければ、数えた行は隠れたまま
- 設定は環境変数 `RECORDS_DATABASE_URL`（既定 `sqlite3://./var/records.sqlite3`）、`RECORDS_REPLICA_URL`（無いか空なら replica なし）、`RECORDS_PORT`（既定 3000）。秘密と本番の設定はフレームワークの `SHOMEN_SECRET`、`SHOMEN_SECRET_VERIFY`、`SHOMEN_ENV`
- 起動は `Records::LEDGER.start`、`Shomen::Server.start(port: Records.port)`、戻ったら `Records::LEDGER.stop`、`Records::STORE.close` の順
- spec は `examples/hello` に合わせ、`Shomen::Server#call` を直接呼ぶ。クッキーを持ち回る `Visitor` を spec に置く。SSE はリポジトリの `spec/support/sse_client.cr`、ブラウザは `spec/support/browser.cr` を使う。spec の DB は一時ファイルの SQLite で、コンシューマは spec の間ずっと動かす

# 理由

台帳は、状態で拒否の条件が変わる（貸出中の備品は貸せない）ので、コマンドとイベントと版の衝突を 1 つの題材で見せられる。一覧と詳細を表から読めば、2 プロセスになっても読み方は変わらない。どのページも `must_see` で読むので、自分の追記は必ず見え、別のプロセスのページでも、クッキーが運んだ `id` まで待つ。

貸出と返却をフォームの版で追記するのは、開いていた画面と違う状態を上書きしないためである。返却のフォームを開いている間に、返却と別の人への貸出が入ったとき、表の版で追記すると、別の人の貸出を返却してしまう。表の版とフォームの版を比べれば、コマンドが見る状態とフォームが見せた状態が同じときだけ追記する。replica が遅れて表の版がフォームより古いときも、409 になり、古い状態で決めない。

一覧の検証子を表の `MAX(event_id)` にすれば、どの備品が変わっても値が変わり、`must_see` まで待った同じ表から読むので、自分の追記の前の一覧を 304 で見せない。

タグをパスに置くので、path helper が拒む文字（`/`、`?`、`#`、`.`、`..`）をタグの形で先に拒む。

島を SSE で置き換える要素の中に置かない（`20260929-phase5-sse-script.md` の既知の制限）ので、島は登録フォームに、SSE は一覧に置く。

# 破棄した案

- 備品の `id` をサーバで連番にする（連番を配る仕組みが要り、2 プロセスで重ならないことを別に保証することになる）
- 登録済みのタグを `Shomen::Conflict` の 409 だけで知らせる（予期した入力の誤りを例外の画面で返すことになる。表で先に確かめ、競合したときだけ 409 にする）
- 貸出と返却を表の版で追記する（開いていたフォームと違う状態を上書きする）
- メモリの `Shomen::Projection` で読む（フェーズ 8 が求めるのは表に保つプロジェクション。2 種類の読み方を混ぜると、どちらがどの画面を支えるかが読みにくくなる）
- SSE の対象を詳細の貸出状態にする（フォームを含む要素は置き換えると入力が消える。8c の 2 プロセスの確認は、別のプロセスで登録した備品が一覧に届くことで見る）
