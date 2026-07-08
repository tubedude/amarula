defmodule Amarula.Protocol.Signal.SessionCustodianTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Signal.{SessionCustodian, SessionStore}

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

  @key "12345.0"

  setup do
    dir = Path.join(System.tmp_dir!(), "amarula_custodian_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    conn = Amarula.TestConn.new(dir)
    {:ok, pid} = SessionCustodian.start_link(conn: conn, key: @key)
    {:ok, custodian: pid, conn: conn}
  end

  describe "decrypt/4" do
    test "a pkmsg establishes and persists the session, returning the prekey id", ctx do
      m1 = @vectors["msg1"]

      assert {:ok, plaintext, pre_key_id} =
               SessionCustodian.decrypt(ctx.custodian, :pkmsg, h(m1["body"]), store())

      assert plaintext == h(m1["plaintext"])
      assert pre_key_id == @vectors["responder"]["preKeyId"]

      # The record was written through to storage under the custodian's key.
      assert %{sessions: sessions} = SessionStore.load_session(ctx.conn, @key)
      assert map_size(sessions) == 1
    end

    test "a second pkmsg advances the chain on the same persisted record", ctx do
      s = store()

      assert {:ok, _, _} =
               SessionCustodian.decrypt(ctx.custodian, :pkmsg, h(@vectors["msg1"]["body"]), s)

      assert {:ok, plaintext, _} =
               SessionCustodian.decrypt(ctx.custodian, :pkmsg, h(@vectors["msg2"]["body"]), s)

      assert plaintext == h(@vectors["msg2"]["plaintext"])
    end

    test "a :msg with no session returns {:error, :no_session}", ctx do
      assert {:error, :no_session} =
               SessionCustodian.decrypt(ctx.custodian, :msg, <<1, 2, 3>>, store())
    end

    test "a cipher failure surfaces as an error tuple, not a custodian crash", ctx do
      # Garbage pkmsg → the cipher raises → with_cipher converts to {:error, _};
      # the custodian stays alive for the next caller.
      assert {:error, _} = SessionCustodian.decrypt(ctx.custodian, :pkmsg, <<0, 1, 2>>, store())
      assert Process.alive?(ctx.custodian)
    end
  end

  describe "encrypt/3" do
    test "with no session returns {:error, :no_session}", ctx do
      assert {:error, :no_session} = SessionCustodian.encrypt(ctx.custodian, "hi", store())
    end
  end

  describe "inject/4" do
    test ":if_absent skips when the record already has an open session", ctx do
      # Establish a session via a pkmsg first.
      assert {:ok, _, _} =
               SessionCustodian.decrypt(
                 ctx.custodian,
                 :pkmsg,
                 h(@vectors["msg1"]["body"]),
                 store()
               )

      # device is never reached on the skip path.
      assert {:skipped, :session_exists} =
               SessionCustodian.inject(ctx.custodian, %{}, store(), :if_absent)
    end
  end

  describe "record ops (get/take/put/delete)" do
    test "put then get returns the record without removing it", ctx do
      assert :ok = SessionCustodian.put_record(ctx.custodian, %{sessions: %{x: 1}})
      assert {:ok, %{sessions: %{x: 1}}} = SessionCustodian.get_record(ctx.custodian)
      # still there
      assert {:ok, %{sessions: %{x: 1}}} = SessionCustodian.get_record(ctx.custodian)
    end

    test "take returns the record and removes it", ctx do
      :ok = SessionCustodian.put_record(ctx.custodian, %{sessions: %{y: 2}})

      assert {:ok, %{sessions: %{y: 2}}} = SessionCustodian.take_record(ctx.custodian)
      assert {:ok, nil} = SessionCustodian.get_record(ctx.custodian)
    end

    test "take on an empty record returns {:ok, nil}", ctx do
      assert {:ok, nil} = SessionCustodian.take_record(ctx.custodian)
    end

    test "delete removes the record", ctx do
      :ok = SessionCustodian.put_record(ctx.custodian, %{sessions: %{z: 3}})
      assert :ok = SessionCustodian.delete(ctx.custodian)
      assert {:ok, nil} = SessionCustodian.get_record(ctx.custodian)
    end
  end
end
