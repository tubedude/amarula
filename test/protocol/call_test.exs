defmodule Amarula.Protocol.CallTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Call

  defp call_node(attrs, child) do
    %Node{tag: "call", attrs: attrs, content: [child]}
  end

  describe "parse/1" do
    test "an offer is an incoming ringing call" do
      node =
        call_node(
          %{"from" => "5511999@s.whatsapp.net", "t" => "1700000000"},
          %Node{
            tag: "offer",
            attrs: %{"call-id" => "CALL1", "call-creator" => "5511999@s.whatsapp.net"},
            content: [%Node{tag: "audio", attrs: %{}, content: nil}]
          }
        )

      assert {:ok, call} = Call.parse(node)
      assert call.status == :offer
      assert call.id == "CALL1"
      assert call.timestamp == 1_700_000_000
      assert call.chat == Amarula.Address.pn("5511999")
      assert call.from == Amarula.Address.pn("5511999")
      refute call.video?
      refute call.group?
      refute call.offline
    end

    test "an offer with a <video> child is a video call" do
      node =
        call_node(%{"from" => "5511999@s.whatsapp.net"}, %Node{
          tag: "offer",
          attrs: %{"call-id" => "CALL2", "call-creator" => "5511999@s.whatsapp.net"},
          content: [%Node{tag: "video", attrs: %{}, content: nil}]
        })

      assert {:ok, %{video?: true, status: :offer}} = Call.parse(node)
    end

    test "terminate with reason=timeout is :timeout (unanswered)" do
      node =
        call_node(%{"from" => "5511999@s.whatsapp.net"}, %Node{
          tag: "terminate",
          attrs: %{"call-id" => "CALL1", "reason" => "timeout"},
          content: nil
        })

      assert {:ok, %{status: :timeout, id: "CALL1"}} = Call.parse(node)
    end

    test "terminate without a timeout reason is :terminate" do
      node =
        call_node(%{"from" => "5511999@s.whatsapp.net"}, %Node{
          tag: "terminate",
          attrs: %{"call-id" => "CALL1"},
          content: nil
        })

      assert {:ok, %{status: :terminate}} = Call.parse(node)
    end

    test "reject and accept map to their statuses" do
      reject =
        call_node(%{"from" => "5511999@s.whatsapp.net"}, %Node{
          tag: "reject",
          attrs: %{"call-id" => "C"},
          content: nil
        })

      accept =
        call_node(%{"from" => "5511999@s.whatsapp.net"}, %Node{
          tag: "accept",
          attrs: %{"call-id" => "C"},
          content: nil
        })

      assert {:ok, %{status: :reject}} = Call.parse(reject)
      assert {:ok, %{status: :accept}} = Call.parse(accept)
    end

    test "an unknown in-progress tag is :ringing" do
      node =
        call_node(%{"from" => "5511999@s.whatsapp.net"}, %Node{
          tag: "preaccept",
          attrs: %{"call-id" => "C"},
          content: nil
        })

      assert {:ok, %{status: :ringing}} = Call.parse(node)
    end

    test "a group call carries group? and group_jid" do
      node =
        call_node(%{"from" => "123-456@g.us"}, %Node{
          tag: "offer",
          attrs: %{
            "call-id" => "G1",
            "call-creator" => "5511999@s.whatsapp.net",
            "group-jid" => "123-456@g.us"
          },
          content: nil
        })

      assert {:ok, call} = Call.parse(node)
      assert call.group?
      assert call.group_jid == Amarula.Address.group("123-456")
    end

    test "an offline-delivered call is flagged" do
      node =
        call_node(%{"from" => "5511999@s.whatsapp.net", "offline" => "0"}, %Node{
          tag: "offer",
          attrs: %{"call-id" => "C", "call-creator" => "5511999@s.whatsapp.net"},
          content: nil
        })

      assert {:ok, %{offline: true}} = Call.parse(node)
    end

    test "a call with no info child is invalid" do
      assert {:error, :invalid} = Call.parse(%Node{tag: "call", attrs: %{}, content: []})
      assert {:error, :invalid} = Call.parse(%Node{tag: "call", attrs: %{}, content: nil})
    end

    test "a non-call node is invalid" do
      assert {:error, :invalid} = Call.parse(%Node{tag: "message", attrs: %{}, content: nil})
    end
  end
end
