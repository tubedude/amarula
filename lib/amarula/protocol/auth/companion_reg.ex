defmodule Amarula.Protocol.Auth.CompanionReg do
  @moduledoc """
  Helpers for the link-code (phone-number) pairing flow.

  Currently this is the Crockford base32 encoder used to mint the 8-character
  pairing code from 5 random bytes — a faithful port of Baileys `bytesToCrockford`
  (`src/Utils/generics.ts`). The companion platform-id table lives in
  `Amarula.Connection` (`companion_platform_id/1`), reused by both QR and
  link-code pairing.
  """

  import Bitwise

  # Crockford base32 alphabet (no I, L, O, U) — must match Baileys
  # CROCKFORD_CHARACTERS exactly or WhatsApp won't recognise the code.
  @crockford "123456789ABCDEFGHJKLMNPQRSTVWXYZ"

  @doc """
  Encode a binary as a Crockford base32 string.

  Groups the input MSB-first into 5-bit chunks; a trailing partial chunk is
  left-padded (shifted up) to a full 5 bits. Mirrors Baileys `bytesToCrockford`.

      iex> Amarula.Protocol.Auth.CompanionReg.crockford_encode(<<0, 1, 2, 3, 4>>)
      "111H51R5"
  """
  @spec crockford_encode(binary()) :: String.t()
  def crockford_encode(bytes) when is_binary(bytes) do
    {chars, value, bit_count} =
      for <<byte <- bytes>>, reduce: {[], 0, 0} do
        {acc, value, bit_count} ->
          value = bor(bsl(value, 8), band(byte, 0xFF))
          bit_count = bit_count + 8
          emit_chunks(acc, value, bit_count)
      end

    chars =
      if bit_count > 0 do
        [acc_char(value, bit_count) | chars]
      else
        chars
      end

    chars |> Enum.reverse() |> IO.iodata_to_binary()
  end

  # Drain full 5-bit groups from the high bits, newest char prepended (list reversed at the end).
  defp emit_chunks(acc, value, bit_count) when bit_count >= 5 do
    char = char_at(band(bsr(value, bit_count - 5), 31))
    emit_chunks([char | acc], value, bit_count - 5)
  end

  defp emit_chunks(acc, value, bit_count), do: {acc, value, bit_count}

  # Trailing partial group: left-pad to 5 bits.
  defp acc_char(value, bit_count), do: char_at(band(bsl(value, 5 - bit_count), 31))

  defp char_at(index), do: binary_part(@crockford, index, 1)
end
