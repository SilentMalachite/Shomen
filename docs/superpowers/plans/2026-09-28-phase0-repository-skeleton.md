# Phase 0 Repository Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Crystal の shard としてインストールでき、`Shomen::VERSION` が `"0.0.0"` であることを確認できるフェーズ 0 の骨格を置く。

**Architecture:** `src/shomen.cr` が `src/shomen/version.cr` を require し、モジュール `Shomen` を開く。定数 `VERSION` は `version.cr` に置く。spec はその定数が空でないことを 1 件だけ見る。パッケージ名と Crystal の下限は `shard.yml` に書き、依存は置かない。ビルドがルートに出す実行ファイル `shomen` は検証のあと削除し、その方針は決定ログに残す。

**Tech Stack:** Crystal `>= 1.20.0`、Shards、標準ライブラリの `spec`。外部 shard は無い。

**Spec:** `docs/superpowers/specs/2026-09-28-phase0-repository-skeleton-design.md`

## Global Constraints

- 言語は Crystal 1.20 以上。`shard.yml` の下限は `>= 1.20.0`。
- フェーズ 0 で足してよい shard は無い。
- 公開 API は `Shomen::` 配下に置く。
- コードと識別子は英語。この文書と決定ログは日本語。
- フェーズ 1 以降のファイルは作らない。
- ユーザーが指示するまで commit しない。
- `crystal tool format` を通し、警告を残して完了にしない。

実行はリポジトリルートで行う。この計画に commit 手順は無い。`git init` もしない。作業開始時点のルートは git リポジトリではない。

## Review Focus

- `Shomen::VERSION` が空でない別の文字列になる。期待は文字列 `"0.0.0"`。Task 1 の Step 6 で固定する。
- `shard.yml` または `shard.lock` に依存が入る。期待は `dependencies` キーが無く、`shard.lock` が `shards: {}` である。Task 2 の Step 3 で固定する。
- `crystal spec` または `crystal build` が warning を出す。期待はどちらの出力にも `Warning` が無い。Task 1 の Step 5 と Task 3 の Step 4 で固定する。
- `src/shomen/server.cr`、`src/shomen/route.cr`、`src/shomen/html.cr`、`examples/hello` のどれかがある。期待はどれも無い。Task 3 の Step 3 で固定する。
- `crystal build src/shomen.cr --error-trace` のあと実行ファイル `./shomen` が残る。期待は削除後にこのファイルが無い。`shomen.dwarf` は残ってよい。Task 3 の Step 4 で固定する。

## File Map

| ファイル | 役割 |
|---|---|
| `src/shomen/version.cr` | `Shomen::VERSION = "0.0.0"` |
| `src/shomen.cr` | ライブラリ入口。version を require し、`Shomen` を再度開く |
| `spec/spec_helper.cr` | `spec` と `../src/shomen` を require する |
| `spec/shomen_spec.cr` | example `"has a non-empty VERSION"` の 1 件 |
| `shard.yml` | name、version、license、crystal 下限。依存キーは無い |
| `.gitignore` | `/lib/`、`/bin/`、`.shards/`、`*.dwarf`、`var/` |
| `docs/decisions/20260928-build-artifact.md` | ルートの実行ファイル `shomen` を検証後に削除する決定 |
| `shard.lock` | `shards install` が生成する。手では書かない |

手で変更しないファイルは `README.md`、`LICENSE`、`docs/decisions/README.md`、既存の `docs/00-INSTRUCTION.md` から `docs/03-CONVENTIONS.md`、`AGENTS.md`、`CLAUDE.md` である。

---

### Task 1: Shomen::VERSION

**Files:**

- Create: `spec/spec_helper.cr`
- Create: `spec/shomen_spec.cr`
- Create: `src/shomen/version.cr`
- Create: `src/shomen.cr`
- Test: `spec/shomen_spec.cr`

**Interfaces:**

- Consumes: なし
- Produces: モジュール `Shomen`。定数 `Shomen::VERSION : String`。値は `"0.0.0"`

- [ ] **Step 1: Write the failing test**

先に `mkdir -p spec src/shomen` を実行する。

`spec/spec_helper.cr` を作る。

