defmodule Amarula.Protocol.Signal.WhisperProtocolTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Signal.WhisperProtocol

  # Vectors encoded with node_modules/libsignal WhisperTextProtocol — see
  # test/fixtures/whisper_vecs.json.
  @vectors "test/fixtures/whisper_vecs.json" |> File.read!() |> JSON.decode!()

  defp h(hex), do: Base.decode16!(hex, case: :lower)

  test "decodes a WhisperMessage" do
    v = @vectors["wm"]
    wm = WhisperProtocol.decode_whisper_message(h(v["enc"]))

    assert wm.ephemeral_key == h(v["ephemeralKey"])
    assert wm.counter == v["counter"]
    assert wm.previous_counter == v["previousCounter"]
    assert wm.ciphertext == h(v["ciphertext"])
  end

  test "decodes a PreKeyWhisperMessage (message field is a full WhisperMessage)" do
    v = @vectors["pk"]
    pk = WhisperProtocol.decode_pre_key_whisper_message(h(v["enc"]))

    assert pk.pre_key_id == v["preKeyId"]
    assert pk.base_key == h(v["baseKey"])
    assert pk.identity_key == h(v["identityKey"])
    assert pk.message == h(v["message"])
    assert pk.registration_id == v["registrationId"]
    assert pk.signed_pre_key_id == v["signedPreKeyId"]
  end

  test "absent optional fields default sensibly" do
    # An empty body: counters default to 0, byte fields to nil
    wm = WhisperProtocol.decode_whisper_message(<<>>)
    assert wm.counter == 0
    assert wm.previous_counter == 0
    assert wm.ephemeral_key == nil
    assert wm.ciphertext == nil
  end
end
