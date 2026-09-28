# 状況

仕様 6 は、HTTPS のときだけ Cookie に Secure を付けるとしている。`Shomen::Server.start` は `bind_tcp` だけを使い、`HTTP::Request` からは TLS 越しかどうかを確実に判断できない。

# 決定

`Shomen::Server.new` と `Shomen::Server.start` に `https : Bool = false` を足す。`true` のときだけ `Secure` を付ける。`X-Forwarded-Proto` は読まない。

`https` が `true` のときは、署名の正しい Cookie を持つ要求にも毎回 `Set-Cookie` を返す。値は変えない。

# 理由

プロキシの向こうで TLS を終端しているかどうかは、アプリを運用する人しか知らない。ヘッダを無条件に信用すると、偽装された値で属性が変わる。

ブラウザは Cookie の属性を送ってこないので、サーバは受け取った Cookie に Secure が付いているかを知らない。HTTP で発行した Cookie を持つ利用者が HTTPS に切り替えた後に来ても、新しいセッションでなければ `Set-Cookie` を返さないと、Secure の無い Cookie が残り、HTTP へのアクセスで平文のまま送られる。毎回返せば、最初の応答で Secure の付いた Cookie に置き換わる。

# 破棄した案

- `X-Forwarded-Proto: https` を見て付ける
- 常に `Secure` を付ける（ローカルの HTTP で Cookie が戻らない）
- HTTPS でも新しいセッションのときだけ `Set-Cookie` を返す（HTTP で発行した Cookie が Secure なしのまま残る）
