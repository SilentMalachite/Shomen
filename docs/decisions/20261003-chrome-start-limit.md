# 状況

`20260929-phase4-browser-spec.md` は、ブラウザ spec の待ちを 1 つの操作ごとに 20 秒とし、Chrome が `DevTools listening on ws://…` を書くまでの待ちも 20 秒にした。#20 の CI で、スイートで最初に Chrome を起動する例（`spec/shomen/script_spec.cr` の `replaces only the element named by data-shomen-get`）が `Chrome did not listen within 00:00:20` で落ち、再実行では通った。同じ CI で Chrome を 5 回続けて起動して測ると、1 回目は 4.8 秒、2 回目以降は約 0.22 秒だった。1 回目は Chrome をディスクから読み込むので、ランナーが遅いと 20 秒を超えうる。

# 決定

- Chrome が待ち受けるまでの待ちは `Browser::START`（60 秒）にする。`Browser.endpoint(error, within = START)` で、spec は `within` を短くして期限切れを確かめる
- DevTools の各操作（`PUT /json/new`、WebSocket のハンドシェイク、コマンドの応答、イベントの待機）の上限は `Browser::LIMIT`（20 秒）のまま変えない
- CI で事前に Chrome を起動して温める手順は足さない

# 理由

遅いのは初回の起動だけで、起動した後の操作は速い。待ちを分ければ、操作の待ちを延ばさずに初回の起動のばらつきを吸収できる。60 秒は、測った初回の起動の 10 倍を超える。spec の中で待つので、手元の開発でも CI でも同じに効く。CI だけで温めると、手元の遅いマシンでは同じ失敗が残る。

# 破棄した案

- `LIMIT` を全体に延ばす（壊れた操作を見つけるまでの時間も延びる）
- CI で `crystal spec` の前に Chrome を 1 回起動する（CI でしか効かない）
- 起動に失敗したら Chrome を起動し直す（遅い起動を途中で止めて、また初めから読み込ませることになる）
