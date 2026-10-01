# Phase 7a Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PR #9 に対する Codex レビューの指摘 4 件を直す。(1) Store を閉じた後にポーリングが DB 接続を開き直して残す、(2) 停止の上限 5 秒が終了用の SQL には効かない、(3) 停止を諦めた後に開いた LISTEN 接続が残る、(4) ロールバックした追記の通知と、つなぎ直しの待ちの伸び方にテストが無い。

**Architecture:** `Shomen::AppendWatcher#stop` は、ポーリングと受信のファイバーが終わるのを上限つきで待つ。ファイバーは終わるときにチャネルを閉じて知らせる（閉じたチャネルは待つ側の全員を起こす）。受信の接続の切断は `stop` とは別のファイバーで繰り返し、`stop` が上限で戻った後も受信のファイバーが終わるまで続ける。Postgres の切断の SQL は、プールではなく、その場で開いて閉じる専用の接続で実行する。つなぎ直しの待ちの計算は純粋な関数にしてテストする。

**Tech Stack:** Crystal 1.21.1、`pg` 0.30.0、`db` 0.14.0。`crystal-db` の `Database#close` は閉じた状態を持たず、閉じた後の問い合わせは新しい接続を作る（`lib/db/src/db/pool.cr:89`、`checkout`）。`crystal-pg` 0.30.0 の接続 URL は `connect_timeout` を受け付けない。

**Spec:** `docs/en/00-INSTRUCTION.md` 10、`docs/decisions/20261001-phase7-append-watcher.md`（D1）、`docs/decisions/20261001-phase7-notify-channel.md`（D2）、元の計画 `docs/superpowers/plans/2026-10-01-phase7a-notify-sse.md`。

## Global Constraints

- 元の計画の Global Constraints をすべて引き継ぐ（shard を足さない、公開 API は `Shomen::` 配下、sleep で同期しない、固定ポートを使わない、`crystal tool format`、警告なし）。
- `Shomen::Store` の公開 API は変えない。`Shomen::AppendWatcher.new` に名前付き引数 `stop_limit : Time::Span = STOP_LIMIT` を足すのは可（spec が短い上限で確かめるため）。
- Postgres の spec は `SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres` を付けて走らせ、pending 0 を確かめる。
- コミットはユーザーが PR #9 のブランチへの修正として求めたので、最後に 1 本だけ作って push する（Task 2）。

## Review Focus

- 閉じた Store のアダプタに、watcher のファイバーが問い合わせる。接続が作り直されて残る。Task 1 の "leaves no SQLite file behind after the store closes and the file is removed" と "waits for a poll in progress before stop returns, and does not poll after" で固定する。Postgres の "leaves no connection after the store closes" は、受信と切断用の接続（`shomen-` で始まる名前）が残らないことを確かめる。
- 終了用の SQL が返らない（プールが埋まっている、ネットワークが詰まる）。`stop` は上限で戻る。Task 1 の "returns from stop within its limit when the interrupt hangs" と "interrupts without a pooled connection" で固定する。
- 受信の接続が、`stop` が上限で戻った後に開く。それでも切られる。Task 1 の "closes a listening connection that opens after stop gave up" で固定する。
- ロールバックした追記は通知しない。Task 1 の "sends no notification for an append that rolls back" で固定する。
- つなぎ直しに失敗し続けると待ちが倍に伸び、間隔で止まる。長く続いた接続の後は最初の待ちに戻る。Task 1 の "backs off" の例で固定する。

---

### Task 1: watcher の停止とテスト

**Files:**
- Modify: `src/shomen/append_watcher.cr`
- Modify: `src/shomen/postgres_adapter.cr`
- Modify: `docs/decisions/20261001-phase7-append-watcher.md`、`docs/decisions/20261001-phase7-notify-channel.md`
- Test: `spec/shomen/append_watcher_spec.cr`、`spec/shomen/postgres_adapter_spec.cr`

