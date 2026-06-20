defmodule Amarula.Connection.SendOpsTest do
  @moduledoc """
  Pure unit tests for the send-path builders — the payoff of extracting them from
  the GenServer: each is exercised without a socket, a process, or `state`.
  """
  use ExUnit.Case, async: true

  alias Amarula.Connection.SendOps
  alias Amarula.Protocol.Proto

  describe "text/2 and message/2" do
    test "text wraps the body and uses the default reply shape" do
      {target, payload, shape} = SendOps.text("123@s.whatsapp.net", "hi")

      assert target == "123@s.whatsapp.net"
      assert payload == %{text: "hi"}
      assert shape.(:ok, "MID") == {:ok, "MID"}
    end

    test "plain text keeps the lightweight %{text:} shorthand (no context)" do
      {_t, payload, _s} = SendOps.text("123@s.whatsapp.net", "hi", [])
      assert payload == %{text: "hi"}
    end

    test "a reply/mention builds the full proto payload (extendedTextMessage)" do
      {_t, %{message: message}, _s} =
        SendOps.text("123@s.whatsapp.net", "hi", mentions: ["2@s.whatsapp.net"])

      assert message.extendedTextMessage.contextInfo.mentionedJid == ["2@s.whatsapp.net"]
    end

    test "message passes a pre-built proto through untouched" do
      msg = %Proto.Message{conversation: "x"}
      {target, payload, _shape} = SendOps.message("g@g.us", msg)

      assert target == "g@g.us"
      assert payload == %{message: msg}
    end

    test "media wraps a ready message with the default shape" do
      msg = %Proto.Message{conversation: "img"}
      {target, payload, shape} = SendOps.media("123@s.whatsapp.net", msg)

      assert target == "123@s.whatsapp.net"
      assert payload == %{message: msg}
      assert shape.(:ok, "MID") == {:ok, "MID"}
    end
  end

  describe "poll/4" do
    test "carries the secret into the success reply, defers other results" do
      {target, %{message: message}, shape} =
        SendOps.poll("123@s.whatsapp.net", "Q", ["a", "b"], [])

      assert target == "123@s.whatsapp.net"
      assert %Proto.Message{} = message

      # :ok → {:ok, id, secret}; the secret is a non-empty binary.
      assert {:ok, "MID", secret} = shape.(:ok, "MID")
      assert is_binary(secret) and byte_size(secret) > 0

      # Non-:ok results fall through to the default shaping.
      assert shape.({:error, :boom}, "MID") == {:error, :boom}
    end
  end

  describe "request_resend/2 and fetch_history/4" do
    setup do
      %{key: %Proto.MessageKey{remoteJid: "123@s.whatsapp.net", id: "ORIG"}}
    end

    test "resend targets me_id with the peer/high-force stanza attrs", %{key: key} do
      {target, payload, shape} = SendOps.request_resend("me@s.whatsapp.net", key)

      assert target == "me@s.whatsapp.net"
      assert payload.stanza_attrs == %{"category" => "peer", "push_priority" => "high_force"}
      assert %Proto.Message{} = payload.message
      assert shape.(:ok, "MID") == {:ok, "MID"}
    end

    test "fetch_history targets me_id with the peer/high-force stanza attrs", %{key: key} do
      {target, payload, _shape} =
        SendOps.fetch_history("me@s.whatsapp.net", key, 1_700_000_000, 50)

      assert target == "me@s.whatsapp.net"
      assert payload.stanza_attrs == %{"category" => "peer", "push_priority" => "high_force"}
      assert %Proto.Message{} = payload.message
    end
  end

  describe "default_send_reply/2" do
    test "maps pipe results to caller replies" do
      assert SendOps.default_send_reply(:ok, "MID") == {:ok, "MID"}
      assert SendOps.default_send_reply({:error, :x}, "MID") == {:error, :x}
      assert SendOps.default_send_reply({:halted, :y}, "MID") == {:error, {:halted, :y}}
    end
  end
end
