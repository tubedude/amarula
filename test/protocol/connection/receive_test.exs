defmodule Amarula.Connection.ReceiveTest do
  @moduledoc "Pure unit tests for the receive-path ack/retry parsers — no socket, no state."
  use ExUnit.Case, async: true

  alias Amarula.Connection.Receive
  alias Amarula.Protocol.Binary.Node

  describe "ack_outcome/1" do
    test "no error attr → :ok" do
      assert Receive.ack_outcome(%Node{tag: "ack", attrs: %{"id" => "M1"}}) == :ok
    end

    test "error attr → {:error, {:send_rejected, code}}" do
      node = %Node{tag: "ack", attrs: %{"id" => "M1", "error" => "479"}}
      assert Receive.ack_outcome(node) == {:error, {:send_rejected, "479"}}
    end
  end

  describe "retry_targets/1" do
    test "participant defaults to from when absent" do
      node = %Node{tag: "receipt", attrs: %{"id" => "M1", "from" => "1@s.whatsapp.net"}}
      assert Receive.retry_targets(node) == {"M1", "1@s.whatsapp.net"}
    end

    test "explicit participant wins over from (group retry)" do
      node = %Node{
        tag: "receipt",
        attrs: %{"id" => "M1", "from" => "g@g.us", "participant" => "2@s.whatsapp.net"}
      }

      assert Receive.retry_targets(node) == {"M1", "2@s.whatsapp.net"}
    end

    test "missing id surfaces as nil for the caller to skip" do
      node = %Node{tag: "receipt", attrs: %{"from" => "1@s.whatsapp.net"}}
      assert {nil, "1@s.whatsapp.net"} = Receive.retry_targets(node)
    end
  end
end
