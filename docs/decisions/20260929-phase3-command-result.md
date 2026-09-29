# 状況

仕様 7 は、コマンドが検証してイベントの列を返すとする。検証に失敗したときの返し方と、だれがストアに追記するかは決めていない。03-CONVENTIONS は、予想される 4xx を例外で流さないとする。01-ARCHITECTURE の表で、Store は Event にだけ依存してよい。

# 決定

`Shomen::Command` は `abstract def call : Array(Shomen::Event) | Shomen::Rejected` だけを持つ。`Shomen::Rejected` は利用者に見せるメッセージの配列 `messages : Array(String)` を持つ。ルートが結果を分岐する。`Shomen::Rejected` なら 422 でフォームを描き直し、イベントの配列なら `store.append(stream, expected_version, events)` を呼ぶ。コマンドはストアもストリーム名も知らない。

# 理由

union を返せば、呼び出し側は失敗の分岐をコンパイラに強制される。ストアがコマンドを知らなければ、モジュール境界の表を守れる。ストリーム名と期待する版はルートが持つ入力（パスの id とフォームの版）から決まるので、ルートが渡すのが最短である。

# 破棄した案

- 検証の失敗を例外にする
- `errors` と `call` を別のメソッドにする（`errors` を見ずに `call` できる）
- `Store#execute(command, expected_version)`（Store が Command に依存する）
- コマンドに `stream` を宣言させる（フェーズ 3 の受入に要らない）
