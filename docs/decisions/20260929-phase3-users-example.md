# 状況

フェーズ 3 の例は「名前を変えると、イベントの行が 1 つ増える」ことである。AGENTS.md の検証コマンドは `examples/hello` だけを走らせる。フェーズ 2 の `Greeting` はフェーズ 4 の受入（JavaScript なしでフォームが動く）でも使う。

# 決定

`examples/hello/src/users.cr` に次を置き、`hello.cr` から require する。

- コマンド `Users::RenameUser`、イベント `Users::UserRenamed`（`event_type "user_renamed"`）、ストリーム `user-<id>`、プロジェクション `Users::Names`
- `Users::Edit`（`GET /users/:id/edit`）、`Users::Rename`（`POST /users/:id`）、`Users::Show`（`GET /users/:id`）
- フォームは、開いたときのストリームの版を hidden の `version` で送る。版は最後の改名ではなく、ストリームの最後のイベントの版にする。`Users::Rename` はそれを期待する版にして追記する。古いフォームは 409、負の版は 400 になる
- 名前が前後の空白を除いて 2 文字未満なら、コマンドが `Shomen::Rejected` を返し、422 で描き直す
- 名前のまだ無い利用者の `Users::Show` は 404
- DB の URL は環境変数 `HELLO_DATABASE_URL`、無ければ `sqlite3://./var/shomen.sqlite3`
- `Shomen::Server.start` の前に `Users::NAMES.catch_up` を呼ぶ
- `Greeting` は変えない

# 理由

期待する版をフォームに載せれば、フォームを開いてから送るまでの間の別の変更を検出でき、409 の経路を例で確かめられる。`Greeting` を残せば、フェーズ 2 の受入とフェーズ 4 の前提が変わらない。

# 破棄した案

- `Greeting` を永続化に書き換える
- 送信時にリードモデルの版を期待する版にする（古いフォームで黙って上書きする）
- `examples/users` を新しく作る（検証コマンドが走らせない）