**Interfaces:**
- Produces: `Shomen::AppendWatcher.new(adapter, signal, interval, stop_limit : Time::Span = STOP_LIMIT)`、`REAP_RETRY = 1.second`、`Shomen::AppendWatcher.backoff(wait : Time::Span, lasted : Time::Span, interval : Time::Span) : {Time::Span, Time::Span}`（今回の待ちと次の待ち）、`Shomen::PostgresAdapter` の ivar `@control_url`、定数 `CONTROL_PREFIX = "shomen-stop-"`

- [ ] **Step 1: 失敗するテストを書く（watcher の単体）**

`spec/shomen/append_watcher_spec.cr` に、DB を使わないアダプタを足す（`FlakyAdapter` の隣、`private class`）。

```crystal
# An adapter that notifies and lets the spec decide when its listening
# connection opens. interrupt_listen ends a listen only once it is
# connected, as terminating a backend that does not exist yet does nothing.
private class GatedAdapter < Shomen::StoreAdapter
  getter calls_after_close = 0
  getter entered = Channel(Nil).new(1)
  getter opened = Channel(Nil).new(1)
  getter ended = Channel(Nil).new(1)
  property interrupt_hangs = false
  @connect = Channel(Nil).new(1)
  @interrupted = Channel(Nil).new(1)
  @connected = Atomic(Bool).new(false)
  @closed = false

  def key : String
    "gated"
  end

  def append(stream : String, expected_version : Int64, rows : Array(Row)) : Int64
    raise "not used"
  end

  def read(after : Int64, limit : Int32) : Array(Stored)
    [] of Stored
  end

  def last_id : Int64
    @calls_after_close += 1 if @closed
    0_i64
  end

  def close : Nil
    @closed = true
  end

  def notifies? : Bool
    true
  end

  # Lets the listen that waits for it connect.
  def connect : Nil
    @connect.send(nil)
  end

  def listen(on_id : Int64 -> Nil) : Nil
    @entered.send(nil)
    @connect.receive
    @connected.set(true)
    @opened.send(nil)
    @interrupted.receive
    raise IO::EOFError.new
  ensure
    @ended.send(nil)
  end

  def interrupt_listen : Nil
    Channel(Nil).new.receive if interrupt_hangs
    @interrupted.send(nil) if @connected.swap(false)
  end
end

private def within(channel : Channel(Nil), limit : Time::Span = 10.seconds) : Bool
  select
  when channel.receive
    true
  when timeout(limit)
    false
  end
end
```

`describe` の中に足す。

```crystal
  it "does not touch the adapter after stop returns" do
    adapter = GatedAdapter.new
    watcher = Shomen::AppendWatcher.new(adapter, Shomen::AppendSignal.new, 1.millisecond, stop_limit: 1.second)
    watcher.stop
    adapter.close
    100.times { Fiber.yield }
    adapter.calls_after_close.should eq(0)
  end

  it "returns from stop within its limit when the interrupt hangs" do
    adapter = GatedAdapter.new
    adapter.interrupt_hangs = true
    watcher = Shomen::AppendWatcher.new(adapter, Shomen::AppendSignal.new, 1.hour, stop_limit: 100.milliseconds)
    adapter.connect
    within(adapter.opened).should be_true
    done = Channel(Nil).new(1)
    spawn do
      watcher.stop
      done.send(nil)
    end
    within(done, 2.seconds).should be_true
  end

  it "closes a listening connection that opens after stop gave up" do
    adapter = GatedAdapter.new
    watcher = Shomen::AppendWatcher.new(adapter, Shomen::AppendSignal.new, 1.hour, stop_limit: 50.milliseconds)
    within(adapter.entered).should be_true
    watcher.stop
    adapter.connect
    within(adapter.opened).should be_true
    within(adapter.ended).should be_true
  end

  it "backs off by doubling up to the interval, and starts again after a connection that lasted" do
    first = Shomen::AppendWatcher::RETRY_FIRST
    Shomen::AppendWatcher.backoff(first, 1.millisecond, 1.second).should eq({first, first * 2})
    Shomen::AppendWatcher.backoff(first * 4, 1.millisecond, 1.second).should eq({first * 4, first * 8})
    Shomen::AppendWatcher.backoff(800.milliseconds, 1.millisecond, 1.second).should eq({800.milliseconds, 1.second})
    Shomen::AppendWatcher.backoff(1.second, 1.millisecond, 1.second).should eq({1.second, 1.second})
    Shomen::AppendWatcher.backoff(first * 8, 1.minute, 1.second).should eq({first, first * 2})
  end
```