```crystal
require "spec"
require "../src/shomen"
```

`spec/shomen_spec.cr` を作る。

```crystal
require "./spec_helper"

describe Shomen do
  it "has a non-empty VERSION" do
    Shomen::VERSION.empty?.should be_false
  end
end
```

`it` はこの 1 件だけにする。サーバは起動しない。

- [ ] **Step 2: Run the test and verify it fails**

`src/shomen.cr` がまだ無い状態で、リポジトリルートから次を実行する。

```bash
set -euo pipefail
status=0
crystal spec > /tmp/shomen-phase0-red.txt 2>&1 || status=$?
cat /tmp/shomen-phase0-red.txt
test "$status" -eq 1
grep -q "can't find file '../src/shomen'" /tmp/shomen-phase0-red.txt
```

Expected: このシェルは終了コード 0。`crystal spec` は終了コード 1 で、出力に `Error: can't find file '../src/shomen'` がある。

- [ ] **Step 3: Write the minimal implementation**

`src/shomen/version.cr` を作る。

```crystal
module Shomen
  VERSION = "0.0.0"
end
```

`src/shomen.cr` を作る。

```crystal
require "./shomen/version"

module Shomen
end
```

- [ ] **Step 4: Run the test and verify it passes**

```bash
set -euo pipefail
status=0
crystal spec > /tmp/shomen-phase0-spec.txt 2>&1 || status=$?
cat /tmp/shomen-phase0-spec.txt
test "$status" -eq 0
! grep -q 'Warning' /tmp/shomen-phase0-spec.txt
grep -q '1 examples, 0 failures, 0 errors, 0 pending' /tmp/shomen-phase0-spec.txt
```

Expected: このシェルは終了コード 0。出力に `1 examples, 0 failures, 0 errors, 0 pending` があり、`Warning` は無い。

- [ ] **Step 5: Format and re-run the spec**

```bash
set -euo pipefail
crystal tool format src/shomen.cr src/shomen/version.cr spec/spec_helper.cr spec/shomen_spec.cr
crystal tool format --check src/shomen.cr src/shomen/version.cr spec/spec_helper.cr spec/shomen_spec.cr
status=0
crystal spec > /tmp/shomen-phase0-spec.txt 2>&1 || status=$?
cat /tmp/shomen-phase0-spec.txt
test "$status" -eq 0
! grep -q 'Warning' /tmp/shomen-phase0-spec.txt
grep -q '1 examples, 0 failures, 0 errors, 0 pending' /tmp/shomen-phase0-spec.txt
```

Expected: `crystal tool format --check` とスクリプト全体が終了コード 0。spec の出力に `Warning` は無い。

- [ ] **Step 6: Pin the version string**

```bash
crystal eval 'require "./src/shomen"; abort("bad version") unless Shomen::VERSION == "0.0.0"; puts "version-ok"'
```

Expected: 終了コード 0。標準出力は `version-ok`。

### Task 2: shard.yml

**Files:**

- Create: `shard.yml`
- Create: `shard.lock`（`shards install` が生成する。手では書かない）

**Interfaces:**

- Consumes: なし。インストール解決はソースの中身をコンパイルしない
- Produces: shard 名 `shomen`、version `0.0.0`、license `MIT`、crystal `>= 1.20.0`。依存パッケージは 0 件。`shard.lock` の依存マップは `shards: {}`

- [ ] **Step 1: Write shard.yml**

`shard.yml` を作る。

```yaml
name: shomen
version: 0.0.0
license: MIT
crystal: ">= 1.20.0"
```

`authors`、`description`、`targets`、`dependencies` は書かない。ファイル末尾は改行 1 つにする。

- [ ] **Step 2: Run shards install**

```bash
set -euo pipefail
status=0
shards install > /tmp/shomen-phase0-shards.txt 2>&1 || status=$?
cat /tmp/shomen-phase0-shards.txt
test "$status" -eq 0
grep -q 'Writing shard.lock' /tmp/shomen-phase0-shards.txt
```

Expected: このシェルは終了コード 0。出力に `Writing shard.lock` がある。

- [ ] **Step 3: Pin metadata and an empty dependency list**

