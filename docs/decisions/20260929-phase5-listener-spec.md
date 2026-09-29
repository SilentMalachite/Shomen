# 状況

受入「フレームワークは島の外にイベントリスナーを撒かない」と「SSE を使わないアプリに依存が増えない」は、ブラウザで JS を動かさないと確かめられない。ブラウザ spec が使う CDP のコマンドは決まっている（`20260929-phase4-browser-spec.md`）。SSE の応答は終わらないので、`call_with` のように書き終わるのを待つヘルパーでは読めない。

# 決定

`Browser#before_load(source)` を足す。`Page.addScriptToEvaluateOnNewDocument` で、ページのスクリプトより先に `source` を動かす。spec はこれで `EventTarget.prototype.addEventListener` と `EventSource` を包み、リスナーを付けた相手と種類、開いたストリームを `window.shomenSeen` に記録する（`PAGE_SPY`）。

受入の spec は、島を動かし、fetch で島を足し、SSE で要素を置き換えた後で、リスナーを付けた相手を `window`、`document`、`EventSource`、島の中の要素、島の外の要素に分ける。島の外の要素が 1 つも無く、`window` と `document` には `shomen.js` の 3 つだけが付いていることを確かめる。`data-shomen-sse` の無いページでは、`EventSource` が 1 つも開かないことを確かめる。

`Browser#run(body)` を足す。`body` を async 関数の中で動かし、`waitFor(check)` を使えるようにする。`waitFor` は最初にすぐ確かめ、その後は文書が変わるたびに確かめる。

サーバ側の SSE の spec は、`IO.pipe` に応答を書かせて読む `SSEClient` を使う。応答は HTTP/1.0 にして、本文をチャンクに分けずに読む。読み込みは 5 秒で打ち切る。クライアントが去ったことは、読む側を閉じて表す。

島の例の動作は、`examples/hello` の spec が `spec/support/browser.cr` を読み込み、Chrome で確かめる。

# 理由

ページのスクリプトより前に包まないと、`shomen.js` が読み込み時に付けるリスナーを記録できない。`on*` プロパティへの代入は包めないので、`shomen.js` がそれを使わないことは文字列で検査する。フェーズ 4 の spec の `waitFor` は変化を待つだけなので、Crystal 側で追記した後に始めると、先に届いた更新を見逃す。パイプは実ポートを使わない。読む側を閉じた後の書き込みはすぐ失敗するので、切断を決まった順序で試せる。

# 破棄した案

- ページの `head` にインラインの `script` を書いて包む（DSL が書かない要素を spec でだけ使い、フェーズ 6 の CSP と衝突する）
- 一時ポートの HTTP クライアントで SSE を読む（TCP では切断後の最初の書き込みが成功することがあり、終わる時機が決まらない）
- 島の例の動作を手で確かめるだけにする（回帰を捕まえられない）
