# 状況

仕様とアーキテクチャは、表の形、WAL、`BEGIN IMMEDIATE`、ファイルごとのロック、ビジータイムアウトを決めた。Store の公開 API は決めていない。フェーズ 6 では Postgres が同じコマンドの API で動く必要がある。

# 決定

- `Shomen::Store.new(url : String)`。フェーズ 3 はスキーム `sqlite3` だけを受け付ける。URL として読めないもの、ほかのスキーム、ファイル名が空、`:memory:`、ディレクトリは `ArgumentError`。ファイルを開けなければ、ファイル名を含む `DB::ConnectionRefused` にする。`events` 表を作れなければ、失敗した文をリセットし、開いた DB を閉じてから例外を上げる。`prepared_statements_cache` を `true` 以外にする URL は `ArgumentError`（文が解放されず、失敗した文をリセットできない）
- URL に無ければ `journal_mode=wal` と `busy_timeout=5000` を足す。URL にあればそれを使う
- ファイルの親ディレクトリが無ければ作る。`events` 表を `CREATE TABLE IF NOT EXISTS` で作る。マイグレーションの仕組みは作らない
- `append(stream : String, expected_version : Int64, events : Array(Shomen::Event)) : Nil`。空の配列は何もしない。空のストリーム名と負の版は `ArgumentError`。版の確認は `BEGIN IMMEDIATE` の中で `SELECT COALESCE(MAX(version), 0)` で行い、違えば `ROLLBACK` して `Shomen::Conflict` を投げる。`payload` と `at` の文字列はロックを取る前に作る
- `UNIQUE (stream, version)` に当たったときは、`SQLite3::Exception` をそのまま上げる。追記が直列なので、通常は版の確認が先に止める
- `read(after : Int64, limit : Int32 = 500) : Array(Shomen::Recorded)` は `id` が `after` より大きい行を `id` 順に返す
- 失敗した文は `ROLLBACK` の前後にリセットする。SQLite がすでにロールバックしていて `ROLLBACK` が失敗しても、元の例外を上げる
- `close : Nil`
- プロセス内のロックは、`File.realpath` で求めた実パスごとに 1 つの `Mutex` にする。`read` と `close` も同じロックを取る。`close` が、実行中の `append` や `read` の文を解放しないため

# 理由

URL にしておけば、フェーズ 6 で呼び出し側を変えずにスキームを足せる。`:memory:` は接続ごとに別の DB になり、接続プールと両立しない。crystal-sqlite3 は、失敗した文が残ると `close` で例外を投げるので、衝突は SQL の失敗ではなく版の確認で止める。`append` が最後の `id` を返すかどうかは、それを使うフェーズ 7 の read-your-writes で決める。

# 破棄した案

- ファイルパスだけを受け取る（フェーズ 6 で API が変わる）
- アダプタの抽象クラスを今作る（実装が 1 つしか無い）
- `UNIQUE` 違反を `Shomen::Conflict` に変換する（失敗した文が残る）
- `append` が最後の `id` を返す
