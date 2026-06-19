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

  @doc """
  Parses a string representation back to a SenderKeyName.
  """
  @spec from_string(String.t()) :: {:ok, t()} | {:error, String.t()}
  def from_string(string) when is_binary(string) do
    case String.split(string, "::") do
      [group_id, sender_id, device_id_str] ->
        case Integer.parse(device_id_str) do
          {device_id, ""} ->
            {:ok, new(group_id, sender_id, device_id)}

          _ ->
            {:error, "Invalid device ID: #{device_id_str}"}
        end

      _ ->
        {:error, "Invalid SenderKeyName format: #{string}"}
    end
  end

  @doc """
  Generates a hash code for the SenderKeyName.
  """
  @spec hash_code(t()) :: integer()
  def hash_code(%__MODULE__{} = sender_key_name) do
    string_repr = to_string_repr(sender_key_name)
    hash_string(string_repr)
  end

  @doc """
  Checks if two SenderKeyNames are equal.
  """
  @spec equal?(t(), t()) :: boolean()
  def equal?(%__MODULE__{group_id: g1, sender: s1}, %__MODULE__{group_id: g2, sender: s2}) do
    g1 == g2 and s1.id == s2.id and s1.device_id == s2.device_id
  end

  # Private helper functions

  @spec hash_string(String.t()) :: integer()
  defp hash_string(string) do
    # Java-style hash code implementation
    string
    |> String.to_charlist()
    |> Enum.reduce(0, fn char, hash ->
      hash = hash * 31 + char
      # Keep within 32-bit signed integer range
      if hash > 0x7FFFFFFF do
        hash - 0x100000000
      else
        hash
      end
    end)
  end
end
