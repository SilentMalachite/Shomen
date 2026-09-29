# 状況

`20260929-scale-projection-checkpoint.md` は、メモリ上のプロジェクションがチェックポイントを持ち、ビューが読む前に追いつくとした。クラスの形、いつ追いつくか、同時に追いつこうとしたとき、適用が失敗したときの扱いは決めていない。

# 決定

`abstract class Shomen::Projection` は `initialize(store : Shomen::Store)`、`abstract def apply(recorded : Shomen::Recorded) : Nil`、`checkpoint : Int64`（初期値 0）、`catch_up : self` を持つ。`catch_up` は `Mutex` の中で、`store.read(after: checkpoint, limit: BATCH)`（`BATCH = 500`）を、返った件数が `BATCH` より少なくなるまで繰り返す。1 件適用するたびにチェックポイントをその `id` に進める。`apply` が例外を投げたら、チェックポイントはその手前に留まり、例外をそのまま上げる。ルートは読む前に自分で `catch_up` を呼ぶ。起動時の再構築は、アプリが `Shomen::Server.start` の前に `catch_up` を呼ぶことで行う。

# 理由

`Mutex` があれば、同時に来た要求のファイバーが同じイベントを二度適用しない。1 件ごとにチェックポイントを進めれば、失敗したイベントを飛ばさず、適用済みのイベントを繰り返さない。サーバがすべてのプロジェクションを知って毎回追いつかせる仕組みは、フェーズ 3 の受入に要らない。`catch_up` が `self` を返すので、`NAMES.catch_up.find(id)` と 1 行で読める。

# 破棄した案

- バッチ単位でチェックポイントを進める（途中の失敗で適用済みを繰り返す）
- サーバが登録済みのプロジェクションを要求ごとに追いつかせる
- 読み取りもロックで囲む API（フェーズ 3 のサーバは 1 スレッドで動く）
- 起動時にスナップショットから始める
