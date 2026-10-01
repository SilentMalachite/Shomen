# 01 アーキテクチャ

> 日本語訳です。正本は [docs/en/01-ARCHITECTURE.md](en/01-ARCHITECTURE.md) です。食い違ったら英語に合わせ、このファイルを直します。

## 状態の置き場

既定: サーバーが文書を持つ。
例外: 島だけがブラウザで短い UI 状態を持つ。
永続化: イベントログが事実。リードモデルが画面の今。
プロセス: 他のプロセスが必要とする状態を持たない。メモリ上のリードモデルは、イベントログから追いつく写しである。

クライアント全域の状態機械を作らない。

## リクエスト経路

```
HTTP 要求
  → Server（ヘッダ・セッション）
  → Router（method + path）
  → Input 構築（変換失敗は 400）
  → Route#call
  → Command（変更がある場合）
  → Event store 追記（版の衝突は 409）
  → Projection が最新の id まで追いつく
  → View
  → Response
```

読み取り専用 GET は Command を経由しない。

## モジュール境界

| モジュール | 責務 | 依存してよい先 |
|---|---|---|
| `Shomen::HTML` | DSL とエスケープと a11y マクロ | なし |
| `Shomen::Route` | 宣言、Input、path helper | HTML, Response |
| `Shomen::Server` | bind、照合、書き出し | Route, Session |
| `Shomen::Session` | 署名クッキー | なし |
| `Shomen::Command` / `Event` | 意図と事実の型 | なし |
| `Shomen::Store` | 追記と読取。追記を待つものを、このプロセスの追記ではすぐに、ほかのプロセスの追記では通知とポーリングで起こす | Event |
| `Shomen::Projection` | チェックポイントより後のイベントを適用 | Event, Store |
| `Shomen::Consumer` | 要求の外でプロジェクションや反応を動かす | Projection, Command, Store |
| `Shomen::Island` | 公式 JS と島のモジュールの配信 | Route |
| `Shomen::SSE` | Store が知った追記のたびに断片を送り直す | Response, Store, Fragment |

下位が上位を import しない。Store が HTML を知ってはいけない。HTML が SQLite を知ってはいけない。

## レンダリング

- 文書ビュー: `<!DOCTYPE html>` から書く
- 断片ビュー（`Shomen::Fragment`）: 根要素 1 つ。数は検査しない。`shomen.js` は `Shomen-Target` と同じ `id` の要素を差し替えるので、差し替える断片はその `id` を持つ
- 同じデータ型から文書と断片の両方を出してよい。無理に 1 クラスに詰め込まない

## 永続化

フェーズ 3:

- ファイル `var/shomen.sqlite3`（アプリ側でパス変更可）。読み手が書き手を止めないよう WAL モードにする
- 追記は `BEGIN IMMEDIATE` で行う。SQLite のビジー待ちはスレッドごと止めるので、プロセス内では、1 つのファイルへの書き込みの前に、ファイバーが待てるプロセス全体のロックを取る。プロセスをまたぐときは、ビジータイムアウトで失敗せずに互いを待つ。書き込みトランザクションの中で副作用を実行しない（`docs/decisions/20260929-scale-sqlite-writes.md`）
- 追記は、ストリームのいまの版の確認と挿入を同じトランザクションで行う
- `events` テーブルのみ必須（仕様 7）
- プロジェクションはメモリに置いてよい。起動時に `id` 1 から全件適用する。ビューが読む前に、チェックポイントより後のイベントを適用する
- Store は `crystal-db` を通して DB に触れる。SQLite と Postgres のアダプタは SQL と列の型が違い、通知を送るのは Postgres だけ。コマンド、イベント、プロジェクションはどちらが動いているかを知らない

フェーズ 6:

- `Shomen::Store.new(url)` は URL のスキームでアダプタを選ぶ。`sqlite3` なら SQLite、`postgres` か `postgresql` なら Postgres。`max_pool_size` を書かない Postgres の URL は、接続 10 本のプールになる（`docs/decisions/20260929-phase6-store-adapters.md`、`docs/decisions/20260929-phase6-postgres-adapter.md`）
- Postgres アダプタも同じ `events` テーブルを作り、整数の列を `BIGINT` にする。`id` は `CACHE 1` の identity
- 追記は、挿入の前に固定の 1 つのキーでトランザクション単位のアドバイザリロックを取り、挿入後すぐにコミットする。そのため id は増える順に見える（`docs/decisions/20260929-scale-event-order.md`）

フェーズ 7:

- プロジェクションは、行とチェックポイントを表に置き、コンシューマが更新してよい。形を変えるときは、新しい名前のプロジェクションを `id` 1 から作り、読み先を切り替えてから古い表を消す。リードモデルをその場でマイグレーションしない（`docs/decisions/20260929-scale-projection-rebuild.md`）
- コンシューマのチェックポイントは `consumers(name TEXT PRIMARY KEY, checkpoint INTEGER NOT NULL)`（Postgres では `BIGINT`）に置く。バッチは、Postgres ではその行をロックし、SQLite ではその値を比べる

## プロセス

フェーズ 6–7:

```
ロードバランサ
  → プロセス 1 … プロセス N   （同じビルド、同じ SHOMEN_SECRET）
      → Postgres primary       （追記、通知、コンシューマのチェックポイント）
      → Postgres replica       （読み取り、フェーズ 7）
```

- CPU コアごとに 1 プロセス動かす。1 ホストのプロセスは `reuse_port` でポートを共有するか、別々のポートでロードバランサの後ろに並べる
- プロセスは、メモリ上のプロジェクションが追いついてから要求を受ける
- デプロイはプロセスを 1 つずつ入れ替える。SIGTERM を受けたプロセスは、受け付け済みの要求を終えてから終了する

## 公式 JS

`src/shomen/assets/shomen.js` を静的に返す。ビルドステップ無し。外部 npm 無し。

島のモジュールはアプリのファイルである。`Shomen::Island.script` がコンパイル時に読み、`/islands/<name>.js` で配る。`shomen.js` は `data-shomen-island` の要素があるときだけそれを読み込む（`docs/decisions/20260929-phase5-island-script.md`）。
