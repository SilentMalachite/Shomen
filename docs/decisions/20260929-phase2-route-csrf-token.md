# 状況

フォームを描くビューには CSRF トークンが要る。01-ARCHITECTURE のモジュール境界では、`Shomen::Route` が依存してよいのは HTML と Response だけで、Session は `Shomen::Server` の依存である。

# 決定

`Shomen::Server` がトークンを文字列で `handle` に渡し、`handle` はルートの `csrf_token` に入れてから `call` する。ルートに `Shomen::Session` は渡さない。ビューは `csrf_field(token)` で `<input type="hidden" name="_csrf" value="...">` を書く。セッションの map をルートから読み書きする API はフェーズ 2 では作らない。

# 理由

文字列 1 つなら Route は Session 型を知らずに済む。フェーズ 2 の受入に、ルートがセッションへ値を書く項目は無い。必要になったら、先に 01-ARCHITECTURE の依存表を直す。

# 破棄した案

- `call` の引数にセッションを足す
- `form` 要素が自動で hidden を差し込む（HTML が Session に依存する）
