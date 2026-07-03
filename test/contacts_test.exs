defmodule Amarula.ContactsTest do
  use ExUnit.Case, async: true

  # Amarula.Contacts builds a USync query, round-trips it via Connection.query_iq/3,
  # and maps USync result entries to %Address{}-bearing maps. These tests call the
  # REAL module against an offline sandbox connection: each public function runs in
  # a Task (query_iq blocks on the reply), the test captures the outbound IQ via
  # the frame_sink, injects a synthetic server reply, and asserts on the parsed
  # return — so both the query construction and the reply mapping are the module's
  # own, not a mirror.
  #
  # Fake placeholder numbers/jids only (repo PII rule).

  alias Amarula.Contacts
  alias Amarula.Protocol.Binary.{Node, NodeUtils}

  @phone "15550001234"
  @jid "15550001234@s.whatsapp.net"
  @lid "111111111111111@lid"

  setup do
    profile = :"contacts_#{System.unique_integer([:positive])}"
    dir = Path.join(System.tmp_dir!(), "amarula_contacts_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    {:ok, pid} =
      Amarula.Testing.start_offline(
        profile: profile,
        storage: {Amarula.Storage.File, root: dir}
      )

    on_exit(fn -> Amarula.stop(pid) end)
    {:ok, pid: pid}
  end

  # Run `fun` (a blocking Contacts call) in a Task, hand the outbound USync IQ to
  # `reply_fun` (frame id → reply node), inject the reply, and return the result.
  defp round_trip(pid, fun, reply_fun) do
    task = Task.async(fn -> fun.() end)
    iq = recv_frame()
    send(pid, {:inject_node, reply_fun.(iq)})
    Task.await(task, 2000)
  end

  defp recv_frame do
    receive do
      {:frame_out, %Node{tag: "iq"} = node} -> node
      {:frame_out, _other} -> recv_frame()
    after
      1000 -> flunk("timed out waiting for the outbound USync IQ")
    end
  end

  defp iq_id(iq), do: NodeUtils.get_attr(iq, "id")

  describe "on_whatsapp/2" do
    test "builds a contact USync (jid attr omitted) and maps the reply to presence", %{pid: pid} do
      result =
        round_trip(
          pid,
          fn -> Contacts.on_whatsapp(pid, [@phone]) end,
          fn iq ->
            # The REAL query the module put on the wire.
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

            contact_reply(iq_id(iq), @jid, "in")
          end
        )

      assert {:ok, [%{address: %Amarula.Address{kind: :pn, user: @phone}, exists: true}]} =
               result
    end

    test "a contact not on WhatsApp maps to exists: false", %{pid: pid} do
      assert {:ok, [%{exists: false}]} =
               round_trip(
                 pid,
                 fn -> Contacts.on_whatsapp(pid, @phone) end,
                 fn iq -> contact_reply(iq_id(iq), @jid, "out") end
               )
    end

    test "an error reply surfaces as {:error, node}", %{pid: pid} do
      assert {:error, %Node{}} =
               round_trip(
                 pid,
                 fn -> Contacts.on_whatsapp(pid, [@phone]) end,
                 fn iq -> error_reply(iq_id(iq)) end
               )
    end
  end

  describe "fetch_status/2" do
    test "builds a status USync by jid and maps the reply to %{status, set_at}", %{pid: pid} do
      result =
        round_trip(
          pid,
          fn -> Contacts.fetch_status(pid, [@jid]) end,
          fn iq ->
            usync = NodeUtils.get_binary_node_child(iq, "usync")
            query_node = NodeUtils.get_binary_node_child(usync, "query")
            assert Enum.map(query_node.content, & &1.tag) == ["status"]

            # Status lookups are by jid, not phone.
            list = NodeUtils.get_binary_node_child(usync, "list")
            [user] = list.content
            assert NodeUtils.get_attr(user, "jid") == @jid

            status_reply(iq_id(iq), @jid, "busy", 1_700_000_000)
          end
        )

      assert {:ok, [%{address: %Amarula.Address{kind: :pn}, status: "busy", set_at: set_at}]} =
               result

      assert %DateTime{} = set_at
    end

    test "a user with no visible status maps to status: nil", %{pid: pid} do
      assert {:ok, [%{status: nil, set_at: nil}]} =
               round_trip(
                 pid,
                 fn -> Contacts.fetch_status(pid, @jid) end,
                 fn iq -> contact_reply(iq_id(iq), @jid, "in") end
               )
    end
  end

  describe "resolve_lid/2" do
    test "runs a lid+contact USync, returns the pair, and persists the mapping", %{pid: pid} do
      result =
        round_trip(
          pid,
          fn -> Contacts.resolve_lid(pid, [@phone]) end,
          fn iq ->
            # resolve_lid needs BOTH protocols: :contact (the PN id) and :lid (the
            # LID); on_whatsapp's contact-only query can't establish a mapping.
            usync = NodeUtils.get_binary_node_child(iq, "usync")
            query_node = NodeUtils.get_binary_node_child(usync, "query")
            assert Enum.sort(Enum.map(query_node.content, & &1.tag)) == ["contact", "lid"]

            lid_reply(iq_id(iq), @jid, @lid)
          end
        )

      assert {:ok, [%{lid: %Amarula.Address{kind: :lid}, pn: %Amarula.Address{kind: :pn}}]} =
               result

      # The mapping landed in the store the send pipeline + lookups use: the local
      # (no server round-trip) reads now resolve both directions.
      assert %Amarula.Address{kind: :pn, user: @phone} = Contacts.pn_for_lid(pid, @lid)

      assert %Amarula.Address{kind: :lid, user: "111111111111111"} =
               Contacts.lid_for_pn(pid, @jid)
    end

    test "numbers with no LID in the reply are omitted (not on WhatsApp)", %{pid: pid} do
      assert {:ok, []} =
               round_trip(
                 pid,
                 fn -> Contacts.resolve_lid(pid, [@phone]) end,
                 fn iq -> contact_reply(iq_id(iq), @jid, "in") end
               )
    end
  end

  describe "pn_for_lid/2 and lid_for_pn/2 without a stored mapping" do
    test "return nil for an unmapped id", %{pid: pid} do
      assert Contacts.pn_for_lid(pid, "999999999999999@lid") == nil
      assert Contacts.lid_for_pn(pid, "15559999999@s.whatsapp.net") == nil
    end
  end

  # --- synthetic server replies (map attrs, stamped with the request's id) ---

  defp contact_reply(id, jid, type) do
    usync_reply(id, [
      %Node{
        tag: "user",
        attrs: %{"jid" => jid},
        content: [%Node{tag: "contact", attrs: %{"type" => type}, content: nil}]
      }
    ])
  end

  defp lid_reply(id, jid, lid) do
    usync_reply(id, [
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

  defp status_reply(id, jid, text, ts) do
    usync_reply(id, [
      %Node{
        tag: "user",
        attrs: %{"jid" => jid},
        content: [%Node{tag: "status", attrs: %{"t" => Integer.to_string(ts)}, content: text}]
      }
    ])
  end

  defp usync_reply(id, users) do
    %Node{
      tag: "iq",
      attrs: %{"type" => "result", "id" => id},
      content: [
        %Node{
          tag: "usync",
          attrs: %{},
          content: [%Node{tag: "list", attrs: %{}, content: users}]
        }
      ]
    }
  end

  defp error_reply(id) do
    %Node{
      tag: "iq",
      attrs: %{"type" => "error", "id" => id},
      content: [%Node{tag: "error", attrs: %{"code" => "403"}, content: nil}]
    }
  end
end
