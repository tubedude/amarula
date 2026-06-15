defmodule Amarula.Protocol.Messages.MediaTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Messages.Media

  test "encrypt/decrypt round-trips and verifies the MAC" do
    data = :crypto.strong_rand_bytes(5000)
    {:ok, e} = Media.encrypt(data, :image)

    assert byte_size(e.media_key) == 32
    assert e.file_length == 5000
    assert e.file_sha256 == :crypto.hash(:sha256, data)
    assert e.file_enc_sha256 == :crypto.hash(:sha256, e.enc)

    assert {:ok, ^data} = Media.decrypt(e.enc, e.media_key, :image)
  end

  test "decrypt rejects a tampered blob" do
    {:ok, e} = Media.encrypt(<<1, 2, 3>>, :image)
    tampered = binary_part(e.enc, 0, byte_size(e.enc) - 1) <> <<:binary.last(e.enc) + 1>>
    assert {:error, :bad_mac} = Media.decrypt(tampered, e.media_key, :image)
  end

  test "round-trips a block-aligned payload (exercises PKCS#7 full block)" do
    data = :crypto.strong_rand_bytes(48)
    {:ok, e} = Media.encrypt(data, :document)
    assert {:ok, ^data} = Media.decrypt(e.enc, e.media_key, :document)
  end
end
