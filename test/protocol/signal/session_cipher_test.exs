defmodule Amarula.Protocol.Signal.SessionCipherTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Amarula.Protocol.Crypto.Crypto
  alias Amarula.Protocol.Signal.{SessionBuilder, SessionCipher, SessionRecord}

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
    assert_raise Amarula.Protocol.Signal.DecryptError, ~r/Incompatible version/, fn ->
      SessionCipher.decrypt_pre_key_whisper_message(nil, <<0x11, 0x00>>, store())
    end
  end

  # --- decrypt_whisper_message / trial-decrypt loop ---
  #
  # The vectors above are PreKeyWhisperMessages. To exercise the plain
  # WhisperMessage path (decrypt_with_sessions), we stand up both peers in
  # Elixir: Alice runs init_outgoing against Bob's bundle and sends the opening
  # pkmsg; Bob decrypts it (establishing his session) and replies with a plain
  # WhisperMessage (:msg). Alice decrypting that reply goes through the loop.

  test "decrypts a plain WhisperMessage through the trial-decrypt loop (happy path)" do
    %{alice_record: alice_record, alice_store: alice_store} = pair = establish_pair()
    reply = bob_reply(pair, "hi alice")

    {:ok, plaintext, _record} =
      SessionCipher.decrypt_whisper_message(alice_record, reply, alice_store)

    assert plaintext == "hi alice"
  end

  test "a single-session record with a tampered MAC exhausts and raises No matching sessions" do
    %{alice_record: alice_record, alice_store: alice_store} = pair = establish_pair()
    reply = bob_reply(pair, "hi alice")
    tampered = flip_last_byte(reply)

    # The bad MAC raises DecryptError inside the per-session decrypt; the loop
    # catches it, has no further sessions to try, and ends in the "no matching
    # sessions" RuntimeError (not a DecryptError leaking out).
    assert_raise RuntimeError, ~r/No matching sessions found/, fn ->
      SessionCipher.decrypt_whisper_message(alice_record, tampered, alice_store)
    end
  end

  test "a non-DecryptError inside per-session decrypt propagates (narrowed rescue guard)" do
    %{alice_record: alice_record, alice_store: alice_store} = pair = establish_pair()
    reply = bob_reply(pair, "hi alice")

    # A store missing :our_identity makes `store.our_identity` raise KeyError
    # *inside* do_decrypt_whisper_message (after the MAC-independent ratchet
    # steps). The rescue only catches DecryptError, so this must propagate as a
    # KeyError — NOT be swallowed into "No matching sessions found".
    broken_store = Map.delete(alice_store, :our_identity)

    assert_raise KeyError, fn ->
      SessionCipher.decrypt_whisper_message(alice_record, reply, broken_store)
    end
  end

  # Establish a mutual Alice(initiator)/Bob(responder) session in Elixir and
  # return each side's record + cipher store.
  defp establish_pair do
    bob_identity = Crypto.generate_key_pair()
    bob_signed = Crypto.generate_key_pair()
    bob_prekey = Crypto.generate_key_pair()
    bob_spk_id = 1
    bob_prekey_id = 31_337
    bob_reg_id = 4242

    bob_store = %{
      our_identity: bob_identity,
      our_registration_id: bob_reg_id,
      load_signed_pre_key: fn id ->
        if id == bob_spk_id or is_nil(id), do: bob_signed, else: nil
      end,
      load_pre_key: fn id -> if id == bob_prekey_id, do: bob_prekey, else: nil end
    }

    alice_identity = Crypto.generate_key_pair()

    alice_store = %{
      our_identity: alice_identity,
      our_registration_id: 5555,
      load_signed_pre_key: fn _ -> nil end,
      load_pre_key: fn _ -> nil end
    }

    # Bob's prekey bundle as Alice's init_outgoing consumes it. libsignal signs
    # the wire-form (33B 0x05-prefixed) signed prekey with the identity key.
    bob_signed_wire = <<5>> <> bob_signed.public
    signature = Crypto.sign(bob_signed_wire, bob_identity.private)

    device = %{
      registration_id: bob_reg_id,
      identity_key: <<5>> <> bob_identity.public,
      signed_pre_key: %{key_id: bob_spk_id, public: bob_signed_wire, signature: signature},
      pre_key: %{key_id: bob_prekey_id, public: <<5>> <> bob_prekey.public}
    }

    alice_record = SessionBuilder.init_outgoing(SessionRecord.new(), device, alice_store)

    {:ok, :pkmsg, opening, alice_record} =
      SessionCipher.encrypt(alice_record, "hello bob", alice_store)

    {:ok, "hello bob", bob_record, _pre_key_id} =
      SessionCipher.decrypt_pre_key_whisper_message(nil, opening, bob_store)

    %{
      alice_record: alice_record,
      alice_store: alice_store,
      bob_record: bob_record,
      bob_store: bob_store
    }
  end

  # Bob encrypts a plain WhisperMessage (:msg) reply back to Alice.
  defp bob_reply(%{bob_record: bob_record, bob_store: bob_store}, text) do
    {:ok, :msg, body, _record} = SessionCipher.encrypt(bob_record, text, bob_store)
    body
  end

  defp flip_last_byte(bin) do
    head = binary_part(bin, 0, byte_size(bin) - 1)
    last = :binary.last(bin)
    <<head::binary, bxor(last, 0x01)>>
  end
end
