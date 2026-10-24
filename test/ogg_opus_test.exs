defmodule Amarula.OggOpusTest do
  use ExUnit.Case, async: true

  alias Amarula.OggOpus

  # One Ogg page: header + segment table + body (CRC left zero: we never verify it).
  defp page(granule, body, type \\ 0) do
    segs = segments(byte_size(body))

    <<"OggS", 0, type, granule::little-signed-64, 1::little-32, 0::little-32, 0::32,
      length(segs)>> <> IO.iodata_to_binary(segs) <> body
  end

  defp segments(n) when n < 255, do: [n]
  defp segments(n), do: [255 | segments(n - 255)]

  defp opus_head(channels, pre_skip),
    do: <<"OpusHead", 1, channels, pre_skip::little-16, 48_000::little-32, 0::16, 0>>

  defp ogg(channels, pre_skip, last_granule) do
    page(0, opus_head(channels, pre_skip), 2) <>
      page(0, "OpusTags" <> <<0::32, 0::32>>) <>
      page(div(last_granule, 2), :binary.copy(<<0xAB>>, 300)) <>
      page(last_granule, :binary.copy(<<0xCD>>, 300), 4)
  end

  test "duration is (last granule − pre-skip) / 48 kHz, rounded up" do
    # 4.5 s of audio after a 312-sample pre-skip (OpenAI's value).
    bytes = ogg(1, 312, 312 + 216_000)
    assert {:ok, %{channels: 1, pre_skip: 312, samples: 216_000}} = OggOpus.info(bytes)
    assert {:ok, 5} = OggOpus.seconds(bytes)
  end

  test "an exact second does not round up, and a tiny clip is at least 1 s" do
    assert {:ok, 3} = OggOpus.seconds(ogg(1, 0, 144_000))
    assert {:ok, 1} = OggOpus.seconds(ogg(1, 312, 400))
  end

  test "mono Ogg/Opus is a voice note as it is; stereo is not" do
    assert OggOpus.voice_note?(ogg(1, 312, 48_000))
    refute OggOpus.voice_note?(ogg(2, 312, 48_000))
  end

  test "anything that is not Ogg/Opus is refused" do
    assert {:error, :not_ogg_opus} = OggOpus.info("RIFF....WAVEfmt ")
    assert {:error, :not_ogg_opus} = OggOpus.info(<<"OggS", 0>>)
    # Ogg, but Vorbis — not Opus.
    assert {:error, :not_ogg_opus} = OggOpus.info(page(0, "\x01vorbis" <> <<0::64>>, 2))
    assert {:error, :not_ogg_opus} = OggOpus.info("")
    refute OggOpus.voice_note?("not audio")
  end

  test "maybe_put_seconds/3 fills :seconds on :audio when omitted and data is Ogg/Opus" do
    bytes = ogg(1, 312, 312 + 216_000)
    assert OggOpus.maybe_put_seconds([ptt: true], :audio, bytes) == [seconds: 5, ptt: true]

    assert OggOpus.maybe_put_seconds([seconds: 9, ptt: true], :audio, bytes) == [
             seconds: 9,
             ptt: true
           ]

    assert OggOpus.maybe_put_seconds([ptt: true], :audio, "not ogg") == [ptt: true]
    assert OggOpus.maybe_put_seconds([], :image, bytes) == []
  end

  @tag :ffmpeg
  test "agrees with ffprobe on a real Opus encode" do
    if System.find_executable("ffmpeg") && System.find_executable("ffprobe") do
      dir = Path.join(System.tmp_dir!(), "ogg_opus_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)
      out = Path.join(dir, "tone.ogg")

      {_, 0} =
        System.cmd(
          "ffmpeg",
          ~w[-y -loglevel error -f lavfi -i sine=frequency=440:duration=4.5 -ac 1 -c:a libopus] ++
            [out],
          stderr_to_stdout: true
        )

      {probe, 0} =
        System.cmd("ffprobe", ~w[-v error -show_entries format=duration -of csv=p=0] ++ [out])

      expected = probe |> String.trim() |> String.to_float()
      bytes = File.read!(out)
      {:ok, %{samples: samples}} = OggOpus.info(bytes)

      assert_in_delta samples / 48_000, expected, 0.03
      assert {:ok, 5} = OggOpus.seconds(bytes)
      assert OggOpus.voice_note?(bytes)
    end
  end
end
