defmodule Amarula.Protocol.Groups.NotificationTest do
  use ExUnit.Case, async: true

  alias Amarula.Address
  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Groups.Notification

  defp gp2(from, participant, child) do
    %Node{
      tag: "notification",
      attrs: %{"type" => "w:gp2", "from" => from, "participant" => participant},
      content: [child]
    }
  end

  @group "120363000000000000@g.us"
  @author "5511999999999@s.whatsapp.net"

  test "parses participant add with admin type" do
    child = %Node{
      tag: "add",
      attrs: %{},
      content: [
        %Node{tag: "participant", attrs: %{"jid" => "5511888888888@s.whatsapp.net"}, content: nil}
      ]
    }

    assert {:ok, update} = Notification.parse(gp2(@group, @author, child))
    assert %Address{kind: :group} = update.group
    assert %Address{user: "5511999999999"} = update.author

    assert {:participants, :add, [%{address: %Address{user: "5511888888888"}, admin: nil}]} =
             update.action
  end

  test "promote carries the admin type" do
    child = %Node{
      tag: "promote",
      attrs: %{},
      content: [
        %Node{
          tag: "participant",
          attrs: %{"jid" => "5511888888888@s.whatsapp.net", "type" => "admin"},
          content: nil
        }
      ]
    }

    assert {:ok, %{action: {:participants, :promote, [%{admin: "admin"}]}}} =
             Notification.parse(gp2(@group, @author, child))
  end

  test "subject change" do
    child = %Node{tag: "subject", attrs: %{"subject" => "New Name"}, content: nil}

    assert {:ok, %{action: {:subject, "New Name"}}} =
             Notification.parse(gp2(@group, @author, child))
  end

  test "announce on/off" do
    on = %Node{tag: "announcement", attrs: %{}, content: nil}
    off = %Node{tag: "not_announcement", attrs: %{}, content: nil}
    assert {:ok, %{action: {:announce, true}}} = Notification.parse(gp2(@group, @author, on))
    assert {:ok, %{action: {:announce, false}}} = Notification.parse(gp2(@group, @author, off))
  end

  test "lock/unlock maps to restrict" do
    locked = %Node{tag: "locked", attrs: %{}, content: nil}
    assert {:ok, %{action: {:restrict, true}}} = Notification.parse(gp2(@group, @author, locked))
  end

  test "unknown child surfaces as {:other, tag} rather than dropping" do
    child = %Node{tag: "some_future_thing", attrs: %{}, content: nil}

    assert {:ok, %{action: {:other, "some_future_thing"}}} =
             Notification.parse(gp2(@group, @author, child))
  end

  test "no change child is an error" do
    node = %Node{tag: "notification", attrs: %{"type" => "w:gp2"}, content: []}
    assert {:error, :no_change_child} = Notification.parse(node)
  end

  test "missing participant attr yields nil author" do
    child = %Node{tag: "subject", attrs: %{"subject" => "x"}, content: nil}
    node = %Node{tag: "notification", attrs: %{"from" => @group}, content: [child]}
    assert {:ok, %{author: nil}} = Notification.parse(node)
  end
end
