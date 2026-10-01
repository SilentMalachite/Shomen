# 04 API

> 日本語訳です。正本は [docs/en/04-API.md](en/04-API.md) です。食い違ったら英語に合わせ、このファイルを直します。

`Shomen::` の公開の型と、それぞれを決めた場所。spec が下の `###` 見出しを、コンパイラが見つけた公開の型と照合するので、公開の型にはどれも見出しが 1 つある（[decisions/20261001-phase8-api-list.md](decisions/20261001-phase8-api-list.md)）。メソッドは照合しない。

版が `0.x` の間は、マイナー版で Application API が変わりうる（[decisions/20261001-phase8-version.md](decisions/20261001-phase8-version.md)）。

## Application API

### `Shomen`

- `Shomen::VERSION`: `shard.yml` が宣言する版 ([../decisions/20261001-phase8-version.md](decisions/20261001-phase8-version.md))
- `Shomen::BUILD_ID`: コンパイルのたびに変わる 16 進 32 桁 ([../decisions/20261001-phase7-etag.md](decisions/20261001-phase7-etag.md))

### `Shomen::HTML`

- `Shomen::HTML.escape(text)`: HTML の特殊文字をエスケープする ([00-INSTRUCTION.md](00-INSTRUCTION.md#3-ビュー--html))

### `Shomen::View`

- `def to_html : String` と `html lang: "en" do … end`: 文書。DSL は仕様が挙げる HTML 要素ごとにメソッドを持つ ([00-INSTRUCTION.md](00-INSTRUCTION.md#3-ビュー--html))
- `html` の `lang`、1 つの `title`、`button` の `type`、`img` の `alt` をコンパイル時に確かめる ([../decisions/20260928-phase1-html.md](decisions/20260928-phase1-html.md))
- `input`: `input` には、同じビューのラベル、空でない `"aria-label"` か `"aria-labelledby"`、または `type: "hidden"` が要る。どれも無ければコンパイルエラー ([../decisions/20260929-phase2-input-label-check.md](decisions/20260929-phase2-input-label-check.md))
- `text(value)`、`raw(html)`: エスケープした文字列と、そのまま書く HTML ([00-INSTRUCTION.md](00-INSTRUCTION.md#3-ビュー--html))
- `embed(fragment)`: 文書に `Shomen::Fragment` を入れる ([../decisions/20260929-phase4-fragment-view.md](decisions/20260929-phase4-fragment-view.md))
- `csrf_field(token)`: フォームの隠しフィールド `_csrf` ([../decisions/20260929-phase2-route-csrf-token.md](decisions/20260929-phase2-route-csrf-token.md))
- `shomen_script`: `shomen.js` の `script` 要素 ([../decisions/20260929-phase4-script-serving.md](decisions/20260929-phase4-script-serving.md))

### `Shomen::Fragment`

- `def content : Nil`: 1 つの断片の要素。断片の中で `html` を書くとコンパイルエラー ([../decisions/20260929-phase4-fragment-view.md](decisions/20260929-phase4-fragment-view.md))
- `to_html`: 断片の HTML ([../decisions/20260929-phase4-fragment-view.md](decisions/20260929-phase4-fragment-view.md))

### `Shomen::FragmentCache`

- `Shomen::FragmentCache.new(max_bytes: Shomen::FragmentCache::MAX_BYTES)`: プロセスの全セッションが共有するキャッシュ。ルートは `cached` を通して使う ([../decisions/20261001-phase7-fragment-cache.md](decisions/20261001-phase7-fragment-cache.md))

### `Shomen::Route`

- `method GET`、`path "/users/:id"`、`struct Input`、`def call(input : Input) : Shomen::Response`: ルート宣言。同じルートを 2 度登録すると失敗する ([../decisions/20260928-phase1-routing.md](decisions/20260928-phase1-routing.md))
- `Route.path(id: 1)`: パスヘルパ ([../decisions/20260928-phase1-routing.md](decisions/20260928-phase1-routing.md))
- `Input` のフィールドは、パスパラメータと urlencoded のフォームから作る ([../decisions/20260929-phase2-form-input.md](decisions/20260929-phase2-form-input.md))
- `csrf_token`: セッションの CSRF トークン ([../decisions/20260929-phase2-route-csrf-token.md](decisions/20260929-phase2-route-csrf-token.md))
- `render(view, status: 200)`: 文書。`render(view, status: 422)` でフォームを出し直す ([../decisions/20260929-phase2-validation-status.md](decisions/20260929-phase2-validation-status.md))
- `render_fragment(fragment, status: 200)`、`target`: 断片だけの応答と、`Shomen-Target` の id ([../decisions/20260929-phase4-fragment-request.md](decisions/20260929-phase4-fragment-request.md))
- `json(value, status: 200)` ([../decisions/20260929-phase4-json-response.md](decisions/20260929-phase4-json-response.md))
- `redirect(location, status: 303)` ([00-INSTRUCTION.md](00-INSTRUCTION.md#4-レスポンス))
- `sse(store, heartbeat: Shomen::SSE::HEARTBEAT) { fragment }`: イベントストリーム ([../decisions/20260929-phase5-sse-response.md](decisions/20260929-phase5-sse-response.md))
- `remember(id)`、`must_see`: 追記の後にセッションが覚える id と、この要求がそれより古い状態を見せてはならない id ([../decisions/20261001-phase7-remember-append.md](decisions/20261001-phase7-remember-append.md))
- `def validator(input : Input) : String`、`def cache_control : String`: GET ルートの弱い `ETag` と 304 ([../decisions/20261001-phase7-etag.md](decisions/20261001-phase7-etag.md))
- `cached(cache, name, *key) { fragment }`: `Shomen::FragmentCache` から取る断片 ([../decisions/20261001-phase7-fragment-cache.md](decisions/20261001-phase7-fragment-cache.md))

### `Shomen::Response`

- `status`, `content_type`, `body`, `headers` ([00-INSTRUCTION.md](00-INSTRUCTION.md#4-レスポンス))

### `Shomen::SSE`

- `sse` が返す応答。アプリケーションは自分で作らない。`Shomen::SSE::HEARTBEAT` はコメント行を送る間隔の既定値 ([../decisions/20260929-phase5-sse-response.md](decisions/20260929-phase5-sse-response.md))

### `Shomen::Island`

- `Shomen::Island.script "name", "file.js"`: アプリケーションの ES モジュールを `/islands/name.js` で配る ([../decisions/20260929-phase5-island-script.md](decisions/20260929-phase5-island-script.md))

### `Shomen::Server`

- `Shomen::Server.start(host: "127.0.0.1", port: 3000, https: false, reuse_port: false, shutdown_timeout: 25.seconds)`: SIGTERM か SIGINT まで動く ([00-INSTRUCTION.md](00-INSTRUCTION.md#5-サーバ), [../decisions/20260929-phase6-shutdown.md](decisions/20260929-phase6-shutdown.md))
- `https: true` でセッションクッキーを `Secure` にする ([../decisions/20260929-phase2-secure-cookie.md](decisions/20260929-phase2-secure-cookie.md)). `reuse_port: true` で 1 つのホストのプロセスがポートを共有する ([../decisions/20260929-scale-reuse-port.md](decisions/20260929-scale-reuse-port.md))
- `SHOMEN_SECRET`, `SHOMEN_SECRET_VERIFY`, `SHOMEN_ENV=production` ([../decisions/20260929-phase6-production.md](decisions/20260929-phase6-production.md), [../decisions/20260929-phase6-secret-verify.md](decisions/20260929-phase6-secret-verify.md))
- `Shomen::Server.new(secret, verify_secret, https)` と `call(context)`: ポートを使わないハンドラ。spec 用 ([00-INSTRUCTION.md](00-INSTRUCTION.md#tdd))

### `Shomen::Store`

- `Shomen::Store.new(url, poll_interval: 5.seconds, replica: nil)`: SQLite（`sqlite3://`）か Postgres（`postgres://`、`postgresql://`） ([../decisions/20260929-phase3-store-api.md](decisions/20260929-phase3-store-api.md), [../decisions/20260929-phase6-store-adapters.md](decisions/20260929-phase6-store-adapters.md), [../decisions/20261001-phase7-replica.md](decisions/20261001-phase7-replica.md))
- `append(stream, expected_version, events)`: 最後に追記したイベントの id を返す。ストリームの版と違えば `Shomen::Conflict` ([../decisions/20260929-phase3-store-api.md](decisions/20260929-phase3-store-api.md), [../decisions/20261001-phase7-remember-append.md](decisions/20261001-phase7-remember-append.md))
- `read(after, limit: 500)`: ある id より後の記録済みイベント ([../decisions/20260929-phase3-store-api.md](decisions/20260929-phase3-store-api.md))
- `last_appended`、`wait_for_append(after, within)`: 追記された最大の id と、ある id より後の追記の待ち ([../decisions/20260929-phase6-store-adapters.md](decisions/20260929-phase6-store-adapters.md)、[../decisions/20261001-phase7-append-watcher.md](decisions/20261001-phase7-append-watcher.md))
- `close`: コンシューマを止めた後に呼ぶ ([../decisions/20261001-phase7-consumer-api.md](decisions/20261001-phase7-consumer-api.md))

### `Shomen::Event`

- struct に `include Shomen::Event` と `event_type "name"`、`getter at : Time` を書く。名前が無いか重なればコンパイルエラー ([../decisions/20260929-phase3-event-type.md](decisions/20260929-phase3-event-type.md), [../decisions/20260929-scale-event-evolution.md](decisions/20260929-scale-event-evolution.md))

### `Shomen::Command`

- `include Shomen::Command` と `def call : Array(Shomen::Event) | Shomen::Rejected` ([../decisions/20260929-phase3-command-result.md](decisions/20260929-phase3-command-result.md))

### `Shomen::Recorded`

- `id`、`stream`、`version`、`event`: Store が保つ形のイベント ([../decisions/20260929-scale-event-stream.md](decisions/20260929-scale-event-stream.md))

### `Shomen::Rejected`

- `Shomen::Rejected.new(messages)`、`messages`: 入力が正しくないときにコマンドが返すもの ([../decisions/20260929-phase3-command-result.md](decisions/20260929-phase3-command-result.md))

### `Shomen::Projection`

- `Shomen::Projection.new(store)`、`def apply(recorded : Shomen::Recorded) : Nil`、`catch_up(must_see)`、`checkpoint`: メモリ上のリードモデル ([../decisions/20260929-phase3-projection-api.md](decisions/20260929-phase3-projection-api.md), [../decisions/20261001-phase7-replica.md](decisions/20261001-phase7-replica.md))

### `Shomen::Consumer`

- `Shomen::Consumer.new(store)`、`def name : String`、`create_tables(connection)`、`write(recorded, connection)`、`react(recorded)`、`run_once`、`start`、`stop`、`checkpoint`: 表に保つプロジェクション、またはリアクション ([../decisions/20261001-phase7-consumer-api.md](decisions/20261001-phase7-consumer-api.md)、[../decisions/20261001-phase7-consumer-batch.md](decisions/20261001-phase7-consumer-batch.md))
- `read(must_see, within: 2.seconds) { |connection| … }`: チェックポイントを待ち、読み取り用の接続を貸す ([../decisions/20261001-phase7-consumer-read.md](decisions/20261001-phase7-consumer-read.md))

### `Shomen::NotFound`

- 投げると 404 の HTML 文書になる ([../decisions/20260928-phase1-errors.md](decisions/20260928-phase1-errors.md))

### `Shomen::BadInput`

- 入力が無いか形が壊れているときに投げられる。400 の HTML 文書 ([../decisions/20260929-phase2-form-input.md](decisions/20260929-phase2-form-input.md))

### `Shomen::Forbidden`

- ルートが要求を拒むときに投げる。403 の HTML 文書 ([../decisions/20260929-phase2-csrf.md](decisions/20260929-phase2-csrf.md))

### `Shomen::Conflict`

- 古い版での `append` が投げる。ルートが扱わなければ 409 の HTML 文書 ([../decisions/20260929-phase3-conflict-response.md](decisions/20260929-phase3-conflict-response.md))

### `Shomen::Unavailable`

- 読み取りが上限内に `must_see` へ届かないときに投げられる。503 の HTML 文書 ([../decisions/20261001-phase7-consumer-read.md](decisions/20261001-phase7-consumer-read.md))

## Internal

アプリケーションはこれらの型を呼ばない。フレームワークの別のファイルが使うので公開になっているだけで、どの版でも変わりうる。

### `Shomen::CachedFragment`

前に描画した断片。`Shomen::FragmentCache` が渡す。

### `Shomen::ETag`

検証子から弱い `ETag` を作り、照合する。

### `Shomen::AppendSignal`

1 つの DB への追記を待つ、このプロセスのファイバーを起こす。

### `Shomen::AppendWatcher`

1 つの DB の通知を聞き、最大の id をポーリングする。

### `Shomen::StoreAdapter`

`Shomen::Store` のうち DB ごとに違う部分。

### `Shomen::StoreAdapter::Row`

追記する 1 つのイベントの型、ペイロード、時刻。

### `Shomen::StoreAdapter::Stored`

保存済みの 1 つのイベントの id、ストリーム、版、型、ペイロード。

### `Shomen::LibSQLite`

`crystal-sqlite3` が束ねていない SQLite の C 関数。

### `Shomen::SQLiteAdapter`

1 つの SQLite ファイルの Store アダプタ。

### `Shomen::PostgresAdapter`

1 つの Postgres DB の Store アダプタ。

### `Shomen::ErrorView`

エラー応答の HTML 文書。

### `Shomen::Session`

1 つの要求が運ぶセッション。id、CSRF トークン、覚えている追記。

### `Shomen::SessionStore`

セッションのクッキーに署名し、検証する。

### `Shomen::Router`

ルートを登録し、要求に合うものを探す。

### `Shomen::Router::Entry`

登録した 1 つのルート。

### `Shomen::Route::Hooks`

ルートの宣言から `handle` を作る。

### `Shomen::Island::Script`

`shomen.js` を配るルート。

### `Shomen::Island::Script::Input`

そのルートの空の入力。

### `Shomen::Connections`

1 つのサーバの接続。シャットダウンが待機中の接続を閉じるために使う。

### `Shomen::Connections::State`

接続が待機中か、要求を処理中か、ストリーム中か。

### `Shomen::Listener`

どのファイバーがどの接続を処理しているかを `Shomen::Connections` に知らせる `HTTP::Server`。