2 つ目の例は、終了用の SQL が返らなくても `stop` が上限で戻ることを確かめる（受信は開いたまま残るが、`interrupt_hangs` の例ではそれを問わない）。`stop` を別のファイバーで呼ぶので、今のコード（`stop` の中で切断を同期で呼ぶ）でもハングせず、2 秒で FAIL する。3 つ目の例は、`stop` が上限の 50 ミリ秒で戻った後に受信の接続が開いても、切断を繰り返すファイバーがそれを終わらせることを確かめる。

- [ ] **Step 2: 失敗するテストを書く（Store と Postgres）**

`spec/shomen/append_watcher_spec.cr` の `describe` の中に足す。

```crystal
  it "leaves no SQLite file behind after the store closes and the file is removed" do
    path = File.tempname("shomen-store", ".sqlite3")
    store = Shomen::Store.new("sqlite3://#{path}", poll_interval: 1.millisecond)
    store.append("a", 0_i64, note("1"))
    store.wait_for_append(after: 0_i64, within: 1.millisecond).should be_true
    store.close
    remove_database(path)
    100.times { Fiber.yield }
    File.exists?(path).should be_false
  ensure
    remove_database(path) if path
  end

  postgres_it "leaves no connection after the store closes" do |_, url|
    other = Shomen::Store.new(url, poll_interval: 1.millisecond)
    other.append("a", 0_i64, note("1"))
    other.wait_for_append(after: 0_i64, within: 1.millisecond).should be_true
    other.close
    DB.open(url) do |db|
      # The store that store_it opened keeps its own pool; count only
      # connections other than that pool's and this one.
      wait_until(10.seconds) do
        db.scalar("SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid() AND application_name LIKE 'shomen-%'").as(Int64) == 0
      end
    end
  end

  postgres_it "interrupts without a pooled connection" do |_, url|
    uri = URI.parse(url)
    uri.query = "max_pool_size=1"
    store = Shomen::Store.new(uri.to_s, poll_interval: 1.hour)
    begin
      store.wait_for_append(after: 0_i64, within: 1.millisecond)
      DB.open(url) { |db| wait_until(10.seconds) { PostgresSpec.listeners(db).size == 1 } }
      adapter = store.@adapter.as(Shomen::PostgresAdapter)
      held = Channel(Nil).new
      release = Channel(Nil).new
      spawn do
        adapter.@db.using_connection do
          held.send(nil)
          release.receive
        end
      end
      held.receive
      done = Channel(Nil).new(1)
      spawn do
        adapter.interrupt_listen
        done.send(nil)
      end
      within(done, 3.seconds).should be_true
      release.send(nil)
    ensure
      store.close
    end
  end
```

`spec/shomen/postgres_adapter_spec.cr` の `describe` の中に足す。

```crystal
  postgres_it "sends no notification for an append that rolls back" do |store, url|
    payloads = Channel(String).new(4)
    listener = PG.connect_listen(url, Shomen::PostgresAdapter::CHANNEL) { |notification| payloads.send(notification.payload) }
    begin
      DB.open(url) { |db| db.exec(%(ALTER TABLE events ADD CONSTRAINT bad CHECK (payload NOT LIKE '%"bad"%'))) }
      expect_raises(PQ::PQError, "bad") do
        store.append("s", 0_i64, [SpecEvents::Noted.new("ok"), SpecEvents::Noted.new("bad")] of Shomen::Event)
      end
      store.append("s", 0_i64, note("after"))
      select
      when payload = payloads.receive
        payload.should eq(store.last_appended.to_s)
      when timeout(5.seconds)
        fail "no notification within 5 seconds"
      end
    ensure
      listener.close
    end
  end
```

