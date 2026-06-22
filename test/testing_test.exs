defmodule Amarula.TestingTest do
  @moduledoc """
  Tests for `Amarula.Testing` — the consumer-facing test-support API. Confirms
  that `start_offline/1` + `deliver_*` push a synthetic inbound message all the way
  to the consumer's `parent_pid` as a real `%Amarula.Msg{}`, with no network.
  """
  # async: false — starts real (offline) connections on the shared, app-global
  # ConnectionsSupervisor + ProfileRegistry; see Amarula.ConnectionTest. Running
  # concurrently with other real-connection tests causes a rare cross-test flake.
  use ExUnit.Case, async: false

  alias Amarula.Protocol.Proto

  # Obviously-fake placeholder JID — not a real number.
  @peer "10000000001@s.whatsapp.net"

  setup do
    # Unique profile per test (one connection per profile) so tests run async.
    profile = :"testing_#{System.unique_integer([:positive])}"
    {:ok, conn} = Amarula.Testing.start_offline(profile: profile)
    on_exit(fn -> if Process.alive?(conn), do: Amarula.stop(conn) end)
    {:ok, conn: conn}
  end

  test "deliver_text reaches the consumer as a text Msg", %{conn: conn} do
    Amarula.Testing.deliver_text(conn, from: @peer, text: "hello", id: "MSG1")

    assert_receive {:amarula, :messages_upsert, %{id: "MSG1", messages: [msg]}}
    assert %Amarula.Msg{type: :text, content: "hello"} = msg
    assert msg.channel.user == "10000000001"
  end

  test "deliver builds the Msg via the real classify pipeline (media)", %{conn: conn} do
    proto = %Proto.Message{
      imageMessage: %Proto.Message.ImageMessage{caption: "look"}
    }

    Amarula.Testing.deliver(conn, proto, from: @peer)

    assert_receive {:amarula, :messages_upsert, %{messages: [msg]}}
    assert %Amarula.Msg{type: :media, content: %{kind: :image}} = msg
    assert msg.content.media.caption == "look"
  end

  test "pushname rides on the stanza notify attr", %{conn: conn} do
    Amarula.Testing.deliver_text(conn, from: @peer, text: "hi", notify: "Alice")

    assert_receive {:amarula, :messages_upsert, %{messages: [%Amarula.Msg{pushname: "Alice"}]}}
  end

  test "a bare protocolMessage goes to :protocol_update, not :messages_upsert", %{conn: conn} do
    proto = %Proto.Message{
      protocolMessage: %Proto.Message.ProtocolMessage{type: :PEER_DATA_OPERATION_REQUEST_MESSAGE}
    }

    Amarula.Testing.deliver(conn, proto, from: @peer)

    # It surfaces on its own event for consumers who want it...
    assert_receive {:amarula, :protocol_update, %{messages: [%Amarula.Msg{type: :protocol}]}}
    # ...and never pollutes the real-message stream.
    refute_received {:amarula, :messages_upsert, _}
  end

  test "no network: outbound frames go to the sink, not a socket", %{conn: conn} do
    # The only outbound frame for an inbound message is the delivery receipt.
    Amarula.Testing.deliver_text(conn, from: @peer, text: "hi")

    assert_receive {:amarula, :messages_upsert, _}
    assert_receive {:frame_out, %Amarula.Protocol.Binary.Node{tag: "receipt"}}
  end

  test "a random id is generated when none is given", %{conn: conn} do
    Amarula.Testing.deliver_text(conn, from: @peer, text: "hi")

    assert_receive {:amarula, :messages_upsert, %{id: id}}
    assert is_binary(id)
  end

  test "in sandbox mode a reply send short-circuits to {:ok, id} with no frame", %{conn: conn} do
    # The bot's reply: a real send_text call. In sandbox mode it must succeed
    # without running the encrypt/relay pipeline (which would block on USync).
    assert {:ok, msg_id} = Amarula.send_text(conn, @peer, "pong")
    assert is_binary(msg_id)

    # No message frame leaves the process (the sink would receive {:frame_out, _}).
    refute_receive {:frame_out, %Amarula.Protocol.Binary.Node{tag: "message"}}
  end

  test "full receive -> reply loop runs against the sandbox", %{conn: conn} do
    Amarula.Testing.deliver_text(conn, from: @peer, text: "ping")

    assert_receive {:amarula, :messages_upsert, %{messages: [%Amarula.Msg{channel: chan}]}}

    assert {:ok, _id} = Amarula.send_text(conn, Amarula.Address.to_jid!(chan), "pong")
  end
end
