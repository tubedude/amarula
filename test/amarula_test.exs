defmodule AmarulaTest do
  use ExUnit.Case, async: true
  doctest Amarula

  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Proto

  # A stand-in for a connection: it answers GenServer.call by recording the
  # request and replying, so we can assert the facade forwards the right message.
  # For {:group_op, iq, transform} it runs the transform against a canned reply
  # (set per-test via set_group_reply/2) so we can test the facade's reply transforms.
  defmodule StubConn do
    use GenServer

    def start_link(test_pid), do: GenServer.start_link(__MODULE__, %{test: test_pid, reply: nil})
    def set_group_reply(pid, reply), do: GenServer.call(pid, {:__set_group_reply, reply})

    def init(state), do: {:ok, state}

    def handle_call({:__set_group_reply, reply}, _from, state),
      do: {:reply, :ok, %{state | reply: reply}}

    def handle_call({:group_op, iq, transform}, _from, state) do
      send(state.test, {:got, {:group_op, iq}})
      {:reply, transform.(state.reply), state}
    end

    def handle_call(request, _from, state) do
      send(state.test, {:got, request})
      {:reply, reply_for(request), state}
    end

    defp reply_for(:get_connection_state), do: :connected
    defp reply_for(:disconnect), do: :ok
    # own_address/1 reads creds.me.id; a linked device carries a :29 suffix.
    defp reply_for(:get_auth_creds), do: %{me: %{id: "5511999999999:29@s.whatsapp.net"}}
    defp reply_for(_), do: {:ok, "MSGID"}
  end

  setup do
    {:ok, conn} = StubConn.start_link(self())
    {:ok, conn: conn}
  end

  test "send_text forwards {:send_text, jid, text, opts}", %{conn: conn} do
    assert {:ok, "MSGID"} = Amarula.send_text(conn, "x@s.whatsapp.net", "hi")
    assert_received {:got, {:send_text, "x@s.whatsapp.net", "hi", []}}
  end

  test "send_reaction builds a reaction and sends to the target's remoteJid", %{conn: conn} do
    key = %Proto.MessageKey{remoteJid: "x@s.whatsapp.net", id: "ABC"}
    assert {:ok, "MSGID"} = Amarula.send_reaction(conn, key, "👍")
    assert_received {:got, {:send_message, "x@s.whatsapp.net", msg}}
    assert msg.reactionMessage.text == "👍"
  end

  test "send_edit / send_revoke build the right protocol message", %{conn: conn} do
    key = %Proto.MessageKey{remoteJid: "x@s.whatsapp.net", id: "ABC"}

    Amarula.send_edit(conn, key, "v2")
    assert_received {:got, {:send_message, "x@s.whatsapp.net", edit}}
    assert edit.protocolMessage.type == :MESSAGE_EDIT

    Amarula.send_revoke(conn, key)
    assert_received {:got, {:send_message, "x@s.whatsapp.net", rev}}
    assert rev.protocolMessage.type == :REVOKE
  end

  test "send_media forwards {:send_media, jid, type, data, opts}", %{conn: conn} do
    Amarula.send_media(conn, "x@s.whatsapp.net", :document, <<1, 2, 3>>, title: "t")

    assert_received {:got,
                     {:send_media, "x@s.whatsapp.net", :document, <<1, 2, 3>>, [title: "t"]}}
  end

  test "connection_state and disconnect delegate", %{conn: conn} do
    assert Amarula.connection_state(conn) == :connected
    assert_received {:got, :get_connection_state}

    assert Amarula.disconnect(conn) == :ok
    assert_received {:got, :disconnect}
  end

  # --- group op reply transforms (the consumer error contract) ---

  defp error_iq(code, text) do
    {:error,
     %Node{
       tag: "iq",
       attrs: %{"type" => "error"},
       content: [%Node{tag: "error", attrs: %{"code" => code, "text" => text}, content: nil}]
     }}
  end

  test "a failed group op surfaces {:group_op_failed, code, text}", %{conn: conn} do
    StubConn.set_group_reply(conn, error_iq("403", "forbidden"))
    assert {:error, {:group_op_failed, "403", "forbidden"}} = Amarula.Group.leave(conn, "g@g.us")
    assert_received {:got, {:group_op, _iq}}
  end

  test "group_invite_code returns the parsed code on success", %{conn: conn} do
    reply =
      {:ok,
       %Node{
         tag: "iq",
         attrs: %{"type" => "result"},
         content: [%Node{tag: "invite", attrs: %{"code" => "ABC123"}, content: nil}]
       }}

    StubConn.set_group_reply(conn, reply)
    assert {:ok, "ABC123"} = Amarula.Group.invite_code(conn, "g@g.us")
  end

  test "group_create maps a result to an %Amarula.Group{}", %{conn: conn} do
    reply =
      {:ok,
       %Node{
         tag: "iq",
         attrs: %{"type" => "result"},
         content: [
           %Node{
             tag: "group",
             attrs: %{"id" => "120363000000000000@g.us", "subject" => "My Group"},
             content: []
           }
         ]
       }}

    StubConn.set_group_reply(conn, reply)
    assert {:ok, %Amarula.Group{subject: "My Group"}} = Amarula.Group.create(conn, "My Group", [])
  end

  test "a successful set-style group op returns :ok", %{conn: conn} do
    StubConn.set_group_reply(
      conn,
      {:ok, %Node{tag: "iq", attrs: %{"type" => "result"}, content: []}}
    )

    assert :ok = Amarula.Group.update_subject(conn, "g@g.us", "New Name")
  end

  # --- download_media dispatch ---

  test "download_media on a non-media Msg returns {:error, :not_media}" do
    msg = %Amarula.Msg{
      channel: Amarula.Address.parse("x@s.whatsapp.net"),
      type: :text,
      content: "hi",
      raw: %Proto.Message{conversation: "hi"}
    }

    assert {:error, :not_media} = Amarula.download_media(msg)
  end

  # --- own_address/1 (identity / device) ---

  test "own_address/1 returns our PN Address with the companion device", %{conn: conn} do
    addr = Amarula.own_address(conn)
    assert %Amarula.Address{user: "5511999999999", kind: :pn, device: 29} = addr
    assert_received {:got, :get_auth_creds}
  end

  test "own_address/1 always returns an Address: empty Address when no creds / no suffix" do
    # A stub whose creds vary, to exercise the no-suffix and pre-login branches.
    defmodule CredStub do
      use GenServer
      def start_link(me), do: GenServer.start_link(__MODULE__, me)
      def init(me), do: {:ok, me}
      def handle_call(:get_auth_creds, _from, me), do: {:reply, %{me: me}, me}
    end

    {:ok, primary} = CredStub.start_link(%{id: "5511999999999@s.whatsapp.net"})
    assert %Amarula.Address{device: nil, kind: :pn} = Amarula.own_address(primary)

    {:ok, pre_login} = CredStub.start_link(%{})
    assert Amarula.Address.empty?(Amarula.own_address(pre_login))
  end

  # --- convenience delegations forward the right tuple ---

  test "convenience sends forward the expected Socket message", %{conn: conn} do
    Amarula.set_presence(conn, :available)
    assert_received {:got, {:set_presence, :available}}

    Amarula.send_chatstate(conn, "x@s.whatsapp.net", :composing)
    assert_received {:got, {:send_chatstate, "x@s.whatsapp.net", :composing}}

    Amarula.subscribe_presence(conn, "x@s.whatsapp.net")
    assert_received {:got, {:presence_subscribe, "x@s.whatsapp.net"}}

    Amarula.mark_read(conn, "x@s.whatsapp.net", ["ID1"])
    assert_received {:got, {:mark_read, "x@s.whatsapp.net", ["ID1"], nil}}
  end
end
