# 状況

`20260929-scale-secret-rotation.md` は、`SHOMEN_SECRET_VERIFY` を検証だけに使う 2 つ目の鍵にし、その鍵で通ったクッキーを `SHOMEN_SECRET` で出し直すと決めた。フェーズ 2 の `Shomen::SessionStore` は鍵を 1 つだけ持ち、`Shomen::Server` は送られた CSRF トークンを `session.csrf_token` と直接比べている。

# 決定

- `Shomen::SessionStore.new(secret, verify_secret = nil)`。クッキーは、まず `secret` で、次に `verify_secret` で確かめる。後者で通ったセッションは `reissue?` が真になり、サーバはその応答で `SHOMEN_SECRET` のクッキーを出し直す
- `session.csrf_token` は常に `secret` で作る。送られたトークンは `Shomen::SessionStore#csrf_valid?(session, sent)` で確かめ、2 つの鍵のどちらで作ったものでも受け付ける。どちらの鍵でクッキーが通ったかは問わない
- `Shomen::Server.new(verify_secret:)` の既定は `SHOMEN_SECRET_VERIFY`。空文字は未設定と同じにする

# 理由

手順 2 の間は、新しい鍵で出し直したクッキーと、古い鍵で描いたフォームのトークンが 1 つの要求にそろうことがある。トークンをクッキーと同じ鍵に縛ると、そのフォームが 403 になる。トークンは同じセッションの `id` から導くので、どちらの鍵で作っても他人のセッションのトークンにはならない。

# 破棄した案

- トークンを、クッキーを通した鍵でだけ確かめる
- 検証用の鍵で通ったセッションを、新しいセッションとして作り直す（利用者のセッションが切れる）
