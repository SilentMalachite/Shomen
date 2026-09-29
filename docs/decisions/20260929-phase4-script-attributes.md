# 状況

フェーズ 4 は `shomen.js` の `data-shomen-get` と `data-shomen-post` で対象 `id` を差し替える。受入は、JS 無しでフェーズ 2 のフォームが動くこと。仕様 8 は属性を `data-shomen-*` だけとする。

# 決定

`<a href="..." data-shomen-get="ID">` と `<form method="post" action="..." data-shomen-post="ID">` を使う。属性の値は差し替える要素の `id`。URL はリンクの `href`、フォームの `action` から取る。

`shomen.js` は次のときは触らず、ブラウザの既定の動作に任せる:

- 別オリジンの URL
- 左ボタン以外のクリック、Ctrl / Cmd / Shift / Alt 付きのクリック
- `target` が `_self` 以外、`download` 付きのリンク
- `method` が `post` でないフォーム、`enctype` が `application/x-www-form-urlencoded` でないフォーム、`target` が `_self` 以外のフォーム
- `formaction`、`formmethod`、`formenctype`、`formtarget` を持つボタンからの送信
- 他のリスナーが `preventDefault` した操作
- 値の `id` の要素がページに無いとき
- 値の `id` が表示可能な ASCII（0x21〜0x7E）以外の文字を含むとき

フォームの属性は `getAttribute` で読む。フォームの値は `new URLSearchParams(new FormData(form, submitter))` で urlencoded にして送る。

# 理由

URL を `href` と `action` に置くので、JS が無くても同じリンクとフォームが動く。別オリジンの HTML をページに差し込むと、そのオリジンがページにマークアップを入れられる。修飾キーや `target` は利用者が新しいタブを選んだ合図である。サーバはフォームを urlencoded でしか読まない（フェーズ 2）。`form.action` などのプロパティは、同じ名前の入力欄があると入力欄を返すので、属性を読む。`id` は `Shomen-Target` ヘッダの値になる。fetch は Latin-1 を超える文字のヘッダ値で例外を投げ、そのとき POST は `preventDefault` 済みなので何も起きない。Latin-1 の範囲の ASCII でない文字は 1 バイトずつ送られ、サーバでは不正な UTF-8 か別の文字列になる。空白を含む値はサーバが 400 にする（`20260929-phase4-fragment-request.md`）。どれも断片を受け取れないので既定の動作に任せ、JS が無いときと同じくページを読み込ませる。

# 破棄した案

- `data-shomen-get="/url"` と `data-shomen-target="ID"` の 2 属性（URL が JS 無しで使われない）
- `button` や任意の要素にも付けられるようにする（JS 無しで動かない）
- `FormData` を multipart のまま送る（サーバが読めない）
