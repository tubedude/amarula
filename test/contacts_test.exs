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
  @lid "111111111111111@lid"

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

  describe "resolve_lid query construction" do
    # resolve_lid needs BOTH protocols: :contact (gives the PN id) and :lid (gives
    # the LID); on_whatsapp's contact-only query can't establish a mapping.
    test "is a lid+contact USync with one phone user per number" do
      query =
        USync.new()
        |> USync.with_context("interactive")
        |> USync.with_mode("query")
        |> USync.with_protocol(:lid)
        |> USync.with_protocol(:contact)
        |> USync.with_user(%{phone: @phone})

      {:ok, iq} = USync.build_iq(query)
      usync = NodeUtils.get_binary_node_child(iq, "usync")
      query_node = NodeUtils.get_binary_node_child(usync, "query")
      assert Enum.sort(Enum.map(query_node.content, & &1.tag)) == ["contact", "lid"]

      list = NodeUtils.get_binary_node_child(usync, "list")
      [user] = list.content
      [contact] = user.content
      assert contact.content == @phone
    end
  end

  describe "reply contract consumed by the mapper" do
    test "a lid reply parses to `\"lid\" => <lid jid>` keyed by the PN jid" do
      # entry_lid_pn pairs entry[:id] (PN) with entry["lid"] (LID); both must be
      # present and the lid non-empty for a mapping to be stored.
      query = USync.new() |> USync.with_protocol(:lid) |> USync.with_protocol(:contact)

      reply = lid_reply(@jid, @lid)
      assert %{list: [entry]} = USync.parse_result(query, reply)
      assert entry.id == @jid
      assert entry["lid"] == @lid
    end

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

  defp lid_reply(jid, lid) do
    usync_reply([
      %Node{
        tag: "user",
        attrs: %{"jid" => jid},
        content: [
          %Node{tag: "lid", attrs: %{"val" => lid}, content: nil},
          %Node{tag: "contact", attrs: %{"type" => "in"}, content: nil}
        ]
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

  # A stub that answers Connection.get_conn (:conn) with a real %Conn{} so the
  # local LID-mapping lookups read the populated store (no live socket).
  defmodule StubConn do
    use GenServer
    def start_link(conn), do: GenServer.start_link(__MODULE__, conn)
    def init(conn), do: {:ok, conn}
    def handle_call(:conn, _from, conn), do: {:reply, conn, conn}
  end

  describe "pn_for_lid/2 and lid_for_pn/2 (local store lookup — #2263)" do
    alias Amarula.Contacts
    alias Amarula.Protocol.Signal.LidMappingFileStore

    setup do
      dir =
        Path.join(System.tmp_dir!(), "amarula_contacts_lid_#{System.unique_integer([:positive])}")

      on_exit(fn -> File.rm_rf(dir) end)
      conn_struct = Amarula.TestConn.new(dir)
      LidMappingFileStore.store_mappings(conn_struct, [{@lid, @jid}])
      {:ok, pid} = StubConn.start_link(conn_struct)
      {:ok, pid: pid}
    end

    test "resolves a known LID to its PN address", %{pid: pid} do
      pn = Contacts.pn_for_lid(pid, @lid)
      assert %Amarula.Address{kind: :pn, user: "15550001234"} = pn
    end

    test "resolves a known PN to its LID address (inverse)", %{pid: pid} do
      lid = Contacts.lid_for_pn(pid, @jid)
      assert %Amarula.Address{kind: :lid, user: "111111111111111"} = lid
    end

    test "returns nil for an unmapped id", %{pid: pid} do
      assert Contacts.pn_for_lid(pid, "999999999999999@lid") == nil
      assert Contacts.lid_for_pn(pid, "15559999999@s.whatsapp.net") == nil
    end
  end
end
