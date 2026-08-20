defmodule Amarula.Content.MediaTest do
  use ExUnit.Case, async: true

  alias Amarula.Content.Media
  alias Amarula.Protocol.Proto

  describe "from_proto/2" do
    test "surfaces a declared mimetype as-is" do
      img = %Proto.Message.ImageMessage{directPath: "/x", mediaKey: <<1>>, mimetype: "image/jpeg"}
      assert %Media{mimetype: "image/jpeg"} = Media.from_proto(:image, img)
    end

    test "an absent mimetype is nil" do
      img = %Proto.Message.ImageMessage{directPath: "/x", mediaKey: <<1>>}
      assert %Media{mimetype: nil} = Media.from_proto(:image, img)
    end

    test "an explicit blank/whitespace mimetype normalizes to nil" do
      img = %Proto.Message.ImageMessage{directPath: "/x", mediaKey: <<1>>, mimetype: "   "}
      assert %Media{mimetype: nil} = Media.from_proto(:image, img)

      sticker = %Proto.Message.StickerMessage{directPath: "/x", mediaKey: <<1>>, mimetype: ""}
      assert %Media{mimetype: nil} = Media.from_proto(:sticker, sticker)
    end
  end
end
