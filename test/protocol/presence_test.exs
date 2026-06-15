defmodule Amarula.Protocol.PresenceTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Presence

  @me %{id: "10000000001@s.whatsapp.net", lid: "20000000001@lid", name: "Tester"}

  describe "presence/2" do
    test "available carries name (no @) and type" do
      assert {:ok, %Node{tag: "presence", attrs: %{"name" => "Tester", "type" => "available"}}} =
               Presence.presence(:available, @me)
    end

    test "unavailable" do
      assert {:ok, %Node{attrs: %{"type" => "unavailable"}}} =
               Presence.presence(:unavailable, @me)
    end

    test "strips @ from the name" do
      assert {:ok, %Node{attrs: %{"name" => "abc"}}} =
               Presence.presence(:available, %{name: "a@b@c"})
    end

    test "errors without a name" do
      assert {:error, :no_name} = Presence.presence(:available, %{name: nil})
      assert {:error, :no_name} = Presence.presence(:available, %{})
    end
  end

  describe "chatstate/3" do
    test "composing to a pn jid uses me.id as from" do
      node = Presence.chatstate(:composing, "999@s.whatsapp.net", @me)

      assert %Node{
               tag: "chatstate",
               attrs: %{"from" => "10000000001@s.whatsapp.net", "to" => "999@s.whatsapp.net"}
             } = node

      assert [%Node{tag: "composing", attrs: %{}}] = node.content
    end

    test "to a lid jid uses me.lid as from" do
      node = Presence.chatstate(:composing, "555@lid", @me)
      assert node.attrs["from"] == "20000000001@lid"
    end

    test "recording is a composing tag flagged audio" do
      node = Presence.chatstate(:recording, "999@s.whatsapp.net", @me)
      assert [%Node{tag: "composing", attrs: %{"media" => "audio"}}] = node.content
    end

    test "paused" do
      node = Presence.chatstate(:paused, "999@s.whatsapp.net", @me)
      assert [%Node{tag: "paused"}] = node.content
    end
  end

  test "subscribe/2" do
    assert %Node{
             tag: "presence",
             attrs: %{"to" => "999@s.whatsapp.net", "type" => "subscribe", "id" => "TAG1"}
           } =
             Presence.subscribe("999@s.whatsapp.net", "TAG1")
  end
end
