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

  describe "parse_update/1" do
    test "available presence" do
      node = %Node{tag: "presence", attrs: %{"from" => "999@s.whatsapp.net"}, content: nil}

      assert {:ok,
              %{
                jid: "999@s.whatsapp.net",
                participant: "999@s.whatsapp.net",
                presence: :available,
                last_seen: nil
              }} = Presence.parse_update(node)
    end

    test "unavailable presence with last seen" do
      node = %Node{
        tag: "presence",
        attrs: %{"from" => "999@s.whatsapp.net", "type" => "unavailable", "last" => "1700000000"},
        content: nil
      }

      assert {:ok, %{presence: :unavailable, last_seen: 1_700_000_000}} =
               Presence.parse_update(node)
    end

    test "last=deny is dropped" do
      node = %Node{
        tag: "presence",
        attrs: %{"from" => "999@s.whatsapp.net", "last" => "deny"},
        content: nil
      }

      assert {:ok, %{last_seen: nil}} = Presence.parse_update(node)
    end

    test "chatstate composing uses participant when present" do
      node = %Node{
        tag: "chatstate",
        attrs: %{"from" => "g@g.us", "participant" => "999@lid"},
        content: [%Node{tag: "composing", attrs: %{}, content: nil}]
      }

      assert {:ok, %{jid: "g@g.us", participant: "999@lid", presence: :composing}} =
               Presence.parse_update(node)
    end

    test "chatstate composing+media:audio is recording" do
      node = %Node{
        tag: "chatstate",
        attrs: %{"from" => "999@lid"},
        content: [%Node{tag: "composing", attrs: %{"media" => "audio"}, content: nil}]
      }

      assert {:ok, %{presence: :recording}} = Presence.parse_update(node)
    end

    test "chatstate paused maps to available" do
      node = %Node{
        tag: "chatstate",
        attrs: %{"from" => "999@lid"},
        content: [%Node{tag: "paused", attrs: %{}, content: nil}]
      }

      assert {:ok, %{presence: :available}} = Presence.parse_update(node)
    end

    test "chatstate update always includes :last_seen (defaults to nil)" do
      node = %Node{
        tag: "chatstate",
        attrs: %{"from" => "999@lid"},
        content: [%Node{tag: "composing", attrs: %{}, content: nil}]
      }

      assert {:ok, update} = Presence.parse_update(node)
      assert Map.has_key?(update, :last_seen)
      assert update.last_seen == nil
    end

    test "malformed chatstate is rejected" do
      assert {:error, :invalid} =
               Presence.parse_update(%Node{tag: "chatstate", attrs: %{}, content: nil})
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
