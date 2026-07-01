defmodule Amarula.Protocol.Signal.Group.SenderKeyName do
  @moduledoc """
  Represents a sender key name for group encryption.

  A sender key name uniquely identifies a sender key for a specific group and sender.
  It consists of a group ID and sender information (JID + device ID).
  """

  alias Amarula.Protocol.Binary.JID

  @type sender :: %{
          id: String.t(),
          device_id: non_neg_integer()
        }

  @type t :: %__MODULE__{
          group_id: String.t(),
          sender: sender()
        }

  defstruct group_id: "", sender: %{id: "", device_id: 0}

  @doc """
  Creates a new SenderKeyName.
  """
  @spec new(String.t(), String.t(), non_neg_integer()) :: t()
  def new(group_id, sender_id, device_id) do
    %__MODULE__{
      group_id: group_id,
      sender: %{id: sender_id, device_id: device_id}
    }
  end

  @whatsapp_domain 0

  @doc """
  Build a SenderKeyName from the group JID and author JID, mirroring Baileys
  jidToSignalSenderKeyName: the group JID is used AS-IS (full "...@g.us"
  string), the author becomes a signal protocol address (user, or
  "user_<domainType>" for non-WhatsApp domains like lid, plus device).

  Both the SKDM-store path and the skmsg-decrypt path MUST use this so the
  sender key is found under the same name.
  """
  @spec from_jids(String.t(), String.t()) :: t()
  def from_jids(group_jid, author_jid) do
    case JID.decode(author_jid) do
      %{user: user} = decoded ->
        dt = Map.get(decoded, :domain_type, @whatsapp_domain)
        device = Map.get(decoded, :device, 0) || 0
        sender_id = if dt == @whatsapp_domain, do: user, else: "#{user}_#{dt}"
        new(group_jid, sender_id, device)

      _ ->
        new(group_jid, author_jid, 0)
    end
  end

  @doc """
  Converts the SenderKeyName to a string representation.
  """
  @spec to_string_repr(t()) :: String.t()
  def to_string_repr(%__MODULE__{
        group_id: group_id,
        sender: %{id: sender_id, device_id: device_id}
      }) do
    "#{group_id}::#{sender_id}::#{device_id}"
  end
end
