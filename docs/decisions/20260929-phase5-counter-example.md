# 状況

フェーズ 5 は島の例を 1 つ作る（カウンターで十分）。サンプルは `examples/` にだけ置く。`examples/hello` は SSE を使っていない。

# 決定

`examples/hello/src/counter.cr` に `Counter` を置く。`GET /counter` の文書は、`data-shomen-island="counter"` の `div` の中に、数を示す `p`（`aria-live="polite"`）と、`hidden` の「Add one」ボタン（`type="button"`）を置く。`examples/hello/src/counter.js` はボタンを表示し、クリックごとに数を 1 増やす。リスナーはボタンにだけ付ける。`Shomen::Island.script "counter", "counter.js"` で配る。

`examples/hello` は SSE を使わないままにする。

# 理由

数はブラウザの中だけの短い状態なので、島の例に合う。JS が無いとボタンを押しても何も起きないので隠しておき、島が動いたときだけ見せる。`aria-live` で数の変化が読み上げられる。例が SSE を使わなければ、SSE を使わないアプリの依存が増えていないことを、その `shard.lock` で確かめられる。

# 破棄した案

- 数をサーバに POST する（島の例ではなくなる）
- 例に SSE も入れる（受入に要らず、SSE を使わないアプリの確認に使えなくなる）
- 新しい例 `examples/counter` を作る
