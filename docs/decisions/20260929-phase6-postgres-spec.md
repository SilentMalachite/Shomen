# 状況

フェーズ 6 の受入のうち、Postgres での追記、ロックの待ち、2 プロセスでのフォームは、Postgres のサーバが無いと確かめられない。これまでの spec は、SQLite のファイルと Chrome（無ければ pending）だけで走った。

# 決定

環境変数 `SHOMEN_SPEC_POSTGRES` に、DB を作れるユーザーの Postgres の URL（例 `postgres://localhost/postgres`）を入れると、Postgres の spec が走る。未設定なら、その spec は pending にする（2026-09-29 の計画時にユーザーが選んだ）。フェーズ 6 の受入は、設定した状態で確かめる。

Postgres の例は、それぞれ `shomen_spec_` に 16 桁の 16 進を続けた名前の DB を作り、終わったら `DROP DATABASE ... WITH (FORCE)` で消す。SQLite と Postgres の両方で同じ振る舞いを確かめる例は `store_it` で書き、1 つの記述から DB ごとの例を作る。Postgres だけの例は `postgres_it`（Store を開いた DB）と `postgres_database_it`（空の DB）で書く。

# 理由

Postgres の無い環境でも `crystal spec` は緑のまま走り、Chrome が無いときと同じ扱いになる。例ごとに DB を分ければ、`id` はいつも 1 から始まり、プロセス内の `AppendSignal` も例ごとに別になる。1 つの DB を使い回すと URL が同じなので、前の例の最後の `id` が `AppendSignal` に残る。

# 破棄した案

- 未設定なら失敗にする（Postgres の無い環境で spec が赤になる）
- 1 つの DB を使い回し、例ごとに表を消す（`AppendSignal` の最後の `id` が例をまたいで残る）
- spec の中で Docker の Postgres を立てる（開発機に Docker が無く、DB 以外の道具を spec に持ち込む）
