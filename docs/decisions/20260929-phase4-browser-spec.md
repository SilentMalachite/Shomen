# 状況

フェーズ 4 の受入「JS 有効では指定要素だけが差し替わる」は、ブラウザで JS を動かさないと確かめられない。公式 JS は npm に依存しない。本体の依存 shard は決定ファイル無しに増やせない。仕様はテストに実ポートを取らせず、一時ポートを使わせる。

# 決定

`spec/support/browser.cr` に、標準ライブラリの `HTTP::WebSocket` と `HTTP::Client` だけで書いた DevTools プロトコルのクライアント `Browser` を置く。Chrome を `--headless --remote-debugging-port=0` と一時プロファイルで起動し、標準エラーの `DevTools listening on ws://…` から接続先を読む。`Page.enable`、`Page.navigate`、`Page.loadEventFired`、`Page.frameNavigated`（戻る／進むキャッシュからの復元の待機）、`Runtime.evaluate`（`awaitPromise`）、`Browser.close`、`PUT /json/new` だけを使う。`Browser#clear_events` で待つ前に古いイベントを捨てる。`Browser.close` で Chrome を正常終了させ、Chrome 自身にロックファイルやソケットを片付けさせる（SIGTERM では片付けずに終わる）。20 秒で終わらなければ強制終了する。

Chrome は `SHOMEN_CHROME`、macOS の `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`、`PATH` の `google-chrome`、`chromium`、`chromium-browser` の順に探す。見つからなければブラウザ spec は `pending` になる。

ブラウザ spec は `Shomen::Server` を `127.0.0.1` の一時ポートで動かす。待ちはページ内の `MutationObserver` と DevTools のイベントで行い、20 秒を過ぎたら失敗にする。

# 理由

受入を手で確かめるだけでは回帰を捕まえられない。CDP は WebSocket と JSON だけで話せるので、shard も npm も足さずに済む。Chrome が無い環境で `crystal spec` 全体を落とさないために `pending` にし、フェーズの完了確認では Chrome のある開発機で pending が 0 件であることを確かめる。計画時にユーザーがこの案を選んだ。

# 破棄した案

- Playwright や Puppeteer（npm に依存する）
- jsdom や happy-dom を Node で動かす（npm に依存する）
- `chrome --dump-dom --virtual-time-budget`（操作を挟めず、macOS では出力の後に終了しないことがあった）
- 手動のブラウザ確認だけにする（回帰を捕まえられない）
