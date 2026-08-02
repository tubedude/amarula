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

  describe "message gating on unmodelled chat kinds (#50)" do
    test "chats we model route as :message" do
      for from <- ["5511@s.whatsapp.net", "5511@c.us", "5511@lid", "120@g.us"] do
        assert Router.route(n("message", %{"from" => from})) == :message,
               "expected #{from} to route as :message"
      end
    end

    test "chats we do not model yet are declined, not built into a %Msg{}" do
      for from <- ["status@broadcast", "x@newsletter", "5511@hosted", "5511@hosted.lid"] do
        assert Router.route(n("message", %{"from" => from})) == :unsupported_message,
               "expected #{from} to be declined"
      end
    end

    test "a device suffix does not change the verdict" do
      assert Router.route(n("message", %{"from" => "5511:3@s.whatsapp.net"})) == :message
      assert Router.route(n("message", %{"from" => "5511:3@hosted"})) == :unsupported_message
    end

    # The gate keys on an unmodelled SERVER, not on "failed to parse" — server-sent
    # messages have no user part and must keep flowing.
    test "a missing or bare-server `from` still routes as :message" do
      assert Router.route(n("message")) == :message
      assert Router.route(n("message", %{"from" => "s.whatsapp.net"})) == :message
      assert Router.route(n("message", %{"from" => ""})) == :message
    end
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
