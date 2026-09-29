# 状況

Store は `crystal-db` と `crystal-sqlite3` を require し、libsqlite3 をリンクする。`require "shomen"` で Store も読み込むか、アプリが別に require するかを決めていない。

# 決定

`src/shomen.cr` が Command、Event、Store、Projection も require する。`require "shomen"` するアプリは libsqlite3 をリンクする。

# 理由

00-INSTRUCTION の前提は、アプリが SQLite の 1 プロセスで始まることである。事実はイベントログにあり、Store を使わないアプリは想定の外にある。require を分けると、例と README の手順が 1 つ増えるだけで、利点が小さい。

# 破棄した案

- `require "shomen/store"` を別にして、Store を選んで使う
- SQLite をコンパイル時フラグで切り替える
