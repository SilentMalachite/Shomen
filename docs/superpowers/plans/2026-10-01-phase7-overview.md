# フェーズ 7（scale out）計画の骨子

フェーズ 7 の build 項目は 7 つあり、どれもフェーズ 6 の 1 項目より重い。1 本の計画にすると 20 タスクを超えるので、4 本のサブ計画に分ける（2026-10-01 にユーザーが選んだ）。各サブ計画は単独で `crystal spec` が緑になり、フェーズ 7 の受入の一部を満たす。順に実行し、前の計画が緑で終わってから次の計画を書く。

## 分け方と順序

| 順 | サブ計画 | build 項目（`docs/en/02-PHASES.md` のフェーズ 7） | 満たす受入 | 依存 |
|---|---|---|---|---|
| 7a | 通知とポーリング、プロセスをまたぐ SSE（`2026-10-01-phase7a-notify-sse.md`） | A notification after an append (Postgres `LISTEN/NOTIFY`), with polling as the fallback / SSE streams that receive changes appended through any process | An SSE client connected to process A receives an update for an event appended through process B | なし |
| 7b | コンシューマと表に置くプロジェクション（`2026-10-01-phase7b-consumers.md`） | Consumers ... / Projections that keep their rows and checkpoint in database tables, and a bounded wait for a request that must see a given `id` | 2 プロセスで同じコンシューマ（1 回ずつ、`id` 順、kill 後も欠けない）/ 書き込みとチェックポイントが一緒にコミットされる / 表のプロジェクションが届かなければ 503（待ちと `Shomen::Unavailable` の仕組みまで） | 7a（コンシューマは `wait_for_append` で起きる） |
| 7c | セッションが覚える `id`、read-your-writes、replica（`2026-10-01-phase7c-read-your-writes.md`） | Reads from a Postgres replica, with read-your-writes within a session | 遅れる replica でも POST → リダイレクト → GET で変更が見える / 503 の後、セッションが `id` を忘れたら 200 | 7b（`Shomen::Unavailable`、表のプロジェクションの待ち） |
| 7d | ETag と断片キャッシュ、フェーズ 7 の締め（`2026-10-01-phase7d-cache.md`） | A weak `ETag` ... / A bounded in-process cache for rendered fragments ... | 一致する `If-None-Match` は 304 でビューを呼ばない / セッションかビルドが変わったら古い `ETag` で 200 / CSRF トークン入りの断片のキャッシュは例外 / SQLite のアプリはそのまま動き、DB 以外のサービスは要らない | 7a〜7c と独立。締めを兼ねるので最後 |

現行フェーズの表示は 7a の Task 1 でフェーズ 7 にし、7d の最後のタスクで「フェーズ 7 の受入を満たした」にする。README の「Phases 1 to 6 are what run」の見出しも 7d で直す。7a〜7c の README は「ここまで足したもの」だけを書き足す。

## 2026-10-01 にユーザーが決めたこと

- 計画は 4 本に分け、今回は骨子と 7a の詳細を書く
- セッションが覚える「最後に追記した `id`」は署名付きクッキーに置く。既存の `shomen_session` とは別のクッキーに、`id` と期限（既定 60 秒）を入れる。ルートが任意の値を書く汎用の map API はまだ作らない。7c の Task 1 で決定ファイルにする
- 遅れる replica の受入 spec は、replica の URL に別の Postgres DB を渡し、spec がそこへ `events` を好きな `id` まで写して遅れを作る。本物のストリーミングレプリケーションは確かめない。7c の Task 1 で決定ファイルにする

## 各サブ計画の Task 1 で決めること

仕様と既存の決定が空けている細部。各計画を書くときに、コードと試作で確かめてから決定ファイルにする。

7b:

- コンシューマの型と API。反応（メールなど）と、表に置くプロジェクション（行の書き込み）を 1 つの型にするか分けるか。適用のメソッドに何を渡すか（DB の接続を渡すと、SQLite と Postgres でプレースホルダ `?` と `$1` が違う）
- コンシューマを誰が動かすか（アプリが `start` を呼ぶか、`Shomen::Server.start` に渡すか）と、シャットダウンでの止め方
- バッチの大きさ、再試行の間隔の初期値と上限、失敗をどこに記録するか
- `consumers` 表を作る場所（Store のアダプタか、コンシューマ側か）
- 表のプロジェクションを待つ API（`wait_for(id, within)` など）と、`Shomen::Unavailable` を 503 にするサーバの変更

7c:

- サーバが「この要求で追記した `id`」を知る方法（`Shomen::Store#append` が `id` を返し、ルートのヘルパが記録するか、要求ごとの文脈に Store が書くか）。`20260929-phase3-store-api.md` が先送りした「`append` が最後の `id` を返すか」もここで決める
- 覚える `id` のクッキーの名前、形式、署名、期限、`SHOMEN_SECRET_VERIFY` での扱い
- replica の URL の渡し方（`Shomen::Store.new(url, replica:)` など）と、メモリ上のプロジェクションが replica から追いつき、上限で primary に切り替える流れ
- ルートが「見る必要のある `id`」をプロジェクションの追いつきと表の待ちに渡す方法

7d:

- GET ルートが検証子を宣言する形（`Input` を受け取るメソッドなど）と、ビューを呼ぶ前に 304 を返す場所（ルートの `handle` かサーバか）
- コンパイル時に決まるビルド ID の作り方
- 断片キャッシュの API、上限（件数かバイト数か）、キーの組み立て、CSRF トークンを含むかの確かめ方
- フェーズ 7 全体の受入の確認（SQLite の `examples/hello` がそのまま動くこと、DB 以外のサービスが要らないこと）
