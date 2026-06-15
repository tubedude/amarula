defmodule AmarulaTest do
  use ExUnit.Case, async: true
  doctest Amarula

  alias Amarula.Protocol.Proto

  # A stand-in for a connection: it answers GenServer.call by recording the
  # request and replying, so we can assert the facade forwards the right message.
  defmodule StubConn do
    use GenServer

    def start_link(test_pid), do: GenServer.start_link(__MODULE__, test_pid)
    def init(test_pid), do: {:ok, test_pid}

    def handle_call(request, _from, test_pid) do
      send(test_pid, {:got, request})
      {:reply, reply_for(request), test_pid}
    end

    defp reply_for(:get_connection_state), do: :connected
    defp reply_for(:disconnect), do: :ok
    defp reply_for(_), do: {:ok, "MSGID"}
  end

  setup do
    {:ok, conn} = StubConn.start_link(self())
    {:ok, conn: conn}
  end

  test "send_text forwards {:send_text, jid, text}", %{conn: conn} do
    assert {:ok, "MSGID"} = Amarula.send_text(conn, "x@s.whatsapp.net", "hi")
    assert_received {:got, {:send_text, "x@s.whatsapp.net", "hi"}}
  end

  test "send_message forwards the proto message", %{conn: conn} do
    msg = %Proto.Message{conversation: "hi"}
    assert {:ok, "MSGID"} = Amarula.send_message(conn, "x@s.whatsapp.net", msg)
    assert_received {:got, {:send_message, "x@s.whatsapp.net", ^msg}}
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

  test "send_media forwards {:send_media, type, jid, data, opts}", %{conn: conn} do
    Amarula.send_media(conn, :document, "x@s.whatsapp.net", <<1, 2, 3>>, title: "t")

    assert_received {:got,
                     {:send_media, :document, "x@s.whatsapp.net", <<1, 2, 3>>, [title: "t"]}}
  end

  test "connection_state and disconnect delegate", %{conn: conn} do
    assert Amarula.connection_state(conn) == :connected
    assert_received {:got, :get_connection_state}

    assert Amarula.disconnect(conn) == :ok
    assert_received {:got, :disconnect}
  end
end