`leaves no connection after the store closes` は、`shomen-` で始まる名前の接続（受信と切断用）を数える。プールの接続は名前が `crystal` なので数えない。閉じた後のポーリングがプールの接続を作り直す不具合は、SQLite の例（ファイルが作り直される）と Step 1 の単体の例で固定する。

- [ ] **Step 3: テストが失敗するのを確かめる**

Run: `SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec spec/shomen/append_watcher_spec.cr spec/shomen/postgres_adapter_spec.cr`
Expected: `stop_limit` と `backoff` が無いのでコンパイルエラー。それを避けて確かめる場合、"does not touch the adapter after stop returns"、"returns from stop within its limit…"、"closes a listening connection that opens after stop gave up"、"leaves no SQLite file behind…"、"interrupts without a pooled connection" が FAIL。"sends no notification for an append that rolls back" は今のコードで PASS する（回帰を防ぐ例）。

- [ ] **Step 4: watcher を直す**

`src/shomen/append_watcher.cr` を次の形にする（コメントは英語で、短く保つ）。

```crystal
  RETRY_FIRST = 100.milliseconds
  STOP_LIMIT  = 5.seconds
  STOP_RETRY  = 50.milliseconds
  REAP_RETRY  = 1.second

  @stop = Channel(Nil).new
  # Closed when each fiber ends, which wakes every receiver.
  @polled = Channel(Nil).new
  @listened = Channel(Nil).new
  @stopped = Atomic(Bool).new(false)

  def initialize(@adapter : Shomen::StoreAdapter, @signal : Shomen::AppendSignal, @interval : Time::Span, @stop_limit : Time::Span = STOP_LIMIT)
    spawn(name: "shomen poll") { poll }
    spawn(name: "shomen listen") { listen } if @adapter.notifies?
  end

  # Waits, up to stop_limit, for both fibers to end, so the store can close
  # the adapter without a fiber opening a connection on it again. The
  # interrupts run in a fiber of their own: a stuck one cannot hold stop
  # past the limit, and they go on after stop returns until the listen
  # ends, so a connection that opens late is closed as well.
  def stop : Nil
    return if @stopped.swap(true)
    @stop.close
    spawn(name: "shomen interrupt listen") { interrupt_until_listened } if @adapter.notifies?
    deadline = Time.instant + @stop_limit
    ended = ended_by?(@polled, deadline)
    ended = ended_by?(@listened, deadline) && ended if @adapter.notifies?
    Log.warn { "the watcher for appends did not stop within #{@stop_limit}" } unless ended
  end

  # The wait before this reconnect and the one after it: back to
  # RETRY_FIRST after a connection that lasted longer than the wait,
  # otherwise the wait, then twice it, at most interval.
  def self.backoff(wait : Time::Span, lasted : Time::Span, interval : Time::Span) : {Time::Span, Time::Span}
    wait = RETRY_FIRST if lasted > wait
    {wait, {wait * 2, interval}.min}
  end

  private def ended_by?(channel : Channel(Nil), deadline : Time::Instant) : Bool
    select
    when channel.receive?
      true
    when timeout({deadline - Time.instant, Time::Span.zero}.max)
      false
    end
  end

  private def interrupt_until_listened : Nil
    retry = STOP_RETRY
    loop do
      begin
        @adapter.interrupt_listen
      rescue ex
        Log.warn(exception: ex) { "could not close the connection that listens for appends" }
      end
      select
      when @listened.receive?
        return
      when timeout(retry)
      end
      retry = {retry * 2, REAP_RETRY}.min
    end
  end

  private def poll : Nil
    until stopped?
      begin
        catch_up
      rescue ex
        Log.warn(exception: ex) { "could not poll for appends" } unless stopped?
      end
      select
      when @stop.receive?
        break
      when timeout(@interval)
      end
    end
  ensure
    @polled.close
  end
```

`listen` は、今の形のまま、待ちの計算を `backoff` に置き換え、終わりで `@listened.close` する。

