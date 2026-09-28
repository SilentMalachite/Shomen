# AGENTS.md

Grok Build と Claude Code の共通ルール。両ツールともこのファイルを正本にする。
詳細仕様の正本は `docs/en/00-INSTRUCTION.md`。日本語訳は `docs/00-INSTRUCTION.md`。チャット履歴は正本ではない。

## 役割

Shomen を Crystal 1.20 以上で実装する。既存の Amber / Lucky / Kemal / Marten を土台にしない。標準ライブラリと、仕様が明示した shard 以外は足さない。

## 着手順

1. このファイル
2. `docs/en/00-INSTRUCTION.md`（日本語訳は `docs/00-INSTRUCTION.md`）
3. `docs/en/01-ARCHITECTURE.md`
4. `docs/en/02-PHASES.md` の現行フェーズだけ
5. `docs/en/03-CONVENTIONS.md`

今やるフェーズは `docs/en/02-PHASES.md` の先頭にある「Current phase」に従う。指定より先のフェーズを実装しない。

## やってはいけないこと

- 仕様に無い機能を足す
- 「あると便利」なジェネレータ、プラグイン機構、管理画面、テーマ、GraphQL、SPA ルーターを先に作る
- Lucky / Amber / Rails 互換レイヤを作る
- 既存フレームワークを wrap して完成扱いにする
- README やコメントで仕様を再発明する。仕様変更は `docs/en/` を先に直し、日本語訳も同じ変更で更新する
- コミットやタグを勝手に増やさない（ユーザーが指示したときだけ）
- サンプルアプリをフレームワーク本体に埋め込む。サンプルは `examples/` のみ
- JavaScript バンドラを本体のビルドに必須にしない

## やってよいこと

- フェーズ内の未指定の細部は、コンパイル時安全性と最小実装を優先して決める
- 決めた細部は `docs/decisions/` に 1 決定 1 ファイルで追記する
- テストが落ちる状態で次のファイル群に進まない

## 実装単位

1 回の作業で触るのは、現行フェーズの受入条件を満たす最小セット。
大きなリファクタは、ユーザーが依頼したときか、現行フェーズの受入条件を壊しているときだけ。

## 検証

毎回:

```sh
crystal spec
crystal build src/shomen.cr --error-trace
```

フェーズ 0 完了後は加えて:

```sh
cd examples/hello && shards install && crystal spec
```

（hello がまだ無いフェーズでは examples を走らせない）

## 言語

- コード・識別子・コミットメッセージ案は英語
- 仕様と GitHub 向け README / CONTRIBUTING の正本は英語。日本語訳を併置し、食い違ったら英語に合わせる
- 決定ログ、`docs/superpowers/`、このファイルは日本語
- ユーザーへの進捗説明は日本語

## 不明点

仕様と矛盾する要求が来たら、実装せず `docs/` の該当節を引用して止める。
推測で言語・DB・レンダリングモデルを変えない。
