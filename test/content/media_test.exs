defmodule Amarula.Content.MediaTest do
  use ExUnit.Case, async: true

  alias Amarula.Content.Media

  doctest Amarula.Content.Media

  @key :crypto.strong_rand_bytes(32)
  @hash :crypto.strong_rand_bytes(32)

  defp attrs(overrides \\ %{}) do
    Map.merge(%{kind: :image, direct_path: "/v/t62.7118-24/abc", media_key: @key}, overrides)
  end

  describe "new/1 accepts" do
    test "an atom-keyed map, carrying the optional metadata through" do
      assert {:ok, media} =
               Media.new(
                 attrs(%{
                   mimetype: "image/jpeg",
                   caption: "hi",
                   file_length: 1234,
                   width: 640,
                   height: 480,
                   file_sha256: @hash,
                   file_enc_sha256: @hash
                 })
               )

      assert %Media{kind: :image, mimetype: "image/jpeg", caption: "hi"} = media
      assert {media.file_length, media.width, media.height} == {1234, 640, 480}
      assert media.media_key == @key
      assert media.file_sha256 == @hash
    end

    test "a string-keyed map with a string kind (a JSON round-trip)" do
      assert {:ok, %Media{kind: :video, direct_path: "/v/x", seconds: 12}} =
               Media.new(%{
                 "kind" => "video",
                 "direct_path" => "/v/x",
                 "media_key" => @key,
                 "seconds" => 12
               })
    end

    test "every kind, as an atom and as a string" do
      for kind <- [:image, :video, :audio, :document, :sticker] do
        assert {:ok, %Media{kind: ^kind}} = Media.new(attrs(%{kind: kind}))
        assert {:ok, %Media{kind: ^kind}} = Media.new(attrs(%{kind: Atom.to_string(kind)}))
      end
    end

    test "an https WhatsApp url as the only locator" do
      url = "https://media-fra3-1.whatsapp.net/v/t62/enc"

      assert {:ok, %Media{url: ^url, direct_path: nil}} =
               Media.new(%{kind: :image, url: url, media_key: @key})
    end

    test "an already-built %Media{} (re-validating one that crossed a boundary)" do
      {:ok, media} = Media.new(attrs())
      assert {:ok, ^media} = Media.new(media)
    end

    # Only our own declared fields are read, so an unfamiliar key is neither an
    # error nor a new atom — it is simply not looked at.
    test "unknown keys, ignoring them" do
      assert {:ok, %Media{}} = Media.new(attrs(%{"there_is_no_such_field" => "x"}))
    end

    test "blank strings as absent fields" do
      assert {:ok, %Media{caption: nil, mimetype: nil}} =
               Media.new(attrs(%{caption: "", mimetype: ""}))
    end
  end

  describe "new/1 rejects" do
    test "a missing or unknown kind" do
      assert {:error, {:invalid, :kind}} = Media.new(Map.delete(attrs(), :kind))
      assert {:error, {:invalid, :kind}} = Media.new(attrs(%{kind: :gif}))
      assert {:error, {:invalid, :kind}} = Media.new(attrs(%{kind: "file"}))
    end

    test "a missing or wrong-sized media key" do
      assert {:error, {:invalid, :media_key}} = Media.new(Map.delete(attrs(), :media_key))
      assert {:error, {:invalid, :media_key}} = Media.new(attrs(%{media_key: <<0::248>>}))
      assert {:error, {:invalid, :media_key}} = Media.new(attrs(%{media_key: "not bytes"}))

      # Base64 is the consumer's encoding, not ours — decode before calling.
      assert {:error, {:invalid, :media_key}} =
               Media.new(attrs(%{media_key: Base.encode64(@key)}))
    end

    test "a wrong-sized hash" do
      assert {:error, {:invalid, :file_sha256}} = Media.new(attrs(%{file_sha256: <<1, 2, 3>>}))

      assert {:error, {:invalid, :file_enc_sha256}} =
               Media.new(attrs(%{file_enc_sha256: <<1, 2, 3>>}))
    end

    test "a negative or non-integer size" do
      assert {:error, {:invalid, :file_length}} = Media.new(attrs(%{file_length: -1}))
      assert {:error, {:invalid, :width}} = Media.new(attrs(%{width: "640"}))
      assert {:error, {:invalid, :seconds}} = Media.new(attrs(%{seconds: 1.5}))
    end

    test "a non-string caption / mimetype / file name" do
      assert {:error, {:invalid, :caption}} = Media.new(attrs(%{caption: :hi}))
      assert {:error, {:invalid, :file_name}} = Media.new(attrs(%{file_name: 42}))
    end

    test "a descriptor with no locator at all" do
      assert {:error, {:invalid, :locator}} = Media.new(%{kind: :image, media_key: @key})
      assert {:error, {:invalid, :locator}} = Media.new(attrs(%{direct_path: ""}))
    end

    test "anything that is not a map" do
      assert {:error, {:invalid, :media}} = Media.new(nil)
      assert {:error, {:invalid, :media}} = Media.new("/v/t62/enc")
    end
  end

  # The point of the constructor: a descriptor rebuilt from stored/untrusted data
  # cannot name the host Amarula will fetch from.
  describe "new/1 locator trust" do
    test "drops the url whenever a usable direct_path is present" do
      assert {:ok, %Media{direct_path: "/v/t62/enc", url: nil}} =
               Media.new(attrs(%{direct_path: "/v/t62/enc", url: "https://evil.example.com/x"}))
    end

    test "rejects a url on a non-WhatsApp host" do
      for url <- [
            "https://evil.example.com/x",
            "https://mmg.whatsapp.net.evil.example.com/x",
            "https://evil-whatsapp.net/x",
            "http://mmg.whatsapp.net/x",
            "https://mmg.whatsapp.net@evil.example.com/x",
            "https://user:pw@mmg.whatsapp.net/x",
            "//evil.example.com/x",
            "file:///etc/passwd",
            "not a url"
          ] do
        assert {:error, {:invalid, :url}} =
                 Media.new(%{kind: :image, url: url, media_key: @key}),
               "expected #{url} to be rejected"
      end
    end

    test "rejects a direct_path that could reach the authority, rather than falling back" do
      for path <- ["@evil.example.com/x", "v/t62/enc", "/v/t62 enc", "/v/t62\r\nX: 1"] do
        assert {:error, {:invalid, :direct_path}} =
                 Media.new(attrs(%{direct_path: path, url: "https://mmg.whatsapp.net/ok"})),
               "expected #{inspect(path)} to be rejected"
      end
    end
  end
end
