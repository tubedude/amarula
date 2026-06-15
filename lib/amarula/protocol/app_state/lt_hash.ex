defmodule Amarula.Protocol.AppState.LTHash do
  @moduledoc """
  LT Hash — the summation hash that keeps app-state integrity across mutations.
  Ported from Baileys' pre-WASM pure-JS impl (`src/Utils/lt-hash.ts` before the
  rust bridge). Adding/removing a mutation gives the same hash as if the whole
  sequence had been applied in order, so patches can be verified incrementally.

  The hash is 128 bytes = 64 little-endian unsigned 16-bit words. Each mutation
  `mac` is expanded with `HKDF(mac, 128, salt="", info="WhatsApp Patch Integrity")`
  into the same 64-word space and added/subtracted pointwise mod 2^16 (wraparound).

  `subtract_then_add/3` is the operation app-state uses: drop the macs of removed
  records, add the macs of new ones.
  """

  alias Amarula.Protocol.Crypto.Crypto

  @hash_bytes 128
  @info "WhatsApp Patch Integrity"
  @wrap 0x1_0000

  @doc "A fresh, all-zero 128-byte hash."
  @spec zero() :: binary()
  def zero, do: <<0::size(@hash_bytes * 8)>>

  @doc "Add each mac in `macs` to `hash` (pointwise, with wraparound)."
  @spec add(binary(), [binary()]) :: binary()
  def add(hash, macs), do: Enum.reduce(macs, hash, &pointwise(&2, &1, :add))

  @doc "Subtract each mac in `macs` from `hash`."
  @spec subtract(binary(), [binary()]) :: binary()
  def subtract(hash, macs), do: Enum.reduce(macs, hash, &pointwise(&2, &1, :sub))

  @doc "Subtract the `subtract` macs, then add the `add` macs."
  @spec subtract_then_add(binary(), [binary()], [binary()]) :: binary()
  def subtract_then_add(hash, subtract, add) do
    hash |> subtract(subtract) |> add(add)
  end

  # Expand a mac to the 64-word space and combine pointwise with the hash.
  defp pointwise(hash, mac, op) do
    derived = Crypto.hkdf(mac, @hash_bytes, <<>>, @info)
    combine(hash, derived, op, [])
  end

  defp combine(<<>>, <<>>, _op, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp combine(<<a::little-16, ra::binary>>, <<b::little-16, rb::binary>>, op, acc) do
    word =
      case op do
        :add -> rem(a + b, @wrap)
        :sub -> rem(a - b + @wrap, @wrap)
      end

    combine(ra, rb, op, [<<word::little-16>> | acc])
  end
end
