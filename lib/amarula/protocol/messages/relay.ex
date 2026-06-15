defmodule Amarula.Protocol.Messages.Relay do
  @moduledoc """
  Build the outbound `<message>` stanza for a 1:1 send, ported from the
  single-device path of Baileys `relayMessage` (`src/Socket/messages-send.ts`).

  Shape (1:1, single device):

      <message id=msgId to=jid type="text" t=ts>
        <enc v="2" type="msg"|"pkmsg">ciphertext</enc>
        <device-identity>...</device-identity>   (only when type=pkmsg)
      </message>

  `device-identity` is required whenever any enc is a pkmsg so the recipient can
  verify our companion identity (encodeSignedDeviceIdentity, include sig key).
  """

  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Proto

  @doc """
  Build the message stanza.

    * `msg_id`     — the message id (also the WAMessageKey id)
    * `to`         — recipient JID
    * `enc_type`   — `:msg` or `:pkmsg`
    * `ciphertext` — Signal ciphertext bytes
    * `account`    — our `ADVSignedDeviceIdentity` (for device-identity on pkmsg)
    * `timestamp`  — unix seconds (defaults to now)
  """
  @spec build_message_stanza(String.t(), String.t(), :msg | :pkmsg, binary(), struct(), keyword()) ::
          Node.t()
  def build_message_stanza(msg_id, to, enc_type, ciphertext, account, opts \\ []) do
    ts = Keyword.get(opts, :timestamp, System.system_time(:second))
    enc = Node.create("enc", %{"v" => "2", "type" => Atom.to_string(enc_type)}, ciphertext)
    children = [enc] ++ maybe_device_identity(enc_type == :pkmsg, account)

    Node.create(
      "message",
      %{"id" => msg_id, "to" => to, "type" => "text", "t" => Integer.to_string(ts)},
      children
    )
  end

  @doc """
  Build a multi-device message stanza, ported from the fan-out path of Baileys
  `relayMessage` (the `<participants>` branch).

  Shape:

      <message id=msgId to=jid type="text" t=ts>
        <participants>
          <to jid=device1><enc v="2" type=...>ct1</enc></to>
          <to jid=device2><enc v="2" type=...>ct2</enc></to>
          ...
        </participants>
        <device-identity>...</device-identity>   (when any enc is pkmsg)
      </message>

    * `participants` — list of `{device_jid, enc_type, ciphertext}` tuples, one
      per recipient device (already encrypted by the caller).

  Returns `{:error, :no_participants}` when the list is empty (all encryptions
  failed upstream), matching Baileys' "All encryptions failed" guard.
  """
  @spec build_multi_device_stanza(
          String.t(),
          String.t(),
          [{String.t(), :msg | :pkmsg, binary()}],
          struct(),
          keyword()
        ) :: {:ok, Node.t()} | {:error, :no_participants}
  def build_multi_device_stanza(msg_id, to, participants, account, opts \\ [])

  def build_multi_device_stanza(_msg_id, _to, [], _account, _opts), do: {:error, :no_participants}

  def build_multi_device_stanza(msg_id, to, participants, account, opts) do
    participants_node =
      Node.create("participants", %{}, Enum.map(participants, &participant_to_node/1))

    children = [participants_node] ++ maybe_device_identity(any_pkmsg?(participants), account)

    # Attrs match a live Baileys 1:1 send (captured 2026-06-13): id, to (PN), type
    # ONLY — NO `t`. The `edit` attr is added only for delete/edit messages.
    # `:extra_attrs` (e.g. category/push_priority for a peer message) merge in.
    attrs =
      %{"id" => msg_id, "to" => to, "type" => "text"}
      |> put_edit(opts)
      |> Map.merge(Keyword.get(opts, :extra_attrs, %{}))

    stanza = Node.create("message", attrs, children)

    {:ok, stanza}
  end

  @doc """
  Build a group message stanza:

      <message id=msgId to=group type="text" t=ts>
        <enc v="2" type="skmsg">skmsg</enc>
        <participants>
          <to jid=device1><enc v="2" type="pkmsg">skdm1</enc></to>
          ...
        </participants>
        <device-identity>...</device-identity>   (when any SKDM enc is pkmsg)
      </message>

  The `skmsg` is the group ciphertext (sender-key encrypted, one for the whole
  group). `participants` are per-device SKDM `{jid, enc_type, ciphertext}` tuples
  so each member can rebuild our sender key. `{:error, :no_participants}` if the
  SKDM fan-out is empty.
  """
  @spec build_group_stanza(
          String.t(),
          String.t(),
          binary(),
          [{String.t(), :msg | :pkmsg, binary()}],
          struct(),
          keyword()
        ) :: {:ok, Node.t()} | {:error, :no_participants}
  def build_group_stanza(msg_id, to, skmsg, participants, account, opts \\ [])

  def build_group_stanza(_msg_id, _to, _skmsg, [], _account, _opts),
    do: {:error, :no_participants}

  def build_group_stanza(msg_id, to, skmsg, participants, account, opts) do
    ts = Keyword.get(opts, :timestamp, System.system_time(:second))

    skmsg_enc = Node.create("enc", %{"v" => "2", "type" => "skmsg"}, skmsg)

    participants_node =
      Node.create("participants", %{}, Enum.map(participants, &participant_to_node/1))

    children =
      [skmsg_enc, participants_node] ++ maybe_device_identity(any_pkmsg?(participants), account)

    attrs =
      put_edit(
        %{"id" => msg_id, "to" => to, "type" => "text", "t" => Integer.to_string(ts)},
        opts
      )

    stanza = Node.create("message", attrs, children)

    {:ok, stanza}
  end

  defp participant_to_node({jid, enc_type, ciphertext}) do
    enc = Node.create("enc", %{"v" => "2", "type" => Atom.to_string(enc_type)}, ciphertext)
    Node.create("to", %{"jid" => jid}, [enc])
  end

  defp any_pkmsg?(participants), do: Enum.any?(participants, &(elem(&1, 1) == :pkmsg))

  # Add the `edit` <message> attr (delete="7"/edit="1"/…) when present in opts.
  # The server needs it to apply a delete/edit instead of routing a normal msg.
  defp put_edit(attrs, opts) do
    case Keyword.get(opts, :edit) do
      nil -> attrs
      edit -> Map.put(attrs, "edit", edit)
    end
  end

  # A <device-identity> child is required whenever any enc is a pkmsg, so the
  # recipient can verify our companion identity. encodeSignedDeviceIdentity keeps
  # the accountSignatureKey.
  defp maybe_device_identity(false, _account), do: []

  defp maybe_device_identity(true, account) do
    [Node.create("device-identity", %{}, Proto.ADVSignedDeviceIdentity.encode(account))]
  end
end
