defmodule Amarula.Protocol.Signal.SessionCipherTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Signal.SessionCipher

  # Vectors from a real libsignal session: a JS "sender" runs
  # SessionBuilder.initOutgoing + SessionCipher.encrypt against our (responder)
  # prekey bundle, producing two PreKeyWhisperMessages. We hold the responder's
  # private keys and must decrypt them to the original plaintext. Generated with
  # node_modules/libsignal — see test/fixtures/session_vec.json.
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

  test "decrypts a libsignal PreKeyWhisperMessage (X3DH session establishment)" do
    m1 = @vectors["msg1"]
    assert m1["type"] == 3

    {:ok, plaintext, record, pre_key_id} =
      SessionCipher.decrypt_pre_key_whisper_message(nil, h(m1["body"]), store())

    assert plaintext == h(m1["plaintext"])
    assert pre_key_id == @vectors["responder"]["preKeyId"]
    # A session was created and stored
    assert map_size(record.sessions) == 1
  end

  test "decrypts a second message on the established session (chain advances)" do
    s = store()
    m1 = @vectors["msg1"]
    m2 = @vectors["msg2"]

    {:ok, _pt1, record, _id} =
      SessionCipher.decrypt_pre_key_whisper_message(nil, h(m1["body"]), s)

    # m2 is also a PreKeyWhisperMessage on the same chain (counter advanced);
    # init_incoming is a no-op for the existing base key and the cipher fills the
    # next message key.
    {:ok, plaintext, _record2, _id} =
      SessionCipher.decrypt_pre_key_whisper_message(record, h(m2["body"]), s)

    assert plaintext == h(m2["plaintext"])
  end

  test "rejects an incompatible version byte" do
    assert_raise RuntimeError, ~r/Incompatible version/, fn ->
      SessionCipher.decrypt_pre_key_whisper_message(nil, <<0x11, 0x00>>, store())
    end
  end
end
