# 02 フェーズ

## 現行フェーズ

**フェーズ 1 — ルートと HTML とサーバ**

フェーズ 0 の受入は満たした。ここより先（フェーズ 2 以降）を実装しない。1 の受入を満たしたら停止し、ユーザーの次指示を待つ。

---

## フェーズ 0 — リポジトリ骨格

作るもの:

- `shard.yml`
- `src/shomen.cr`（`require` だけでもよいが、空モジュール `Shomen` を定義する）
- `src/shomen/version.cr`（`0.0.0`）
- `spec/spec_helper.cr`
- `spec/shomen_spec.cr`（VERSION が空でないこと）
- `.gitignore`（`/lib/`, `/bin/`, `.shards/`, `*.dwarf`, `var/`）

受入:

- `shards install` が通る
- `crystal spec` が緑
- フレームワーク機能（サーバ、DSL）はまだ無い

---

## フェーズ 1 — ルートと HTML とサーバ

作るもの:

- HTML DSL（仕様 3 の要素セット）
- テキストエスケープ
- a11y マクロのうち `button@type`, `img@alt`, 文書の `lang` と `title`
- Route 宣言、登録、path helper
- Server、200 / 404 / 500
- `examples/hello`（`GET /` が `<h1>Hello</h1>` を含む文書を返す）

受入:

- 指示書 TDD 節の 1–6 を満たす
- `examples/hello` を `crystal run` し、ローカルで HTML が返る
- 本体 shard に外部依存が無い

---

## フェーズ 2 — フォームとセッション

作るもの:

- `form` POST の Input 束縛（urlencoded）
- 検証エラー時に同じフォームを 422 で描画できること
- 署名セッションクッキー
- CSRF: セッションに紐づくトークン。POST で不一致なら 403
- `input` のコンパイル時ラベル検査（同一ビュー内の `for` / ラップ、または `aria-label`）。フェーズ 1 は `input` 要素を出すだけで、この検査はしない

受入:

- フォームを 1 つ持つ example が、投稿後に値を再表示できる
- CSRF 無し POST が 403
- セッションが無い応答に Set-Cookie が付く

---

## フェーズ 3 — コマンドとイベントと SQLite

作るもの:

- Command / Event の型
- SQLite 追記ストア
- 起動時リードモデル再構築
- example: 名前を変更してイベントが 1 行増える

受入:

- 同じコマンドを 2 回扱うと events が 2 行（上書きではない）
- 再起動後もリードモデルが復元される
- Store が HTML を import していない

---

## フェーズ 4 — 断片と fetch

作るもの:

- `render_fragment`
- `shomen.js` の `data-shomen-get` / `data-shomen-post` と対象 `id` 差し替え
- JSON 応答は、ルートが明示したときだけ

受入:

- JS 無効でもフェーズ 2 のフォームは動く
- JS 有効では、指定要素だけが差し替わる
- 公式 JS に npm 依存が無い

---

## フェーズ 5 — SSE と島

作るもの:

- オプトイン SSE
- `data-shomen-island`
- 島は example 1 つ（カウンタ程度）

受入:

- SSE 未使用アプリが追加依存を持たない
- 島の外にフレームワークがイベントリスナをばらまかない

---

## フェーズ 6 — Postgres と本番寄せ

作るもの:

- Store の Postgres アダプタ
- `SHOMEN_ENV=production` で例外本文を隠す
- 最低限の CSP

受入:

- SQLite と Postgres を同じ Command API で使える
- example の既定は SQLite のまま

このフェーズはユーザーが明示するまで開始しない。
