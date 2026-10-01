# Phase 7d ETag and Fragment Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** フェーズ 7 の 4 本のサブ計画の最後。GET ルートの検証子から弱い `ETag` を作って一致すれば 304 を返し、描画した断片をプロセス内の上限つきキャッシュに置き、フェーズ 7 を締める。受入「A GET with a matching `If-None-Match` returns 304 and does not call the view」「After the session or the build changes, a GET with the old `ETag` gets a full 200 response」「Caching a fragment that contains the current CSRF token raises」「An application on SQLite runs unchanged. No feature in this phase requires a backing service besides the database」を満たす。

**Architecture:** ルートの `handle` が、GET ルートの `validator(input)` を `call` の前に呼び、`Shomen::ETag.tag(validator, csrf_token, target)` が `If-None-Match` に一致すれば 304 を返す。一致しなければ `call` の 200 に `ETag` と `Cache-Control` を付ける。ビルド ID はマクロの `run` で埋め込む（D1）。`Shomen::FragmentCache` はバイト数で上限を決めた LRU で、`Route#cached` がルートの CSRF トークンを渡し、描画した断片がトークンを含めば例外にする（D2）。

**Tech Stack:** Crystal `>= 1.20.0`（開発機は 1.21.1）、標準ライブラリだけ。shard は増やさない。

**Spec:** `docs/en/00-INSTRUCTION.md` の 10（スケールアウト）、`docs/en/02-PHASES.md` のフェーズ 7。既存の決定 `20260929-scale-etag.md`、`20260929-scale-fragment-cache.md`。この計画の Task 1 で足す決定:

- `docs/decisions/20261001-phase7-etag.md`（D1）
- `docs/decisions/20261001-phase7-fragment-cache.md`（D2）

## Global Constraints

- shard を足さない。DB 以外のサービスを使わない
- 既存の公開 API は変えない。`validator` を定義しないルートの応答は変わらない
- モジュール境界: `Shomen::ETag` と `Shomen::FragmentCache` は Store もセッションも知らない。Server は Route の検証子を知らない
- `examples/hello` のコードは変えない（SQLite のアプリはそのまま動く）
- テストは固定ポートを bind しない。sleep で同期しない
- ユーザーが指示するまで commit しない

## Review Focus

- 一致したら `call` を呼ばない。検証子は `call` より先に計算する（Task 3）
- `ETag` はセッション（CSRF トークン）、ビルド ID、`Shomen-Target` のどれが変わっても変わる（Task 2, 3）
- GET 以外のルートが `validator` を定義したらコンパイルエラー（Task 3）
- 200 以外の応答と SSE には `ETag` を付けない（Task 3）
- トークンを含む断片はキャッシュに置かず例外。キャッシュにある断片ではブロックを呼ばない（Task 4）
- バイト数の上限を超えたら最も長く使われていない断片から捨てる（Task 4）

## File Map

| ファイル | 役割 | Task |
|---|---|---|
| `docs/en/00-INSTRUCTION.md`、`docs/00-INSTRUCTION.md` | 仕様 10 | 1 |
| `docs/decisions/20261001-phase7-*.md` | D1、D2 | 1 |
| `src/shomen/build_id.cr`、`src/shomen/generate_build_id.cr`、`src/shomen/etag.cr` | ビルド ID、`ETag` の計算と照合 | 2 |
| `src/shomen/route.cr`、`src/shomen/response.cr` | 検証子、304 | 3 |
| `src/shomen/fragment_cache.cr`、`src/shomen/route.cr` | 断片キャッシュ、`cached` | 4 |
| `spec/support/etag_routes.cr`、`spec/fixtures/route_post_validator.cr`、`spec/fixtures/route_validator_not_string.cr`、`spec/fixtures/cached_bad_key.cr` | spec 用のルートとコンパイルエラーの例 | 3, 4 |
| `spec/shomen/etag_spec.cr`、`spec/shomen/fragment_cache_spec.cr` | 各 Task の spec | 2〜4 |
| `docs/en/02-PHASES.md`、`docs/02-PHASES.md`、`README.md`、`README.ja.md` | フェーズ 7 の締め | 5 |

