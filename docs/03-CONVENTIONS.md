# 03 規約

## コード

- 公開型は `Shomen::` 配下
- 1 ファイル 1 主要型を原則にする
- メソッドは短く。マクロは DSL とルート登録に限る
- `nil` を隠して落とさない。入力欠落は `BadInput`
- 例外で制御流を増やしすぎない。想定内の 4xx は Response で返す

## 命名

- ルート: `リソース::動詞`（`Users::Show`, `Users::Update`）
- ビュー: `ルート名View`（`Users::ShowView`）
- コマンド: 動詞過去形にしない。意図は現在形（`RenameUser`）
- イベント: 過去形（`UserRenamed`）

## 文書

- 仕様変更はコードより先に `docs/` を直す
- 決定は `docs/decisions/YYYYMMDD-short-name.md`
- 決定ファイルの中身は「状況 / 決定 / 理由 / 破棄した案」だけ

## Git

- ユーザーが指示するまで commit しない（エージェント既定）
- する場合の題名は英語、本文は必要なら日本語

## 品質

- `crystal tool format` を通す
- 警告を残してフェーズ完了にしない
- テストから sleep で同期しない
