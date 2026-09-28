# フェーズ 0 — リポジトリ骨格

フェーズ 0 は、Crystal の shard としてインストールでき、`Shomen::VERSION` が空でないことを spec で確認できる骨格を置く。サーバ、ルート、HTML、例外型、永続化は置かない。

この文書は 2026-09-28 に承認した実装設計である。製品仕様の正本は `docs/00-INSTRUCTION.md`、`docs/01-ARCHITECTURE.md`、`docs/02-PHASES.md`、`docs/03-CONVENTIONS.md`、`AGENTS.md` である。フェーズ 0 の範囲は `docs/02-PHASES.md` に従い、そこで未指定だったビルド成果物の扱いをこの設計で決める。

## 公開 API

外部から使う名前は次の二つだけである。

- モジュール `Shomen`
- 定数 `Shomen::VERSION`。値は文字列 `"0.0.0"`

要求を受け付ける経路は無い。例外型もレスポンス型も定義しない。

## 置くファイル

手で置くのは次の 6 ファイルと、決定ログ 1 ファイルである。`README.md` と `LICENSE` は変更しない。`git init` も commit もこのフェーズの作業に含めない。

### `shard.yml`

```yaml
name: shomen
version: 0.0.0
license: MIT
crystal: ">= 1.20.0"
```

`authors`、`description`、`targets`、`dependencies` は書かない。

### `src/shomen/version.cr`

```crystal
module Shomen
  VERSION = "0.0.0"
end
```

### `src/shomen.cr`

```crystal
require "./shomen/version"

module Shomen
end
```

`require` のあとで同じ `Shomen` を再度開く。定数は `version.cr` 側に置く。

### `spec/spec_helper.cr`

```crystal
require "spec"
require "../src/shomen"
```

### `spec/shomen_spec.cr`

```crystal
require "./spec_helper"

describe Shomen do
  it "has a non-empty VERSION" do
    Shomen::VERSION.empty?.should be_false
  end
end
```

`it` は `"has a non-empty VERSION"` の 1 件だけである。この spec はサーバを起動せず、ポートも使わない。

### `.gitignore`

```gitignore
/lib/
/bin/
.shards/
*.dwarf
var/
```

パターンはこの 5 つだけである。各パターンは 1 行に 1 つ書き、ファイル末尾の改行以外の空行は置かない。

## 検証

コマンドはリポジトリルートで、この順に実行する。

1. `crystal tool format src/shomen.cr src/shomen/version.cr spec/spec_helper.cr spec/shomen_spec.cr`
2. `shards install` が終了コード 0 で終わる。このコマンドが生成する `shard.lock` は残す。手では書かない。依存は空である。`/lib/` は `.gitignore` に含まれる。
3. `crystal spec` が終了コード 0 で終わる。出力に warning は出ない。
4. `crystal build src/shomen.cr --error-trace` が終了コード 0 で終わる。出力に warning は出ない。
5. 手順 4 がリポジトリルートに出す実行ファイル `shomen` を削除する。削除後、ルートに `shomen` というファイルは無い。

同じビルドが `*.dwarf` を出した場合、そのファイルは `.gitignore` の対象なので削除しなくてよい。削除するのは実行ファイル `shomen` だけである。

## 決定ログ

`docs/decisions/20260928-build-artifact.md` を次の内容で置く。

````markdown
# 状況

`crystal build src/shomen.cr --error-trace` は、リポジトリルートで実行すると実行ファイル `shomen` をルートに出す。フェーズ 0 の `.gitignore` にこの名前は無い。

# 決定

検証のあと、ルートの実行ファイル `shomen` を削除する。`.gitignore` は次の 5 行のままにする。

```
/lib/
/bin/
.shards/
*.dwarf
var/
```

# 理由

検証コマンドは `AGENTS.md` の表記に合わせる。無視リストは `docs/02-PHASES.md` の指定に合わせる。

# 破棄した案

- `.gitignore` に `/shomen` を足す
- 出力先を `-o bin/shomen` に変える
````

## 受入

- `shards install` が終了コード 0 で終わる。
- `crystal spec` が終了コード 0 で終わり、出力に warning が無い。
- `crystal build src/shomen.cr --error-trace` が終了コード 0 で終わり、出力に warning が無い。そのあとルートに実行ファイル `shomen` が残っていない。
- サーバ、ルート DSL、HTML DSL のソースが無い。
- 本体 shard の依存が無い。`shard.yml` に `dependencies` が無く、フェーズ 3 用の `crystal-sqlite3` も入っていない。

## 制約

実装時は次も守る。

- 言語は Crystal 1.20 以上。`shard.yml` の下限は `>= 1.20.0`。
- フェーズ 0 で足してよい shard は無い。
- 公開 API は `Shomen::` 配下に置く。
- コードと識別子は英語。この文書と決定ログは日本語。
- フェーズ 1 以降のファイルは作らない。
- ユーザーが指示するまで commit しない。
- `crystal tool format` を通し、警告を残して完了にしない。
