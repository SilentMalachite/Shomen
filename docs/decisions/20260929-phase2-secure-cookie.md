# 状況

仕様 6 は、HTTPS のときだけ Cookie に Secure を付けるとしている。`Shomen::Server.start` は `bind_tcp` だけを使い、`HTTP::Request` からは TLS 越しかどうかを確実に判断できない。

# 決定

`Shomen::Server.new` と `Shomen::Server.start` に `https : Bool = false` を足す。`true` のときだけ `Secure` を付ける。`X-Forwarded-Proto` は読まない。

# 理由

プロキシの向こうで TLS を終端しているかどうかは、アプリを運用する人しか知らない。ヘッダを無条件に信用すると、偽装された値で属性が変わる。

# 破棄した案

- `X-Forwarded-Proto: https` を見て付ける
- 常に `Secure` を付ける（ローカルの HTTP で Cookie が戻らない）
