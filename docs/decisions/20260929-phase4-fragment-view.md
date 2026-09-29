# 状況

仕様 4 は `render_fragment(view)` が文書の `<html>` を含まない断片を返すとする。01-ARCHITECTURE は断片ビューの根要素を 1 つとし、文書と断片を 1 クラスに詰め込まなくてよいとする。フェーズ 3 までの `Shomen::View` は、文書なら `html` マクロが出力をやり直し、そうでなければ呼ぶ側が `result` を返していた。

# 決定

`abstract class Shomen::Fragment < Shomen::View` を足す。サブクラスは `content : Nil` を実装する。`to_html` は `Fragment` が持ち、出力を空にしてから `content` を呼んで結果を返す。`Fragment` は `html` マクロを上書きし、断片の中で `html` を書くとコンパイルエラーにする。

`Shomen::View#embed(fragment : Shomen::Fragment)` で文書ビューに断片を埋め込む。`Shomen::Route#render_fragment(view : Shomen::Fragment, status = 200)` は断片だけを 200 の `text/html; charset=utf-8` で返す。`render` に `Shomen::Fragment` を渡すとコンパイルエラー、`render_fragment` に文書ビューを渡すと型が合わずコンパイルエラーになる。

根要素が 1 つであることは検査しない。

# 理由

文書と断片の取り違えは、JS 無しで断片だけが届く、または要素の中に文書が入れ子になる事故になる。型で分ければコンパイル時に止まる。`embed` で同じ断片クラスを文書と断片応答の両方で使えるので、「同じビューを断片として返せる」（仕様 8）を満たす。根要素の数は HTML を解析しないとわからず、`shomen.js` は応答から `id` で要素を探すので、数を強制しなくても動く。

# 破棄した案

- `render_fragment(view : Shomen::View)` で出力が `<!DOCTYPE` で始まるかを実行時に調べる（コンパイル時に止まらない）
- ビューに `fragment?` を渡して 1 クラスで文書と断片を切り替える（文書の骨組みと断片の中身が 1 つのメソッドに混ざる）
- 根要素の数を実行時に数える（HTML の解析が要る）
