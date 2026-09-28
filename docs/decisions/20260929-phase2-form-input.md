# 状況

フェーズ 2 は、urlencoded の `form` POST から `Input` を組むとしている。フェーズ 1 では、`Input` のフィールドは path パラメータと名前も数も一致しなければならない。

# 決定

GET と HEAD のルートは、フェーズ 1 の規則のままにする。それ以外のメソッドでは、path パラメータに無い `Input` のフィールドを本文のフォームから取る。型は path と同じく `String`、`Int32`、`Int64` だけ。フィールドが無い、整数に変換できない、本文が妥当な UTF-8 でないときは `Shomen::BadInput` で 400 にする。同じキーが複数あれば最初の値を使う。`Input` に無いキー（`_csrf` を含む）は無視する。本文は `Server` が一度だけ読んで `URI::Params` にし、`handle(request, form, csrf_token)` に渡す。

# 理由

03-CONVENTIONS は、欠けた入力を `BadInput` にするとしている。クエリ文字列のバインドとチェックボックスの省略値は仕様に無い。本文は一度しか読めないので、CSRF 検査とバインドで同じ値を共有する。

# 破棄した案

- 欠けたフィールドを空文字や nil にする
- `String?` などの nilable 型を受ける
- GET のクエリ文字列を `Input` に入れる
