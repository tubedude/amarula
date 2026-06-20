defmodule Amarula.Connection.Pairing do
  @moduledoc """
  Pure pairing builders for `Amarula.Connection` — the node-building and
  creds-transform parts of the QR/multi-device handshake.

  The orchestrating handlers (`handle_pair_device`, `handle_pair_success`,
  `emit_next_qr`) stay on `Connection`: they send frames, run timers, persist
  creds, and emit events. What lives here is pure and testable directly — the
  two reply IQ nodes, the QR-ref extraction, and the post-pairing creds merge.
  """

  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Crypto.Constants

  @doc "The `<iq type=result>` ack for a received pair-device IQ."
  @spec pair_device_ack_node(String.t()) :: Node.t()
  def pair_device_ack_node(msg_id) do
    %Node{
      tag: "iq",
      attrs: [
        {"to", "@s.whatsapp.net"},
        {"type", "result"},
        {"id", msg_id}
      ],
      content: nil
    }
  end

  @doc """
  Extract the QR `ref` payloads from a pair-device IQ node, in order. Returns
  `[]` when the `<pair-device>` wrapper or its `<ref>` children are absent.
  """
  @spec qr_refs(Node.t()) :: [binary()]
  def qr_refs(node) do
    with pair_device_node when not is_nil(pair_device_node) <-
           NodeUtils.get_binary_node_child(node, "pair-device"),
         [_ | _] = ref_nodes <-
           NodeUtils.get_binary_node_children(pair_device_node, "ref") do
      Enum.map(ref_nodes, & &1.content)
    else
      _ -> []
    end
  end

  @doc "The `<iq><pair-device-sign>` reply counter-signing the device identity."
  @spec pair_device_sign_reply(String.t(), integer(), binary()) :: Node.t()
  def pair_device_sign_reply(msg_id, key_index, account_enc) do
    %Node{
      tag: "iq",
      attrs: %{
        "to" => Constants.s_whatsapp_net(),
        "type" => "result",
        "id" => msg_id
      },
      content: [
        %Node{
          tag: "pair-device-sign",
          attrs: %{},
          content: [
            %Node{
              tag: "device-identity",
              attrs: %{"key-index" => to_string(key_index)},
              content: account_enc
            }
          ]
        }
      ]
    }
  end

  @doc """
  Merge the paired-device fields into creds. `me.name` defaults to "~" (Baileys)
  when there's no business name — presence-available requires a non-nil me.name.
  """
  @spec update_credentials_after_pairing(
          map(),
          term(),
          String.t(),
          String.t(),
          term(),
          term(),
          term()
        ) ::
          map()
  def update_credentials_after_pairing(
        creds,
        account,
        jid,
        lid,
        biz_name,
        platform,
        signal_identity
      ) do
    creds
    |> Map.put(:account, account)
    |> Map.put(:me, %{id: jid, name: biz_name || "~", lid: lid})
    |> Map.put(:platform, platform)
    |> Map.update(:signal_identities, [signal_identity], fn identities ->
      [signal_identity | identities || []]
    end)
  end
end
