defmodule Amarula.Protocol.Socket.RouterTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Socket.Router

  defp n(tag, attrs \\ %{}, children \\ []) do
    %Node{tag: tag, attrs: attrs, content: children}
  end

  defp child(tag), do: %Node{tag: tag, attrs: %{}, content: nil}

  test "pairing nodes" do
    assert Router.route(n("iq", %{"type" => "set"}, [child("pair-device")])) == :pair_device
    assert Router.route(n("iq", %{}, [child("pair-success")])) == :pair_success
  end

  test "auth + message + stream control" do
    assert Router.route(n("success")) == :auth_success
    assert Router.route(n("message")) == :message
    assert Router.route(n("stream:error")) == :stream_error
    assert Router.route(n("failure")) == :connection_failure
    assert Router.route(n("xmlstreamend")) == :xml_stream_end
  end

  test "ping is disambiguated by xmlns / direction" do
    assert Router.route(n("iq", %{"type" => "get", "xmlns" => "urn:xmpp:ping"})) == :server_ping
    assert Router.route(n("iq", %{}, [child("ping")])) == :ping_response
  end

  test "tracked iq results and errors both route to iq_response" do
    assert Router.route(n("iq", %{"type" => "result"})) == :iq_response
    assert Router.route(n("iq", %{"type" => "error"})) == :iq_response
  end

  test "ib variants" do
    assert Router.route(n("ib", %{}, [child("offline_preview")])) == :offline_preview
    assert Router.route(n("ib", %{}, [child("offline")])) == :offline_complete
    assert Router.route(n("ib", %{}, [child("edge_routing")])) == :edge_routing
    assert Router.route(n("ib", %{}, [child("dirty")])) == :dirty
    assert Router.route(n("ib", %{}, [child("thread_metadata")])) == :ignore
  end

  test "notifications, acks, receipts, calls" do
    assert Router.route(n("notification")) == :notification
    # A bare ack (or any non-message class) carries no send correlation.
    assert Router.route(n("ack")) == :ignore
    assert Router.route(n("ack", %{"class" => "receipt"})) == :ignore
    # Only a class="message" ack confirms a parked send.
    assert Router.route(n("ack", %{"class" => "message"})) == :message_ack
    assert Router.route(n("receipt", %{"type" => "retry"})) == :retry_receipt
    assert Router.route(n("receipt", %{"type" => "read"})) == :receipt_ack
    assert Router.route(n("receipt")) == :receipt_ack
    assert Router.route(n("call")) == :call_ack
  end

  test "presence + chatstate route to :presence" do
    assert Router.route(n("presence")) == :presence
    assert Router.route(n("chatstate", %{}, [child("composing")])) == :presence
  end

  test "anything unrecognised is :unhandled" do
    assert Router.route(n("iq", %{"type" => "set"}, [child("something-new")])) == :unhandled
  end
end
