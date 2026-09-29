# 状況

仕様 7 は、`type` 列にイベント型が宣言する名前を入れるとする（`20260929-scale-event-evolution.md`）。宣言の書き方、`payload` の作り方、行からイベントを読み戻す方法は決めていない。標準の `Time#to_json` は秒未満を落とす。

# 決定

`include Shomen::Event` した struct は、本体で `event_type "user_renamed"` と書いて名前を宣言する。引数は空でない文字列リテラルに限る。宣言の無い型と、2 つの型が同じ名前を宣言したプログラムは、コンパイルエラーにする。`Shomen::Event` は `JSON::Serializable` を include させ、`payload` はその JSON にする。読み戻しは `Shomen::Event.decode(type, payload)` が、`Shomen::Event` を include した型をマクロで列挙して行う。知らない名前は、名前を含む `ArgumentError` にする。`at` は `payload` と `at` 列のどちらも秒までの UTC の RFC 3339 にし、秒未満は保存しない。`at` が UTC でないイベントは、`Shomen::Store#append` が何も書かずに `ArgumentError` にする。

# 理由

宣言をマクロにすれば、書き忘れと重複をコンパイル時に止められる。`JSON::Serializable` は標準ライブラリで、既定値のあるフィールドを足しても古い行を読める。知らない名前を読み飛ばすと、リードモデルが黙って欠ける。秒未満を残すには独自の変換器が要り、イベントの順序は `id` が決めるので要らない。

# 破棄した案

- 実行時に型を登録する表（登録漏れが読むときまで見つからない）
- アノテーションで名前を付ける（書き忘れを検出する仕組みが別に要る）
- Crystal の型名をそのまま使う（改名で古い行が読めなくなる）
- 知らない名前の行を読み飛ばす
- 秒未満まで保存する変換器を入れる
- UTC でない `at` を追記のときに UTC へ直す（`payload` はイベント型の JSON なので、ストアが中の時刻を書き換えることになる）
