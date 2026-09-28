# 状況

フェーズ 2 の受入は、フォームを 1 つ持つ例が、送信後に値を表示し直すことである。AGENTS.md の検証コマンドは `examples/hello` だけを走らせる。

# 決定

`examples/hello` に `Greeting::Edit`（`GET /greeting`）と `Greeting::Update`（`POST /greeting`）を足す。名前が 2 文字未満なら、送った値を入れたまま 422 でフォームを描き直す。2 文字以上なら 303 で `/greeting` に戻す。

# 理由

例を増やさずに、既存の検証コマンドで受入を確かめられる。値の表示し直しは 422 の描き直しで確かめられる。

# 破棄した案

- `examples/form` を新しく作る
- 成功時の値をセッションに入れて表示する（ルートが Session を読めない）
