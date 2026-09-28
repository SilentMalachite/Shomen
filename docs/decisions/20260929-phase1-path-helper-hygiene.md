# 状況

パラメータ付き path helper は `String.build do |io|` の中へ引数式を展開する。呼び出し側に `io` という変数があると、引数式の `io` がそのブロック引数を指す。

# 決定

path helper のバッファ引数は `%io` にする。`%component` と同じく、マクロが展開先と衝突しない名前にする。

# 理由

`Labels::Show.path(name: io.upcase)` が、呼び出し側の文字列ではなく構築中のバッファを受け取る。型検査は `String::Builder` に `upcase` が無い、で失敗する。

# 破棄した案

- ブロック引数名を `io` のままにする
- 衝突しにくそうな長い名前を手で付ける
