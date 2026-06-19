defmodule Amarula.Protocol.Signal.LIDMapping do
  @moduledoc """
  LID (Local ID) mapping types and utilities.

  LID mapping is used to convert between Phone Number (PN) JIDs and Local ID (LID) JIDs
  for WhatsApp's privacy features. This allows users to communicate without exposing
  their phone numbers.
  """

  @type t :: %__MODULE__{
          pn: String.t(),
          lid: String.t()
        }

  defstruct pn: nil, lid: nil

  @doc """
  Creates a new LID mapping.
  """
  @spec new(String.t(), String.t()) :: t()
  def new(pn, lid) do
    %__MODULE__{pn: pn, lid: lid}
  end

  @doc """
  Checks if a JID is a phone number user.
  """
  @spec pn_user?(String.t()) :: boolean()
  def pn_user?(jid) do
    String.ends_with?(jid, "@s.whatsapp.net") or String.ends_with?(jid, "@hosted")
  end

  @doc """
  Checks if a JID is a hosted phone number user.
  """
  @spec hosted_pn_user?(String.t()) :: boolean()
  def hosted_pn_user?(jid) do
    String.ends_with?(jid, "@hosted")
  end

  @doc """
  Checks if a JID is a LID user.
  """
  @spec lid_user?(String.t()) :: boolean()
  def lid_user?(jid) do
    String.ends_with?(jid, "@lid") or String.ends_with?(jid, "@hosted.lid")
  end

  @doc """
  Normalizes a JID to its user part.
  """
  @spec normalize_user(String.t()) :: String.t()
  def normalize_user(jid) do
    case String.split(jid, "@") do
      [user, _domain] -> user
      _ -> jid
    end
  end

  @doc """
  Decodes a JID into its components.
  """
  @spec decode_jid(String.t()) :: {:ok, map()} | {:error, String.t()}
  def decode_jid(jid) do
    with [user_part, domain] <- String.split(jid, "@"),
         [user | device_parts] <- String.split(user_part, ":"),
         {:ok, device} <- parse_device_parts(device_parts) do
      {:ok, %{user: user, device: device, domain: domain}}
    else
      _ -> {:error, "Invalid JID format: #{jid}"}
    end
  end

  defp parse_device_parts([]), do: {:ok, 0}

  defp parse_device_parts([device_str]) do
    case Integer.parse(device_str) do
      {device, ""} -> {:ok, device}
      _ -> :error
    end
  end

  defp parse_device_parts(_), do: :error

  @doc """
  Constructs a device-specific JID.
  """
  @spec construct_device_jid(String.t(), non_neg_integer(), String.t()) :: String.t()
  def construct_device_jid(user, device, domain) do
    if device == 0 do
      "#{user}@#{domain}"
    else
      "#{user}:#{device}@#{domain}"
    end
  end
end
