defmodule Amarula.Protocol.Crypto.XEdDSATest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Crypto.{Crypto, XEdDSA}

  # Vectors generated with libsignal (node_modules/libsignal/src/curve.js):
  # calculateSignature(privKey, msg) over X25519 keypairs. Elixir signatures were
  # also cross-checked against libsignal's verifySignature when these were created.
  @libsignal_vectors [
    %{
      priv: "60744d79d0f7e9a4fe5785f86fcb4d2dba2efb02d1895109d155b4bfd2a3105e",
      pub: "b35f8730e1e9d732735f252dc03b8b6284fbd37c4be8bea0edcd7d9154975568",
      msg: "",
      sig:
        "e7eb907e63dfa6b46f005446dbde023d476dc617b37c044f0185842b162140273c746291eaa230c3cd84cddae3d2064875e8dc155c539026f799b633ac61c101"
    },
    %{
      priv: "288405eeb18182cca8791289c1c1d0040b87c5213e39c20ee9a280e7643dda56",
      pub: "bb08464f618221120437768c1cbe33d56584ff6bf7f51cbd6848f96be97c6c35",
      msg: "61",
      sig:
        "edf8ba99b833f02d3ae81d88a09da9343f97588712b1025ed157512fe42a7bff0f9afe949312daf58b0bcfff4b295b71de864451132533918f0b73dd87ccfe8b"
    },
    %{
      priv: "f0d33fbdfe48694443395d978fd2942eb30d2cbe4d649f2bdf868ee0ae8c2276",
      pub: "05b7499eb0c1183101f7e5ecca3e3e96f0faaf954633762276d06b5387953002",
      msg: "68656c6c6f2077686174736170702070616972696e67",
      sig:
        "cc0472160060e3c02d6167b3ffd2bed2f4bf48d7906cab2318f224d718d33106a3f5831b07adf930f39fefe6938c173d4eb863d3ca0c7e1dae4a920d0614ed8c"
    },
    %{
      priv: "409cd5989634bdea177d9a05501dff5176765c2a3f97bbc3739dd535cd1ee674",
      pub: "05ee915a7680739e6145b41231541892e33e4e14bd7be51650b4d2463506dc1e",
      msg:
        "1a0913f0ee88d07b3969a9f4d30c20e31c0ac3986159f00509b4c29c3d6fc84deb542bb80c0d8d73c5db52d289f1a9a31a777dda73ff7106e2c1af9ae3360344c88351fd57f218ebada03915cb1eff9430c7e60902a81127b84a97acae8044a1d8b45c51",
      sig:
        "248b50672c0aef1f498238c26542d83bff1dc06dbdff70c186d20b0394d7bd5692c8bf2730d70b32608d289ae037e436bf48d9d4c47d9299974eb9b73d80fb80"
    }
  ]

  defp decode(vector) do
    Map.new(vector, fn {k, v} -> {k, Base.decode16!(v, case: :lower)} end)
  end

  describe "verify/3 against libsignal signatures" do
    test "accepts signatures produced by libsignal calculateSignature" do
      for vector <- @libsignal_vectors do
        %{pub: pub, msg: msg, sig: sig} = decode(vector)
        assert XEdDSA.verify(msg, sig, pub)
      end
    end

    test "rejects tampered messages" do
      for vector <- @libsignal_vectors do
        %{pub: pub, msg: msg, sig: sig} = decode(vector)
        refute XEdDSA.verify(msg <> <<0>>, sig, pub)
      end
    end

    test "rejects tampered signatures" do
      %{pub: pub, msg: msg, sig: sig} = decode(hd(@libsignal_vectors))
      <<first, rest::binary>> = sig
      refute XEdDSA.verify(msg, <<Bitwise.bxor(first, 1), rest::binary>>, pub)
    end

    test "rejects malformed inputs" do
      %{pub: pub, msg: msg, sig: sig} = decode(hd(@libsignal_vectors))
      refute XEdDSA.verify(msg, sig, <<0::8*31>>)
      refute XEdDSA.verify(msg, <<0::8*63>>, pub)
    end
  end

  describe "sign/2" do
    test "signatures verify against the libsignal vector public keys" do
      for vector <- @libsignal_vectors do
        %{priv: priv, pub: pub, msg: msg} = decode(vector)
        sig = XEdDSA.sign(msg, priv)
        assert byte_size(sig) == 64
        assert XEdDSA.verify(msg, sig, pub)
      end
    end

    test "round-trips with freshly generated X25519 keypairs" do
      for _ <- 1..10 do
        key_pair = Crypto.generate_key_pair()
        msg = :crypto.strong_rand_bytes(:rand.uniform(256))
        sig = XEdDSA.sign(msg, key_pair.private)
        assert XEdDSA.verify(msg, sig, key_pair.public)
        refute XEdDSA.verify(msg <> <<1>>, sig, key_pair.public)
      end
    end

    test "Crypto.sign/Crypto.verify delegate to XEdDSA" do
      key_pair = Crypto.generate_key_pair()
      msg = "signed pre-key payload"
      sig = Crypto.sign(msg, key_pair.private)
      assert Crypto.verify(msg, sig, key_pair.public)
      assert XEdDSA.verify(msg, sig, key_pair.public)
    end
  end
end
