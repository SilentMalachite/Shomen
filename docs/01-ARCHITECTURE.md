# 01 アーキテクチャ

> 日本語訳です。正本は [docs/en/01-ARCHITECTURE.md](en/01-ARCHITECTURE.md) です。食い違ったら英語に合わせ、このファイルを直します。

## 状態の置き場

既定: サーバーが文書を持つ。
例外: 島だけがブラウザで短い UI 状態を持つ。
永続化: イベントログが事実。リードモデルが画面の今。

クライアント全域の状態機械を作らない。

## リクエスト経路

```
HTTP 要求
  → Server（ヘッダ・セッション）
  → Router（method + path）
  → Input 構築（変換失敗は 400）
  → Route#call
  → Command（変更がある場合）
  → Event store 追記
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
| `Shomen::Store` | 追記と読取 | Event |
| `Shomen::Island` | 公式 JS の配信 | Server |

下位が上位を import しない。Store が HTML を知ってはいけない。HTML が SQLite を知ってはいけない。

## レンダリング

- 文書ビュー: `<!DOCTYPE html>` から書く
- 断片ビュー: 根要素 1 つ。`id` を持てると差し替えやすいが、フェーズ 1 では必須にしない
- 同じデータ型から文書と断片の両方を出してよい。無理に 1 クラスに詰め込まない

## 永続化

フェーズ 3:

- ファイル `var/shomen.sqlite3`（アプリ側でパス変更可）
- `events` テーブルのみ必須
- リードモデルは最初メモリ再構築でよい。起動時に全件適用。件数が増えてからスナップショットを足す

## 公式 JS

`src/shomen/assets/shomen.js` を静的に返す。ビルドステップ無し。外部 npm 無し。
