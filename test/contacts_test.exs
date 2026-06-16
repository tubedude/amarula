defmodule Amarula.ContactsTest do
  use ExUnit.Case, async: true

  # Amarula.Contacts builds a USync query, round-trips it via Connection.query_iq/3,
  # and maps USync result entries to %Address{}-bearing maps. Without a live socket
  # we test the two pure seams it owns: the query it constructs, and the contract
  # of the reply it maps (the same `USync.parse_result` output its mapper consumes).
  #
  # Fake placeholder numbers/jids only (repo PII rule).

  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.USync

  @phone "15550001234"
  @jid "15550001234@s.whatsapp.net"

  describe "on_whatsapp query construction" do
    # Mirror what Contacts.on_whatsapp/2 builds, so a regression in protocol/mode/
    # context/user shape is caught here (the build side is pure up to query_iq).
    test "is a contact USync with one phone user per number, jid attr omitted" do
      query =
        USync.new()
        |> USync.with_context("interactive")
        |> USync.with_mode("query")
        |> USync.with_protocol(:contact)
        |> USync.with_user(%{phone: @phone})

      {:ok, iq} = USync.build_iq(query)
      assert NodeUtils.get_attr(iq, "xmlns") == "usync"

      usync = NodeUtils.get_binary_node_child(iq, "usync")
      assert NodeUtils.get_attr(usync, "context") == "interactive"
      assert NodeUtils.get_attr(usync, "mode") == "query"

      query_node = NodeUtils.get_binary_node_child(usync, "query")
      assert Enum.map(query_node.content, & &1.tag) == ["contact"]

      list = NodeUtils.get_binary_node_child(usync, "list")
      [user] = list.content
      refute Map.has_key?(user.attrs, "jid")
      [contact] = user.content
      assert contact.content == @phone
    end
  end

  describe "reply contract consumed by the mapper" do
    test "a contact reply parses to `\"contact\" => true/false` keyed by jid" do
      query = USync.new() |> USync.with_protocol(:contact)

      reply = contact_reply(@jid, "in")
      assert %{list: [entry]} = USync.parse_result(query, reply)
      # Contacts.on_whatsapp maps entry[:id] -> Address and entry["contact"] -> exists.
      assert entry.id == @jid
      assert entry["contact"] == true

      not_in = contact_reply(@jid, "out")
      assert %{list: [e2]} = USync.parse_result(query, not_in)
      assert e2["contact"] == false
    end

    test "a status reply parses to %{status, set_at} keyed by jid" do
      query = USync.new() |> USync.with_protocol(:status)

      reply = status_reply(@jid, "busy", 1_700_000_000)
      assert %{list: [entry]} = USync.parse_result(query, reply)
      assert entry.id == @jid
      assert %{status: "busy", set_at: %DateTime{}} = entry["status"]
    end
  end

  defp contact_reply(jid, type) do
    usync_reply([
      %Node{
        tag: "user",
        attrs: %{"jid" => jid},
        content: [%Node{tag: "contact", attrs: %{"type" => type}, content: nil}]
      }
    ])
  end

  defp status_reply(jid, text, ts) do
    usync_reply([
      %Node{
        tag: "user",
        attrs: %{"jid" => jid},
        content: [%Node{tag: "status", attrs: %{"t" => Integer.to_string(ts)}, content: text}]
      }
    ])
  end

  defp usync_reply(users) do
    %Node{
      tag: "iq",
      attrs: %{"type" => "result"},
      content: [
        %Node{
          tag: "usync",
          attrs: %{},
          content: [%Node{tag: "list", attrs: %{}, content: users}]
        }
      ]
    }
  end
end
