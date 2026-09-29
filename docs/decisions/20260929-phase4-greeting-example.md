# 状況

フェーズ 4 の受入は、JS 無しでフェーズ 2 のフォーム（`examples/hello` の `Greeting`）が動くことと、JS 有りで指定要素だけが差し替わること。

# 決定

`Greeting::FormView < Shomen::Fragment` を足し、根要素を `div(id: "greeting-form")` にする。中身はエラーの `p`（`role: "alert"`）と、`data-shomen-post: "greeting-form"` を付けたフォーム。保存ボタンに `id: "greeting-save"` を付ける。`Greeting::EditView` は見出しの後に `embed` で `FormView` を埋め込む。

`Greeting::ShowView` は `div(id: "greeting-form")` の中に「Change」リンク（`data-shomen-get: "greeting-form"`）を置く。両方の文書は `head` で `shomen_script` を呼ぶ。

`Greeting::Edit` と `Greeting::Update` の 422 は、`target` があれば `render_fragment(FormView)`、無ければ今までどおり文書を返す。正しい名前は今までどおり 303 で `Greeting::Show` へ移る。`Users` の例は変えない。

# 理由

同じフォームを、JS 無しでは今までの文書とリダイレクトで、JS 有りでは「Change」で表示中のページにフォームを差し込み、422 ではフォームだけを差し替えて動かせる。フェーズ 2 の spec はそのまま通る。`role="alert"` で差し替え後のエラーが読み上げられ、ボタンの `id` で置き換えの後もフォーカスが保存ボタンに戻る。

# 破棄した案

- 新しい例 `examples/fetch` を作る（受入はフェーズ 2 のフォームを名指ししている）
- `Users` の名前変更も断片にする（受入に要らない）
