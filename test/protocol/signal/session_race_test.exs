defmodule Amarula.Protocol.Signal.SessionRaceTest do
  @moduledoc """
  Proves the load-modify-store on a Signal session is not atomic across processes.

  A session ratchet advance is `load_session -> mutate -> store_session` with no
  lock, CAS, or version check (see `SessionStore`). The send path runs this in a
  per-recipient `ConversationSender`; the receive path runs it inline in
  `Connection`. They are *different* processes touching the *same* session, with
  nothing serializing them — so a concurrent send + receive to the same peer can
  interleave their load-modify-store and lose an update (a forked ratchet).

  This test reproduces that lost update at the mechanism level: N processes each do
  one load -> +1 -> store against one session key. With a real lock the final
  counter would be N; the race makes it less.
  """
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Signal.SessionStore

  @addr "racepeer.0"

  setup do
    dir =
      Path.join(System.tmp_dir!(), "amarula_session_race_#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(dir) end)

    # DETS, not File: each individual `put` is one atomic `:dets.insert`, so every
    # write *succeeds*. That isolates the thing under test — the lost update from
    # the unsynchronized load-modify-store — from any per-write failure in the
    # storage adapter. (The File adapter has its own concurrent-write-to-one-key
    # bug, a fixed `.tmp` path; that's a separate issue, not what this proves.)
    conn = Amarula.Conn.new(%{profile: :test, storage: {Amarula.Storage.DETS, root: dir}})
    {:ok, conn: conn}
  end

  test "concurrent load-modify-store on one session loses updates (the fork)", %{conn: conn} do
    # Pre-create the session (and its on-disk dir/file) before the concurrent
    # phase, so what we measure is purely the lost-update on the *value* — not any
    # directory-creation contention in the storage adapter.
    :ok = SessionStore.store_session(conn, @addr, %{counter: 0})
    assert %{counter: 0} = SessionStore.load_session(conn, @addr)

    n = 50

    # Each task does exactly what an encrypt or a decrypt does to the ratchet:
    # load the current record, advance it by one, store it back. A tiny yield
    # between load and store widens the interleaving window so the race is
    # reliable rather than probabilistic-but-rare (the real-world window is
    # narrower, but the hazard is identical — no lock guards the read-modify-write).
    tasks =
      for _ <- 1..n do
        Task.async(fn ->
          %{counter: c} = SessionStore.load_session(conn, @addr)
          Process.sleep(1)
          SessionStore.store_session(conn, @addr, %{counter: c + 1})
        end)
      end

    Task.await_many(tasks, 5_000)

    %{counter: final} = SessionStore.load_session(conn, @addr)

    # If the load-modify-store were atomic/serialized, every one of the N advances
    # would land and final would be N. It is not — concurrent loaders read the same
    # value and clobber each other, so updates are lost.
    assert final < n,
           "expected lost updates from the unsynchronized load-modify-store, but " <>
             "final counter was #{final} (== N=#{n}); the race did not reproduce"
  end
end