```crystal
  private def listen : Nil
    wait = RETRY_FIRST
    until stopped?
      began = Time.instant
      begin
        catch_up
        break if stopped?
        @adapter.listen(->(id : Int64) { @signal.announce(id) })
      rescue ex
        break if stopped?
        Log.warn(exception: ex) { "lost the connection that listens for appends; connecting again" }
      end
      wait, after = Shomen::AppendWatcher.backoff(wait, Time.instant - began, @interval)
      select
      when @stop.receive?
        break
      when timeout(wait)
      end
      wait = after
    end
  ensure
    @listened.close
  end
```

- [ ] **Step 5: Postgres の切断を専用の接続にする**

`src/shomen/postgres_adapter.cr`:

```crystal
  CONTROL_PREFIX  = "shomen-stop-"
```

`@control_url : String` を足し、`initialize` で受信の URL と同じように、プールの引数を足す前の URL から `application_name=shomen-stop-` と 16 桁の 16 進で作る（受信の名前とは別の乱数）。`interrupt_listen` を次にする。

```crystal
  # On a connection of its own rather than the pool, so a full pool or a
  # closed one does not hold it up or open a pooled connection again.
  def interrupt_listen : Nil
    DB.connect(@control_url) do |connection|
      connection.exec(TERMINATE, @listener_name)
    end
  end
```

- [ ] **Step 6: 決定ファイルを直す**

`docs/decisions/20261001-phase7-append-watcher.md` の 決定 の `stop` の段落を次にする。

```markdown
`stop` はポーリングと受信のファイバーに止まるよう知らせ、両方が終わるのを上限（既定 5 秒）まで待つ。ファイバーが閉じたアダプタで問い合わせ、接続を作り直すことが無いようにするためである。`crystal-db` の `Database#close` は閉じた状態を持たず、閉じた後の問い合わせは新しい接続を作る。受信中の接続の切断（`StoreAdapter#interrupt_listen`）は別のファイバーで繰り返し（50 ミリ秒から倍にし、1 秒を上限）、`stop` が上限で戻った後も受信のファイバーが終わるまで続ける。接続を開いている途中で切断が空振りしても、後から開いた接続を切れる。上限を過ぎても終わらない問い合わせが使った接続は、プロセスの終了まで残りうる。
```

同じファイルの、受信の箇条の「接続が切れたら … 待ちを 100 ミリ秒に戻す」の文は変えない（`backoff` は同じ規則を関数にしたもの）。

`docs/decisions/20261001-phase7-notify-channel.md` の 決定 の「受信の接続を閉じるときは、プールの接続で …」の箇条を次にする。

```markdown
- 受信の接続を閉じるときは、Store の URL に `application_name=shomen-stop-` と 16 桁の 16 進を足した URL で短い接続を開き、`SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name = $1 AND pid <> pg_backend_pid()` を実行して閉じる。プールは使わないので、プールが埋まっていても閉じていても、切断は待たされず、プールの接続も作り直さない
```

- [ ] **Step 7: テストが通るのを確かめる**

Run:

```sh
crystal tool format
SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec spec/shomen/append_watcher_spec.cr spec/shomen/postgres_adapter_spec.cr spec/shomen/sse_processes_spec.cr spec/shomen/append_signal_spec.cr
SHOMEN_SPEC_POSTGRES=postgres://localhost/postgres crystal spec
crystal spec
/opt/homebrew/bin/psql-18 postgres -tAc "SELECT count(*) FROM pg_stat_activity WHERE application_name LIKE 'shomen-%'"
```

Expected: 失敗 0。Postgres 付きは pending 0。最後の問い合わせは `0`。

---

### Task 2: コミットと push

**Files:** なし（Task 1 の変更とこの計画ファイル）

- [ ] **Step 1: 最終確認**

Run: `crystal tool format --check && crystal build src/shomen.cr --error-trace && rm -f shomen shomen.dwarf && (cd examples/hello && crystal spec)`
Expected: すべて成功。

- [ ] **Step 2: コミットして push する**

```sh
git add docs/superpowers/plans/2026-10-01-phase7a-review-fixes.md src spec docs/decisions
git commit -m "fix: stop the append watcher without leaving connections behind" -m "<本文: 4 件の指摘と直し方を英語で>"
git push
```