---

### Task 1: 仕様と決定ファイル

- [x] D1、D2 を書く
- [x] 仕様 10 に `validator` と `FragmentCache`、`cached` を足す（英語と日本語訳）
- [x] 骨子の 7d の行にこの計画のファイル名を入れる

### Task 2: ビルド ID と `ETag`

**Files:** `src/shomen/build_id.cr`、`src/shomen/generate_build_id.cr`、`src/shomen/etag.cr`、`src/shomen.cr`、`spec/shomen/etag_spec.cr`（新規）

- [x] spec を先に書く: `BUILD_ID` は 32 文字の 16 進 / `tag` は `W/"…"` で、ビルド ID、トークン、target、検証子のどれが変わっても変わる / 区切りをずらした値は別の `ETag` / `match?` は同じ値、`W/` の有無、一覧の中の値、`*` で真、空、`nil`、別の値で偽
- [x] `Shomen::BUILD_ID`、`Shomen::ETag.tag(validator, csrf_token, target, build_id = BUILD_ID)`、`Shomen::ETag.match?(header, tag)`
- [x] `crystal spec spec/shomen/etag_spec.cr` が緑

### Task 3: ルートの検証子と 304

**Files:** `src/shomen/route.cr`、`src/shomen/response.cr`、`spec/support/etag_routes.cr`（新規）、`spec/spec_helper.cr`、`spec/fixtures/route_post_validator.cr`（新規）、`spec/shomen/etag_spec.cr`

- [x] spec を先に書く: 一致する `If-None-Match` は 304 で、`call` もビューも呼ばない / 一致しなければ 200 に `ETag` と `Cache-Control: private, no-cache` / ルートが付けた `Cache-Control` は残す / 検証子が `call` より先に呼ばれる / 検証子の無いルート、リダイレクト、SSE には `ETag` が無い / サーバ経由: 同じセッションで 304、セッションが変われば古い `ETag` で 200、別のビルド ID の `ETag` で 200 / `Shomen-Target` が違えば 200 / POST ルートの `validator` と、`String` を返さない `validator` はコンパイルエラー
- [x] `Shomen::Response.not_modified(tag)`
- [x] `Hooks.handle` の検証子の分岐と、200 への `ETag` の付与
- [x] 関係する spec が緑

### Task 4: 断片キャッシュ

**Files:** `src/shomen/fragment_cache.cr`、`src/shomen/route.cr`、`src/shomen.cr`、`spec/support/etag_routes.cr`、`spec/shomen/fragment_cache_spec.cr`（新規）

- [x] spec を先に書く: 同じキーの 2 回目はブロックを呼ばない / キーの値が違えば別の断片 / 型と長さで区切る / `String`、`Int32`、`Int64` 以外のキーはコンパイルエラー / トークンを含む断片は `ArgumentError` で、置かない / トークンが空なら確かめない / バイト数を超えたら最も長く使われていない断片を捨て、読んだ断片は新しくなる / 上限より大きい断片は置かない / `max_bytes` が正でなければ `ArgumentError` / ルートの `cached` は `embed` と `render_fragment` に渡せる / サーバ経由でトークン入りの断片は 500
- [x] `Shomen::CachedFragment`、`Shomen::FragmentCache`、`Route#cached`
- [x] 関係する spec が緑

### Task 5: フェーズ 7 の締め

- [x] `docs/en/02-PHASES.md` と訳の現行フェーズを「フェーズ 7 の受入を満たした」にする
- [x] README（英語と日本語）: 冒頭の段落と「Phases 1 to 6 are what run」の見出しをフェーズ 7 までにし、`validator` と `cached` を書き足す
- [x] `crystal tool format --check`、`crystal spec`、`PG=` 付き `crystal spec`、`crystal build src/shomen.cr --error-trace`、`examples/hello` の `crystal spec`
