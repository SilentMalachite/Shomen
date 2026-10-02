# 状況

フェーズ 8 は、`shard.yml` の版を `0.1.0` にし、タグはユーザーが指示したときだけ作ると決めた。`shard.yml` の `version` と `Shomen::VERSION` のどちらを正本にするか、`0.x` の間の公開 API の扱いは決めていない。

# 決定

- 版の正本は `shard.yml` の `version`。`Shomen::VERSION` は同じ文字列にし、spec が一致を確かめる
- フェーズ 8 で `0.1.0` にする
- `0.x` の間は、マイナー版で公開 API（`docs/en/04-API.md` の Application API）が変わりうる
- タグ（`v0.1.0`）はユーザーが指示したときだけ作る

# 理由

shards は依存を解くときに `shard.yml` の `version` とタグを読むので、そちらを正本にする。`Shomen::VERSION` を手で合わせ、spec でずれを止めれば、`src/` に新しい仕組みを足さずに済む。

# 破棄した案

- `Shomen::VERSION` をマクロで `shard.yml` から読む（`src/` に新しい仕組みを足すことになる）