```bash
set -euo pipefail
diff -u - shard.yml <<'EOF'
name: shomen
version: 0.0.0
license: MIT
crystal: ">= 1.20.0"
EOF
diff -u - shard.lock <<'EOF'
version: 2.0
shards: {}
EOF
! grep -q 'crystal-sqlite3' shard.yml shard.lock
```

Expected: 両方の `diff` が終了コード 0。`crystal-sqlite3` はどちらのファイルにも無い。`shard.lock` は削除しない。

### Task 3: gitignore、決定ログ、受入

**Files:**

- Create: `.gitignore`
- Create: `docs/decisions/20260928-build-artifact.md`
- Test: フェーズ 0 の受入コマンド一式

**Interfaces:**

- Consumes: Task 1 の `src/shomen.cr` と `Shomen::VERSION`。Task 2 の `shard.yml`
- Produces: 無視パターン 5 行。決定ログ 1 ファイル。検証後の作業ツリーに実行ファイル `./shomen` が無い状態

- [ ] **Step 1: Write .gitignore**

`.gitignore` を作る。

```gitignore
/lib/
/bin/
.shards/
*.dwarf
var/
```

パターンはこの 5 つだけにする。各パターンは 1 行に 1 つ書き、ファイル末尾の改行以外の空行は置かない。

- [ ] **Step 2: Write the decision log**

`docs/decisions/20260928-build-artifact.md` を作る。

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

書いたあと、内容が一致することを確認する。

```bash
set -euo pipefail
diff -u - docs/decisions/20260928-build-artifact.md <<'EOF'
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
EOF
diff -u - .gitignore <<'EOF'
/lib/
/bin/
.shards/
*.dwarf
var/
EOF
```

Expected: 両方の `diff` が終了コード 0。

- [ ] **Step 3: Confirm phase 1 files are absent**

```bash
set -euo pipefail
test ! -e src/shomen/server.cr
test ! -e src/shomen/route.cr
test ! -e src/shomen/html.cr
test ! -e examples/hello
find src spec -type f | sort > /tmp/shomen-phase0-files.txt
diff -u - /tmp/shomen-phase0-files.txt <<'EOF'
spec/shomen_spec.cr
spec/spec_helper.cr
src/shomen.cr
src/shomen/version.cr
EOF
```

Expected: 終了コード 0。`src` と `spec` にあるファイルはこの 4 つだけである。

- [ ] **Step 4: Run phase 0 acceptance and remove the binary**

リポジトリルートで、この順に実行する。

```bash
set -euo pipefail
crystal tool format src/shomen.cr src/shomen/version.cr spec/spec_helper.cr spec/shomen_spec.cr
crystal tool format --check src/shomen.cr src/shomen/version.cr spec/spec_helper.cr spec/shomen_spec.cr

status=0
shards install > /tmp/shomen-phase0-shards.txt 2>&1 || status=$?
cat /tmp/shomen-phase0-shards.txt
test "$status" -eq 0

status=0
crystal spec > /tmp/shomen-phase0-spec.txt 2>&1 || status=$?
cat /tmp/shomen-phase0-spec.txt
test "$status" -eq 0
! grep -q 'Warning' /tmp/shomen-phase0-spec.txt
grep -q '1 examples, 0 failures, 0 errors, 0 pending' /tmp/shomen-phase0-spec.txt

status=0
crystal build src/shomen.cr --error-trace > /tmp/shomen-phase0-build.txt 2>&1 || status=$?
cat /tmp/shomen-phase0-build.txt
test "$status" -eq 0
! grep -q 'Warning' /tmp/shomen-phase0-build.txt
test -f ./shomen
test -x ./shomen

rm -f ./shomen
test ! -e ./shomen
```

Expected: このシェルは終了コード 0。`crystal spec` の出力に `1 examples, 0 failures, 0 errors, 0 pending` があり、spec と build の出力に `Warning` は無い。`./shomen` はビルド直後に存在し、`rm` のあと存在しない。`shomen.dwarf` が出ても削除しない。このファイルは `.gitignore` の `*.dwarf` に該当する。

このタスクのあと、commit はしない。
