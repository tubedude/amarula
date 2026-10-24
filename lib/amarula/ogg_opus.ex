defmodule Amarula.OggOpus do
  @moduledoc """
  Read an Ogg/Opus audio stream's channel count and duration in pure Elixir — no `ffmpeg`.

  WhatsApp voice notes (and TTS outputs like OpenAI's `opus` format) are Ogg/Opus streams
  (48 kHz). WhatsApp requires `:seconds` on outbound `:audio` messages so iPhones play
  clips longer than ~10 seconds (Baileys #2646), and Ogg makes that duration cheap to read
  directly from the container bytes:

    * Every Ogg page header carries a 64-bit **granule position**; for Opus it is the
      number of 48 kHz samples decoded up to the end of that page (RFC 7845 §4). The
      last page's granule is the stream's total.
    * The first packet, `OpusHead`, carries the channel count and the **pre-skip**:
      samples the decoder discards at the start. Duration = `(granule − pre_skip) / 48_000`,
      regardless of the original input sample rate (Opus always counts at 48 kHz).

  `Amarula.send_media/5` calls `seconds/1` automatically when sending `:audio` without an
  explicit `:seconds` option, and you can also call `info/1`, `seconds/1`, or
  `voice_note?/1` directly in your own media pipeline.

  Page header layout (RFC 3533): `"OggS"`, version (1), type (1), granule (8, little-
  endian, signed), serial (4), sequence (4), CRC (4), segment count (1), then the
  segment table. `OpusHead`: magic (8), version (1), channels (1), pre-skip (2, LE),
  input rate (4), gain (2), mapping family (1).
  """

  @rate 48_000

  @typedoc "Parsed Ogg/Opus header and sample count."
  @type info :: %{channels: pos_integer(), pre_skip: non_neg_integer(), samples: integer()}

  @doc """
  Parse `bytes` as Ogg/Opus.

  Returns `{:ok, %{channels: pos_integer(), pre_skip: non_neg_integer(), samples: integer()}}`
  or `{:error, :not_ogg_opus}` for anything else (WAV, MP3, Vorbis, or a truncated file).
  """
  @spec info(binary()) :: {:ok, info()} | {:error, :not_ogg_opus}
  def info(
        <<"OggS", _version, _type, _granule::64, _serial::32, _seq::32, _crc::32, nsegs,
          rest::binary>> = bytes
      )
      when byte_size(rest) >= nsegs do
    <<_table::binary-size(^nsegs), body::binary>> = rest

    with <<"OpusHead", _v, channels, pre_skip::little-16, _::binary>> <- body,
         true <- channels >= 1,
         granule when is_integer(granule) <- last_granule(bytes) do
      {:ok, %{channels: channels, pre_skip: pre_skip, samples: granule - pre_skip}}
    else
      _ -> {:error, :not_ogg_opus}
    end
  end

  def info(_bytes), do: {:error, :not_ogg_opus}

  @doc """
  Whole seconds, rounded up, at least `1` — the value `:seconds` on `Amarula.send_media/5` expects.
  """
  @spec seconds(binary()) :: {:ok, pos_integer()} | {:error, :not_ogg_opus}
  def seconds(bytes) do
    case info(bytes) do
      {:ok, %{samples: samples}} -> {:ok, max(ceil_div(samples, @rate), 1)}
      error -> error
    end
  end

  @doc "True when `bytes` is a mono Ogg/Opus stream (a WhatsApp voice note as-is)."
  @spec voice_note?(binary()) :: boolean()
  def voice_note?(bytes), do: match?({:ok, %{channels: 1}}, info(bytes))

  @doc false
  @spec maybe_put_seconds(keyword(), atom(), binary()) :: keyword()
  def maybe_put_seconds(opts, :audio, data) when is_list(opts) and is_binary(data) do
    case {Keyword.get(opts, :seconds), seconds(data)} do
      {nil, {:ok, secs}} -> Keyword.put(opts, :seconds, secs)
      _ -> opts
    end
  end

  def maybe_put_seconds(opts, _type, _data), do: opts

  # The granule of the LAST page: scan for the final "OggS" capture pattern. Opus audio
  # is high-entropy, so a stray "OggS" inside a packet is possible in principle; a real
  # page also has version 0, which we check, and a candidate that fails falls back to
  # the one before it.
  defp last_granule(bytes) do
    bytes
    |> :binary.matches("OggS")
    |> Enum.reverse()
    |> Enum.find_value(fn {pos, _len} -> granule_at(bytes, pos) end)
  end

  defp granule_at(bytes, pos) do
    case bytes do
      <<_::binary-size(^pos), "OggS", 0, _type, granule::little-signed-64, _::binary>>
      when granule >= 0 ->
        granule

      _ ->
        nil
    end
  end

  defp ceil_div(n, d) when n <= 0, do: div(n, d)
  defp ceil_div(n, d), do: div(n + d - 1, d)
end
