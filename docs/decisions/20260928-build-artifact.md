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
