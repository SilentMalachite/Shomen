# 状況

GitHub に出す文書が、作業用の日本語仕様だけだった。README はフェーズ 0 向けの短い案内で、ライセンスファイルも無かった。`shard.yml` は MIT と書いている。

# 決定

仕様（`docs/en/00` から `03`）、`README.md`、`CONTRIBUTING.md` の正本は英語にする。日本語訳は従来の `docs/00-INSTRUCTION.md` から `docs/03-CONVENTIONS.md`、それに `README.ja.md` と `CONTRIBUTING.ja.md` に置く。食い違ったら英語を優先し、日本語を直す。決定ログと `docs/superpowers/` は日本語のままにする。ライセンス条文はルートの `LICENSE`（MIT）を正本にする。

# 理由

GitHub の初期画面は英語の README を出す。仕様を二か所で別々に育てると、実装がどちらに従うか分からなくなる。著者との作業メモは日本語のままの方が、これまでの決定ファイルとつながる。

# 破棄した案

- 仕様の正本を日本語のままにし、README だけ英語にする
- 日本語仕様を `docs/ja/` へ移動して、既存のリンクをすべて張り替える
- 決定ログも英語へ翻訳する
