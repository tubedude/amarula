defmodule Amarula.Protocol.Binary.JID do
  @moduledoc """
  JID (Jabber ID) utilities for WhatsApp protocol.
  Ported from src/WABinary/jid-utils.ts

  This module provides functions for encoding, decoding, and manipulating
  WhatsApp JIDs (Jabber IDs) with support for devices, agents, and different
  server types.
  """

  # Constants from TypeScript
  @s_whatsapp_net "@s.whatsapp.net"
  @official_biz_jid "16505361212@c.us"
  @server_jid "server@c.us"
  @psa_wid "0@c.us"
  @stories_jid "status@broadcast"
  @meta_ai_jid "13135550002@c.us"

  # Domain types
  @whatsapp_domain 0
  @lid_domain 1
  @hosted_domain 128
  @hosted_lid_domain 129

  # Server types (for reference)
  # ["c.us", "g.us", "broadcast", "s.whatsapp.net", "call", "lid",
  #  "newsletter", "bot", "hosted", "hosted.lid"]

  # Bot regex pattern from TypeScript
  @bot_regex ~r/^1313555\d{4}$|^131655500\d{2}$/

  @doc """
  Encodes a JID from its components.

  ## Parameters
  - `user`: The user identifier (string, number, or nil)
  - `server`: The server part of the JID (optional, defaults to "s.whatsapp.net")
  - `device`: Optional device number
  - `agent`: Optional agent number

  ## Examples

      iex> JID.encode(%{user: "1234", server: "s.whatsapp.net"})
      "1234@s.whatsapp.net"

      iex> JID.encode(%{user: "1234", device: 0, server: "s.whatsapp.net"})
      "1234:0@s.whatsapp.net"

      iex> JID.encode(%{user: "1234", agent: 1, server: "s.whatsapp.net"})
      "1234_1@s.whatsapp.net"
  """
  @spec encode(map()) :: binary()
  def encode(%{user: user, server: server, device: device, agent: agent})
      when not is_nil(device) and not is_nil(agent) do
    user_str = user_to_string(user)
    agent_str = "_#{agent}"
    # device 0 → no suffix (Baileys jidEncode `!!device`)
    device_str = if device == 0, do: "", else: ":#{device}"
    "#{user_str}#{agent_str}#{device_str}@#{server}"
  end

  # Device 0 (and nil) emit NO `:device` suffix — matches Baileys jidEncode
  # (`!!device ? :device : ''`). A device-suffixed `:0` jid is malformed for the
  # server (e.g. prekey-bundle fetches by `user:0@...` are silently ignored).
  def encode(%{user: user, server: server, device: 0}) do
    encode(%{user: user, server: server})
  end

  def encode(%{user: user, server: server, device: device}) when not is_nil(device) do
    user_str = user_to_string(user)
    device_str = ":#{device}"
    "#{user_str}#{device_str}@#{server}"
  end

  def encode(%{user: user, server: server, agent: agent}) when not is_nil(agent) do
    user_str = user_to_string(user)
    agent_str = "_#{agent}"
    "#{user_str}#{agent_str}@#{server}"
  end

  def encode(%{user: user, server: server}) do
    user_str = user_to_string(user)
    "#{user_str}@#{server}"
  end

  def encode(%{user: user}) do
    user_str = user_to_string(user)
    "#{user_str}@s.whatsapp.net"
  end

  @doc """
  Decodes a JID string into its components.

  ## Parameters
  - `jid`: The JID string to decode

  ## Returns
  A map with keys: `:user`, `:server`, `:device` (optional), `:domain_type`

  ## Examples

      iex> JID.decode("1234@s.whatsapp.net")
      %{user: "1234", server: "s.whatsapp.net", domain_type: 0}

      iex> JID.decode("1234:0@s.whatsapp.net")
      %{user: "1234", device: 0, server: "s.whatsapp.net", domain_type: 0}
  """
  @spec decode(binary() | nil) :: map() | nil
  def decode(jid) when is_binary(jid) do
    case String.split(jid, "@", parts: 2) do
      [user_part, server] ->
        decode_user_part(user_part, server)

      _ ->
        nil
    end
  end

  def decode(_), do: nil

  @doc """
  Checks if a JID represents a user (PN user).
  """
  @spec jid_user?(binary() | nil) :: boolean()
  def jid_user?(jid) when is_binary(jid) do
    String.ends_with?(jid, "@s.whatsapp.net") or
      String.ends_with?(jid, "@lid") or
      String.ends_with?(jid, "@hosted") or
      String.ends_with?(jid, "@hosted.lid")
  end

  def jid_user?(_), do: false

  @doc """
  Checks if a JID represents a group.
  """
  @spec jid_group?(binary() | nil) :: boolean()
  def jid_group?(jid) when is_binary(jid), do: String.ends_with?(jid, "@g.us")
  def jid_group?(_), do: false

  @doc """
  Checks if a JID represents a group.
  This is an alias for jid_group?/1 for compatibility with the messages module.
  """
  @spec group?(binary() | nil) :: boolean()
  def group?(jid), do: jid_group?(jid)

  @doc """
  Checks if a JID represents a LID user.
  """
  @spec lid_user?(binary() | nil) :: boolean()
  def lid_user?(jid) when is_binary(jid), do: String.ends_with?(jid, "@lid")
  def lid_user?(_), do: false

  @doc """
  Checks if a JID represents a broadcast.
  """
  @spec jid_broadcast?(binary() | nil) :: boolean()
  def jid_broadcast?(jid) when is_binary(jid), do: String.ends_with?(jid, "@broadcast")
  def jid_broadcast?(_), do: false

  @doc """
  Checks if a JID represents a bot.
  """
  @spec jid_bot?(binary() | nil) :: boolean()
  def jid_bot?(jid) when is_binary(jid) do
    with [user, _] <- String.split(jid, "@", parts: 2),
         true <- Regex.match?(@bot_regex, user),
         true <- String.ends_with?(jid, "@c.us") do
      true
    else
      _ -> false
    end
  end

  def jid_bot?(_), do: false

  @doc """
  Checks if a JID represents a newsletter.
  """
  @spec jid_newsletter?(binary() | nil) :: boolean()
  def jid_newsletter?(jid) when is_binary(jid), do: String.ends_with?(jid, "@newsletter")
  def jid_newsletter?(_), do: false

  @doc """
  Checks if a JID represents a hosted PN user.
  """
  @spec hosted_pn_user?(binary() | nil) :: boolean()
  def hosted_pn_user?(jid) when is_binary(jid), do: String.ends_with?(jid, "@hosted")
  def hosted_pn_user?(_), do: false

  @doc """
  Checks if a JID represents a hosted LID user.
  """
  @spec hosted_lid_user?(binary() | nil) :: boolean()
  def hosted_lid_user?(jid) when is_binary(jid), do: String.ends_with?(jid, "@hosted.lid")
  def hosted_lid_user?(_), do: false

  @doc """
  Checks if a JID is the status broadcast.
  """
  @spec jid_status_broadcast?(binary()) :: boolean()
  def jid_status_broadcast?(jid), do: jid == "status@broadcast"

  @doc """
  Checks if a JID represents Meta AI.
  """
  @spec jid_meta_ai?(binary() | nil) :: boolean()
  def jid_meta_ai?(jid) when is_binary(jid), do: String.ends_with?(jid, "@bot")
  def jid_meta_ai?(_), do: false

  @doc """
  Normalizes a JID to user format, converting c.us to s.whatsapp.net.
  """
  @spec jid_normalized_user(binary() | nil) :: binary()
  def jid_normalized_user(jid) do
    case decode(jid) do
      %{user: user, server: server} ->
        normalized_server = if server == "c.us", do: "s.whatsapp.net", else: server
        encode(%{user: user, server: normalized_server})

      _ ->
        ""
    end
  end

  @doc """
  Compares two JIDs to see if they represent the same user.
  """
  @spec are_jids_same_user?(binary() | nil, binary() | nil) :: boolean()
  def are_jids_same_user?(jid1, jid2) do
    case {decode(jid1), decode(jid2)} do
      {%{user: u}, %{user: u}} -> true
      _ -> false
    end
  end

  @doc """
  Transfers device from one JID to another.
  """
  @spec transfer_device(binary(), binary()) :: binary()
  def transfer_device(from_jid, to_jid) do
    from_decoded = decode(from_jid)
    device_id = Map.get(from_decoded || %{}, :device, 0)
    to_decoded = decode(to_jid)

    if to_decoded do
      # Always include device, even if it's 0
      encode(%{
        user: to_decoded.user,
        server: to_decoded.server,
        device: device_id
      })
    else
      ""
    end
  end

  # Constants
  @doc "Returns the S_WHATSAPP_NET constant"
  @spec s_whatsapp_net() :: binary()
  def s_whatsapp_net, do: @s_whatsapp_net

  @doc "Returns the OFFICIAL_BIZ_JID constant"
  @spec official_biz_jid() :: binary()
  def official_biz_jid, do: @official_biz_jid

  @doc "Returns the SERVER_JID constant"
  @spec server_jid() :: binary()
  def server_jid, do: @server_jid

  @doc "Returns the PSA_WID constant"
  @spec psa_wid() :: binary()
  def psa_wid, do: @psa_wid

  @doc "Returns the STORIES_JID constant"
  @spec stories_jid() :: binary()
  def stories_jid, do: @stories_jid

  @doc "Returns the META_AI_JID constant"
  @spec meta_ai_jid() :: binary()
  def meta_ai_jid, do: @meta_ai_jid

  # Private functions

  defp user_to_string(nil), do: ""
  defp user_to_string(user) when is_integer(user), do: to_string(user)
  defp user_to_string(user) when is_binary(user), do: user

  defp decode_user_part(user_part, server) do
    case String.split(user_part, ":", parts: 2) do
      [user_agent, device] ->
        decode_user_agent(user_agent, server, String.to_integer(device))

      [user_agent] ->
        decode_user_agent(user_agent, server, nil)
    end
  end

  defp decode_user_agent(user_agent, server, device) do
    case String.split(user_agent, "_", parts: 2) do
      [user, agent] ->
        domain_type = get_domain_type(server, String.to_integer(agent))
        build_result(user, server, device, domain_type)

      [user] ->
        domain_type = get_domain_type(server, nil)
        build_result(user, server, device, domain_type)
    end
  end

  defp build_result(user, server, nil, domain_type) do
    %{user: user, server: server, domain_type: domain_type}
  end

  defp build_result(user, server, device, domain_type) do
    %{user: user, server: server, device: device, domain_type: domain_type}
  end

  defp get_domain_type("lid", _), do: @lid_domain
  defp get_domain_type("hosted", _), do: @hosted_domain
  defp get_domain_type("hosted.lid", _), do: @hosted_lid_domain
  defp get_domain_type(_, agent) when not is_nil(agent), do: agent
  defp get_domain_type(_, _), do: @whatsapp_domain
end
