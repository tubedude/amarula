defmodule Amarula.Protocol.Signal.SessionCustodianTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Signal.{SessionCustodian, SessionStore}
  alias Amarula.Protocol.Socket.ConnectionSupervisor

  # Same libsignal vectors session_cipher_test uses: the responder's keys + two
  # PreKeyWhisperMessages we must decrypt. Lets us drive the custodian's decrypt
  # path against real ciphertext, proving it wraps load → cipher → store.
  @vectors "test/fixtures/session_vec.json" |> File.read!() |> JSON.decode!()

  defp h(hex), do: Base.decode16!(hex, case: :lower)
  defp strip5(<<5, k::binary-size(32)>>), do: k
  defp strip5(<<k::binary-size(32)>>), do: k

  defp store do
    r = @vectors["responder"]

    %{
      our_identity: %{public: strip5(h(r["identityPub"])), private: h(r["identityPriv"])},
      load_pre_key: fn id ->
        if id == r["preKeyId"],
          do: %{public: strip5(h(r["prePub"])), private: h(r["prePriv"])},
          else: nil
      end,
      load_signed_pre_key: fn id ->
        if id == r["signedPreKeyId"],
          do: %{public: strip5(h(r["signedPub"])), private: h(r["signedPriv"])},
          else: nil
      end
    }
  end

  @addr "12345.0"

  # The ops resolve their own custodian through the app registry, so every test
  # needs the per-instance custodian DynamicSupervisor the ops start children under.
  setup do
    dir = Path.join(System.tmp_dir!(), "amarula_custodian_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    conn = Amarula.TestConn.new(dir)
    instance_id = make_ref()

    {:ok, sup} =
      DynamicSupervisor.start_link(
        strategy: :one_for_one,
        name: ConnectionSupervisor.name(instance_id, :custodian_supervisor)
      )

    on_exit(fn -> if Process.alive?(sup), do: Process.exit(sup, :normal) end)
    {:ok, conn: conn, instance_id: instance_id}
  end

  describe "decrypt/6" do
    test "a pkmsg establishes and persists the session, returning the prekey id", ctx do
      m1 = @vectors["msg1"]

      assert {:ok, plaintext, pre_key_id} =
               SessionCustodian.decrypt(
                 ctx.instance_id,
                 ctx.conn,
                 @addr,
                 :pkmsg,
                 h(m1["body"]),
                 store()
               )

      assert plaintext == h(m1["plaintext"])
      assert pre_key_id == @vectors["responder"]["preKeyId"]

      # The record was written through to storage under the custodian's key.
      assert %{sessions: sessions} = SessionStore.load_session(ctx.conn, @addr)
      assert map_size(sessions) == 1
    end

    test "a second pkmsg advances the chain on the same persisted record", ctx do
      s = store()

      assert {:ok, _, _} =
               SessionCustodian.decrypt(
                 ctx.instance_id,
                 ctx.conn,
                 @addr,
                 :pkmsg,
                 h(@vectors["msg1"]["body"]),
                 s
               )

      assert {:ok, plaintext, _} =
               SessionCustodian.decrypt(
                 ctx.instance_id,
                 ctx.conn,
                 @addr,
                 :pkmsg,
                 h(@vectors["msg2"]["body"]),
                 s
               )

      assert plaintext == h(@vectors["msg2"]["plaintext"])
    end

    test "a :msg with no session returns {:error, :no_session}", ctx do
      assert {:error, :no_session} =
               SessionCustodian.decrypt(ctx.instance_id, ctx.conn, @addr, :msg, <<1, 2, 3>>, store())
    end

    test "a cipher failure surfaces as an error tuple, not a custodian crash", ctx do
      # Garbage pkmsg → the cipher raises → the op converts it to {:error, _};
      # the custodian stays alive for the next caller.
      assert {:error, _} =
               SessionCustodian.decrypt(ctx.instance_id, ctx.conn, @addr, :pkmsg, <<0, 1, 2>>, store())

      assert {:ok, pid} = SessionCustodian.for_address(ctx.instance_id, ctx.conn, @addr)
      assert Process.alive?(pid)
    end
  end

  describe "encrypt/5" do
    test "with no session returns {:error, :no_session}", ctx do
      assert {:error, :no_session} =
               SessionCustodian.encrypt(ctx.instance_id, ctx.conn, @addr, "hi", store())
    end
  end

  describe "inject/6" do
    test ":if_absent skips when the record already has an open session", ctx do
      # Establish a session via a pkmsg first.
      assert {:ok, _, _} =
               SessionCustodian.decrypt(
                 ctx.instance_id,
                 ctx.conn,
                 @addr,
                 :pkmsg,
                 h(@vectors["msg1"]["body"]),
                 store()
               )

      # device is never reached on the skip path.
      assert {:skipped, :session_exists} =
               SessionCustodian.inject(ctx.instance_id, ctx.conn, @addr, %{}, store(), :if_absent)
    end
  end

  describe "record custody (record/replace)" do
    test "replace writes; record reads it back without removing", ctx do
      assert :ok = SessionCustodian.replace(ctx.instance_id, ctx.conn, @addr, %{sessions: %{x: 1}})
      assert {:ok, %{sessions: %{x: 1}}} = SessionCustodian.record(ctx.instance_id, ctx.conn, @addr)
      # still there
      assert {:ok, %{sessions: %{x: 1}}} = SessionCustodian.record(ctx.instance_id, ctx.conn, @addr)
    end

    test "replace(nil) deletes the record", ctx do
      :ok = SessionCustodian.replace(ctx.instance_id, ctx.conn, @addr, %{sessions: %{z: 3}})
      assert :ok = SessionCustodian.replace(ctx.instance_id, ctx.conn, @addr, nil)
      assert {:ok, nil} = SessionCustodian.record(ctx.instance_id, ctx.conn, @addr)
    end

    test "record on an empty custodian returns {:ok, nil}", ctx do
      assert {:ok, nil} = SessionCustodian.record(ctx.instance_id, ctx.conn, @addr)
    end
  end

  describe "install_if_absent (migration target)" do
    test "installs the record when the address has no live session", ctx do
      assert :ok =
               SessionCustodian.install_if_absent(
                 ctx.instance_id,
                 ctx.conn,
                 @addr,
                 %{sessions: %{migrated: 1}}
               )

      assert {:ok, %{sessions: %{migrated: 1}}} =
               SessionCustodian.record(ctx.instance_id, ctx.conn, @addr)
    end

    test "keeps the existing live session and discards the migrated record", ctx do
      # Establish a real, open session (a pkmsg gives an open ratchet).
      assert {:ok, _, _} =
               SessionCustodian.decrypt(
                 ctx.instance_id,
                 ctx.conn,
                 @addr,
                 :pkmsg,
                 h(@vectors["msg1"]["body"]),
                 store()
               )

      {:ok, live} = SessionCustodian.record(ctx.instance_id, ctx.conn, @addr)

      # A migration trying to overwrite it is refused — the live ratchet wins.
      assert {:skipped, :session_exists} =
               SessionCustodian.install_if_absent(
                 ctx.instance_id,
                 ctx.conn,
                 @addr,
                 %{sessions: %{migrated: 1}}
               )

      assert {:ok, ^live} = SessionCustodian.record(ctx.instance_id, ctx.conn, @addr)
    end
  end

  describe "group ops trust boundary" do
    alias Amarula.Protocol.Signal.Group.SenderKeyName

    test "a malformed skmsg surfaces as {:error, _}, not a custodian crash", ctx do
      name = SenderKeyName.from_jids("123@g.us", "456:0@s.whatsapp.net")

      assert {:error, _} =
               SessionCustodian.group_decrypt(ctx.instance_id, ctx.conn, name, <<0, 1, 2, 3>>)

      # The custodian stays alive for the next caller (a raw crash would :exit it,
      # and with it every queued caller — including Connection).
      assert {:ok, pid} = SessionCustodian.for_sender_key(ctx.instance_id, ctx.conn, name)
      assert Process.alive?(pid)
    end

    test "serves the record from the write-through cache, not re-reading storage", ctx do
      # Establish + cache a session via a pkmsg.
      assert {:ok, _, _} =
               SessionCustodian.decrypt(
                 ctx.instance_id,
                 ctx.conn,
                 @addr,
                 :pkmsg,
                 h(@vectors["msg1"]["body"]),
                 store()
               )

      {:ok, cached} = SessionCustodian.record(ctx.instance_id, ctx.conn, @addr)
      refute is_nil(cached)

      # Mutate storage out from under the custodian (only possible in a test — in
      # production the custodian is the sole writer). It keeps serving the cache,
      # proving `record` reads memory, not disk.
      :ok = SessionStore.store_session(ctx.conn, @addr, %{sessions: %{}})
      assert {:ok, ^cached} = SessionCustodian.record(ctx.instance_id, ctx.conn, @addr)
    end
  end

  describe "for_address/3 (find-or-start)" do
    test "every caller for a record converges on one custodian; records get distinct ones", ctx do
      assert {:ok, pid} = SessionCustodian.for_address(ctx.instance_id, ctx.conn, "aaa.0")
      # a second lookup for the same record returns the SAME process (the lock)
      assert {:ok, ^pid} = SessionCustodian.for_address(ctx.instance_id, ctx.conn, "aaa.0")
      # a different record gets its own custodian
      assert {:ok, other} = SessionCustodian.for_address(ctx.instance_id, ctx.conn, "bbb.0")
      assert other != pid
    end

    test "concurrent find-or-start for the same record all converge on one custodian", ctx do
      # A lost :already_started start race must resolve to the winner, not error —
      # so N simultaneous callers must all see the SAME pid.
      pids =
        1..20
        |> Enum.map(fn _ ->
          Task.async(fn -> SessionCustodian.for_address(ctx.instance_id, ctx.conn, "race.0") end)
        end)
        |> Task.await_many(5000)

      assert Enum.all?(pids, &match?({:ok, _}, &1))
      assert pids |> Enum.map(fn {:ok, pid} -> pid end) |> Enum.uniq() |> length() == 1
    end

    test "sheds itself after idling", %{conn: conn} do
      {:ok, pid} = SessionCustodian.start_link(conn: conn, key: "idle.0", idle_ms: 40)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    end
  end

  describe "serialization + resilience" do
    test "concurrent mutations on one record serialize without corruption", ctx do
      # Establish a session (gives the responder a sending chain), then fire many
      # concurrent encrypts at the SAME record. The custodian serializes them, so
      # every advance lands: all succeed, none crashes, ciphertexts are distinct.
      assert {:ok, _, _} =
               SessionCustodian.decrypt(
                 ctx.instance_id,
                 ctx.conn,
                 @addr,
                 :pkmsg,
                 h(@vectors["msg1"]["body"]),
                 store()
               )

      results =
        1..25
        |> Enum.map(fn i ->
          Task.async(fn ->
            SessionCustodian.encrypt(ctx.instance_id, ctx.conn, @addr, "m#{i}", store())
          end)
        end)
        |> Task.await_many(5000)

      assert Enum.all?(results, &match?({:ok, _type, _ct}, &1))
      ciphertexts = for {:ok, _t, ct} <- results, do: ct
      assert length(Enum.uniq(ciphertexts)) == 25

      # The custodian survived the whole burst.
      assert {:ok, pid} = SessionCustodian.for_address(ctx.instance_id, ctx.conn, @addr)
      assert Process.alive?(pid)
    end

    test "a custodian dying between resolve and call doesn't take the caller down", ctx do
      # Seed a record so a fresh custodian re-reads real state from storage.
      :ok = SessionCustodian.replace(ctx.instance_id, ctx.conn, @addr, %{sessions: %{y: 9}})
      {:ok, pid} = SessionCustodian.for_address(ctx.instance_id, ctx.conn, @addr)

      # Kill the custodian; the next op must retry through find-or-start (starting a
      # fresh one that re-reads storage) rather than :exit the calling process.
      Process.exit(pid, :kill)

      assert {:ok, %{sessions: %{y: 9}}} =
               SessionCustodian.record(ctx.instance_id, ctx.conn, @addr)

      # The test process (the "caller") is obviously still alive to make this assertion,
      # and a brand-new custodian is now serving the record.
      assert {:ok, fresh} = SessionCustodian.for_address(ctx.instance_id, ctx.conn, @addr)
      assert fresh != pid
      assert Process.alive?(fresh)
    end
  end
end
