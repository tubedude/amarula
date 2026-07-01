defmodule Amarula.Protocol.Crypto.XEdDSA do
  @moduledoc """
  XEd25519 signatures over Curve25519 (X25519) keys, compatible with libsignal's
  `curve25519_sign` / `curve25519_verify` — what Baileys calls `Curve.sign` / `Curve.verify`.

  WhatsApp signs the signed pre-key, the device signature (pairing) and verifies the
  account signature with this scheme, NOT plain Ed25519:

  - Keys are X25519 (Montgomery) keypairs; the same key does DH and signing.
  - sign: derive the Edwards public key A = a*B from the Montgomery private scalar,
    produce a standard Ed25519 signature with a randomized nonce, then store the
    sign bit of A in the top bit of the last signature byte (libsignal sign_modified.c).
  - verify: convert the Montgomery public key to an Edwards key using the sign bit
    carried in the signature, clear that bit, then run standard Ed25519 verification.

  Deviation from libsignal's C: the bignum double-and-add here is NOT
  constant-time (it branches on secret scalar bits), so signing leaks timing.
  Acceptable for a client — exploiting it needs a local high-resolution timing
  oracle — but don't reuse this where a hostile co-tenant could measure it.
  """

  import Bitwise

  # Curve25519 field prime and Ed25519 group order
  @p (1 <<< 255) - 19
  @l (1 <<< 252) + 27_742_317_777_372_353_535_851_937_790_883_648_493

  # Twisted Edwards constant d = -121665/121666 mod p
  @d 37_095_705_934_669_439_343_138_083_508_754_565_189_542_113_879_843_219_016_388_785_533_085_940_283_555

  # Ed25519 base point (extended coordinates with Z = 1, T = X*Y)
  @bx 15_112_221_349_535_400_772_501_151_409_588_531_511_454_012_693_041_857_206_046_113_283_949_847_762_202
  @by 46_316_835_694_926_478_169_428_394_003_475_163_141_307_993_866_256_225_615_783_033_603_165_251_855_960

  # Hash-domain-separation prefix used by libsignal's sign_modified
  @sign_prefix <<0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>

  @doc """
  Sign `message` with a 32-byte X25519 private key. Returns a 64-byte signature
  verifiable by libsignal's `curve25519_verify` against the Montgomery public key.
  """
  @spec sign(binary(), binary()) :: binary()
  def sign(message, <<private::binary-size(32)>>) do
    a = clamp(:binary.decode_unsigned(private, :little))
    scalar = :binary.encode_unsigned(a, :little) |> pad_le(32)

    a_enc = encode_point(scalar_mult_base(a))
    sign_bit = :binary.at(a_enc, 31) &&& 0x80

    random = :crypto.strong_rand_bytes(64)
    nonce = sha512_mod_l(@sign_prefix <> scalar <> message <> random)
    r_enc = encode_point(scalar_mult_base(nonce))

    hram = sha512_mod_l(r_enc <> a_enc <> message)
    s = Integer.mod(hram * a + nonce, @l)
    s_enc = :binary.encode_unsigned(s, :little) |> pad_le(32)

    <<sig_head::binary-size(63), last>> = r_enc <> s_enc
    <<sig_head::binary, (last &&& 0x7F) ||| sign_bit>>
  end

  @doc """
  Verify a 64-byte XEd25519 `signature` over `message` against a 32-byte
  Montgomery (X25519) public key.
  """
  @spec verify(binary(), binary(), binary()) :: boolean()
  def verify(message, <<sig::binary-size(64)>>, <<mont_pub::binary-size(32)>>) do
    <<sig_head::binary-size(63), last>> = sig
    sign_bit = last &&& 0x80
    ed25519_sig = <<sig_head::binary, last &&& 0x7F>>

    case montgomery_to_edwards(mont_pub, sign_bit) do
      {:ok, ed_pub} ->
        :crypto.verify(:eddsa, :none, message, ed25519_sig, [ed_pub, :ed25519])

      :error ->
        false
    end
  end

  def verify(_message, _signature, _public_key), do: false

  @doc """
  Convert a Montgomery u-coordinate public key to an Ed25519 public key:
  y = (u - 1) / (u + 1) mod p, with the given sign bit (0 or 0x80) placed in the
  top bit of the last byte. Returns :error when u = -1 (no inverse).
  """
  @spec montgomery_to_edwards(binary(), 0 | 0x80) :: {:ok, binary()} | :error
  def montgomery_to_edwards(<<mont_pub::binary-size(32)>>, sign_bit) do
    # Bit 255 is ignored for Montgomery keys (RFC 7748)
    u = Integer.mod(:binary.decode_unsigned(mont_pub, :little) &&& (1 <<< 255) - 1, @p)

    if u == @p - 1 do
      :error
    else
      y = Integer.mod((u - 1) * inv(u + 1), @p)
      <<head::binary-size(31), last>> = :binary.encode_unsigned(y, :little) |> pad_le(32)
      {:ok, <<head::binary, (last &&& 0x7F) ||| sign_bit>>}
    end
  end

  # --- Edwards curve arithmetic (a = -1, extended coordinates) ---

  # Unified addition (add-2008-hwcd-3), valid for doubling as well
  defp point_add({x1, y1, z1, t1}, {x2, y2, z2, t2}) do
    a = Integer.mod((y1 - x1) * (y2 - x2), @p)
    b = Integer.mod((y1 + x1) * (y2 + x2), @p)
    c = Integer.mod(2 * t1 * t2 * @d, @p)
    d = Integer.mod(2 * z1 * z2, @p)
    e = b - a
    f = d - c
    g = d + c
    h = b + a

    {Integer.mod(e * f, @p), Integer.mod(g * h, @p), Integer.mod(f * g, @p),
     Integer.mod(e * h, @p)}
  end

  defp scalar_mult_base(k), do: scalar_mult(k, {@bx, @by, 1, Integer.mod(@bx * @by, @p)})

  defp scalar_mult(k, point), do: scalar_mult(k, point, {0, 1, 1, 0})

  defp scalar_mult(0, _point, acc), do: acc

  defp scalar_mult(k, point, acc) do
    acc = if (k &&& 1) == 1, do: point_add(acc, point), else: acc
    scalar_mult(k >>> 1, point_add(point, point), acc)
  end

  defp encode_point({x, y, z, _t}) do
    zinv = inv(z)
    affine_x = Integer.mod(x * zinv, @p)
    affine_y = Integer.mod(y * zinv, @p)

    <<head::binary-size(31), last>> = :binary.encode_unsigned(affine_y, :little) |> pad_le(32)
    <<head::binary, last ||| (affine_x &&& 1) <<< 7>>
  end

  # --- helpers ---

  defp clamp(a), do: (a &&& (1 <<< 254) - 8) ||| 1 <<< 254

  defp inv(x), do: pow_mod(Integer.mod(x, @p), @p - 2, @p)

  defp pow_mod(_base, 0, _m), do: 1

  defp pow_mod(base, exp, m) do
    half = pow_mod(base, exp >>> 1, m)
    sq = Integer.mod(half * half, m)
    if (exp &&& 1) == 1, do: Integer.mod(sq * base, m), else: sq
  end

  defp sha512_mod_l(data) do
    :crypto.hash(:sha512, data) |> :binary.decode_unsigned(:little) |> Integer.mod(@l)
  end

  defp pad_le(bin, size) when byte_size(bin) >= size, do: binary_part(bin, 0, size)
  defp pad_le(bin, size), do: bin <> :binary.copy(<<0>>, size - byte_size(bin))
end
