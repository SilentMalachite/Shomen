# 状況

ルートの登録漏れと二重登録は、コンパイル失敗か起動失敗のどちらかにする必要がある。path helper は `Hello::Show.path` のようにルートクラスから呼べる。`:id` は `Input` の同名フィールドへ束縛し、変換失敗は 400 にする。指示書のクラス本体は `method`、`path`、`struct Input`、`call` の順である。

# 決定

具象サブクラスは `macro inherited` で `Shomen::Route::Hooks` を include し、`handle` をそのクラス自身に定義する。`method` は `GET` `POST` `PUT` `PATCH` `DELETE` `HEAD` だけを受け、`VERB` 定数と `self.verb` を置く。`path` は `/` で始まる文字列リテラルだけを宣言として受け、`PATH` 定数と `self.pattern` を置く。引数なし、またはキーワード引数の `path` 呼び出しは path helper である。静的 path は宣言文字列を返し、パラメータは `URI.encode_path_segment` で 1 セグメントにする。値に `/`、`?`、`#` が含まれるとき、または値が `.` か `..` のときは `ArgumentError`。ブラウザは `.` と `..` のセグメントを解決して消すので、リンクが別の path を指す。照合とキャプチャは宣言と同じ `String#split("/")` を使う。`"/"` の split は `["", ""]` である。空のキャプチャセグメントは不一致。クエリは `HTTP::Request#path` に含まれないので照合しない。

`handle` は path パラメータと `Input` のインスタンス変数が名前も個数も一致することをコンパイル時に検査する。型は `String`、`Int32`、`Int64` だけ。整数へ変換できない値は `Shomen::BadInput` を上げる。ルート表は `Shomen::Route.all_subclasses` を `Router.entries` の初回呼び出しで走査して作る。具象サブクラスに `VERB` または `PATH` が無いときは、その走査のコンパイルに失敗する。同じメソッドかつ同じ shape（パラメータ名を `:` に潰した path）は `duplicate route` で起動失敗する。リテラルセグメントが多いルートを優先する。`src/shomen/handler.cr` は作らず、`Shomen::Server` が `HTTP::Handler` を include する。

# 理由

`macro finished` の実行時コードはファイル末尾に回る。`Server.start` が listen すると、その登録は走らない。`instance_vars` はトップレベルのマクロ展開では呼べないので、path helper ではなく `handle` の中で Input を検査する。shape で比べると `/users/:id` と `/users/:name` を二重登録にできる。

# 破棄した案

- クラス定義の実行時に `macro finished` で `Router.add` する
- path helper の呼び出し位置で `instance_vars` を読み、`.as(Int32)` する
- サブクラス一覧をアプリが手で渡す
- メソッド違いを 405 にする
