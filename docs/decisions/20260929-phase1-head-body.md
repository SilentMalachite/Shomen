# 状況

`method HEAD` はフェーズ 1 のルート宣言で受け付ける。`Shomen::Server` はリクエストメソッドに関係なく `Response` の本文を書き出している。標準の `HTTP::Server` は HEAD の本文を抑止しない。

# 決定

リクエストメソッドが HEAD のときは本文を書き出さない。`Content-Length` は、書き出さなかった本文のバイト数にする。HEAD を GET ルートへ自動では流さない。未照合の HEAD は、本文の無い 404 文書のヘッダだけを返す。

# 理由

HEAD の応答に本文があると、本文を読まないクライアントが keep-alive の次の応答を誤って読む。`Content-Length` を 0 にすると、GET で返る表現の長さと食い違う。照合規則は method と path の完全一致のままにする。

# 破棄した案

- HEAD でも本文を書き出す
- GET と同じルートを HEAD で自動的に呼ぶ
- `Content-Length` を 0 にする
