defmodule Amarula.Connection.NotificationsTest do
  @moduledoc "Pure unit tests for the notification parsers — no socket, no state."
  use ExUnit.Case, async: true

  alias Amarula.Connection.Notifications
  alias Amarula.Protocol.Binary.Node

  describe "account_sync/1" do
    test "disappearing_mode → {:disappearing, duration}" do
      node = %Node{
        tag: "notification",
        content: [%Node{tag: "disappearing_mode", attrs: %{"duration" => "604800"}}]
      }

      assert Notifications.account_sync(node) == {:disappearing, "604800"}
    end

    test "blocklist → {:blocklist, items}" do
      node = %Node{
        tag: "notification",
        content: [
          %Node{
            tag: "blocklist",
            content: [
              %Node{tag: "item", attrs: %{"jid" => "1@s.whatsapp.net", "action" => "block"}},
              %Node{tag: "item", attrs: %{"jid" => "2@s.whatsapp.net", "action" => "unblock"}}
            ]
          }
        ]
      }

      assert {:blocklist, items} = Notifications.account_sync(node)

      assert items == [
               %{jid: "1@s.whatsapp.net", action: "block"},
               %{jid: "2@s.whatsapp.net", action: "unblock"}
             ]
    end

    test "a devices child → :own_devices" do
      node = %Node{
        tag: "notification",
        content: [
          %Node{
            tag: "devices",
            content: [%Node{tag: "device", attrs: %{"jid" => "me:2@s.whatsapp.net"}}]
          }
        ]
      }

      assert Notifications.account_sync(node) == :own_devices
    end

    test "unrecognized → :ignore" do
      assert Notifications.account_sync(%Node{tag: "notification", content: []}) == :ignore
    end
  end

  describe "devices/1" do
    test "extracts {tag, normalized + de-duped users}" do
      node = %Node{
        tag: "notification",
        content: [
          %Node{
            tag: "remove",
            content: [
              %Node{tag: "device", attrs: %{"jid" => "5511999@s.whatsapp.net"}},
              %Node{tag: "device", attrs: %{"jid" => "5511999:2@s.whatsapp.net"}},
              %Node{tag: "device", attrs: %{}}
            ]
          }
        ]
      }

      assert {"remove", users} = Notifications.devices(node)
      # both devices normalize to the same bare user → de-duped to one
      assert users == ["5511999@s.whatsapp.net"]
    end

    test "unrecognized child → :ignore" do
      node = %Node{tag: "notification", content: [%Node{tag: "other", content: []}]}
      assert Notifications.devices(node) == :ignore
    end
  end

  describe "picture/1" do
    test "a <set> means changed, carrying picture_id and author" do
      node = %Node{
        tag: "notification",
        attrs: %{"from" => "1@s.whatsapp.net"},
        content: [%Node{tag: "set", attrs: %{"id" => "PIC123", "author" => "9@s.whatsapp.net"}}]
      }

      assert %{
               id: "1@s.whatsapp.net",
               img_url: "changed",
               picture_id: "PIC123",
               author: "9@s.whatsapp.net"
             } = Notifications.picture(node)
    end

    test "a <delete> means removed, no picture_id" do
      node = %Node{
        tag: "notification",
        attrs: %{"from" => "1@s.whatsapp.net"},
        content: [%Node{tag: "delete", attrs: %{}}]
      }

      assert %{id: "1@s.whatsapp.net", img_url: "removed", picture_id: nil, author: nil} =
               Notifications.picture(node)
    end

    test "no action child means removed" do
      node = %Node{tag: "notification", attrs: %{"from" => "1@s.whatsapp.net"}, content: []}
      assert %{img_url: "removed", picture_id: nil} = Notifications.picture(node)
    end
  end
end
