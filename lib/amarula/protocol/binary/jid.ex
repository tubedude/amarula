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

  Both `device` and `agent` follow Baileys' `!!x` rule — a `nil` or `0` value
  drops that segment (server defaults to `s.whatsapp.net`).

  ## Examples

      iex> JID.encode(%{user: "1234", server: "s.whatsapp.net"})
      "1234@s.whatsapp.net"

      iex> JID.encode(%{user: "1234", device: 2, server: "s.whatsapp.net"})
      "1234:2@s.whatsapp.net"

      iex> JID.encode(%{user: "1234", agent: 1, server: "s.whatsapp.net"})
      "1234_1@s.whatsapp.net"
  """
  @spec encode(map()) :: binary()
  def encode(%{user: user} = jid) do
    server = Map.get(jid, :server, "s.whatsapp.net")
    "#{user_to_string(user)}#{suffix("_", jid[:agent])}#{suffix(":", jid[:device])}@#{server}"
  end

  defp suffix(_sep, x) when x in [nil, 0], do: ""
  defp suffix(sep, x), do: "#{sep}#{x}"

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

  # nil-safe String.ends_with? — a non-binary jid never matches a suffix. Lets the
  # suffix predicates below stay one-liners with no `_ -> false` head or guard.
  defp ends?(jid, suffix) when is_binary(jid), do: String.ends_with?(jid, suffix)
  defp ends?(_, _), do: false

  @doc """
  Checks if a JID represents a user (PN user).
  """
  @spec jid_user?(binary() | nil) :: boolean()
  def jid_user?(jid) do
    ends?(jid, "@s.whatsapp.net") or ends?(jid, "@lid") or
      ends?(jid, "@hosted") or ends?(jid, "@hosted.lid")
  end

  @doc """
  Checks if a JID represents a group.
  """
  @spec jid_group?(binary() | nil) :: boolean()
  def jid_group?(jid), do: ends?(jid, "@g.us")

  @doc """
  Checks if a JID represents a LID user.
  """
  @spec lid_user?(binary() | nil) :: boolean()
  def lid_user?(jid), do: ends?(jid, "@lid")

  @doc """
  Checks if a JID represents a broadcast.
  """
  @spec jid_broadcast?(binary() | nil) :: boolean()
  def jid_broadcast?(jid), do: ends?(jid, "@broadcast")

  @doc """
  Checks if a JID represents a bot.
  """
  @spec jid_bot?(binary() | nil) :: boolean()
  def jid_bot?(jid) when is_binary(jid) do
    [user | _] = String.split(jid, "@", parts: 2)
    Regex.match?(@bot_regex, user) and ends?(jid, "@c.us")
  end

  def jid_bot?(_), do: false

  @doc """
  Checks if a JID represents a newsletter.
  """
  @spec jid_newsletter?(binary() | nil) :: boolean()
  def jid_newsletter?(jid), do: ends?(jid, "@newsletter")

  @doc """
  Checks if a JID represents a hosted PN user.
  """
  @spec hosted_pn_user?(binary() | nil) :: boolean()
  def hosted_pn_user?(jid), do: ends?(jid, "@hosted")

  @doc """
  Checks if a JID represents a hosted LID user.
  """
  @spec hosted_lid_user?(binary() | nil) :: boolean()
  def hosted_lid_user?(jid), do: ends?(jid, "@hosted.lid")

  @doc """
  Checks if a JID is the status broadcast.
  """
  @spec jid_status_broadcast?(binary()) :: boolean()
  def jid_status_broadcast?(jid), do: jid == "status@broadcast"

  @doc """
  Checks if a JID represents Meta AI.
  """
  @spec jid_meta_ai?(binary() | nil) :: boolean()
  def jid_meta_ai?(jid), do: ends?(jid, "@bot")

  @doc """
  Normalizes a JID to user format, converting c.us to s.whatsapp.net.
  """
  @spec jid_normalized_user(binary() | nil) :: binary()
  def jid_normalized_user(jid), do: jid |> decode() |> to_user_jid()

  # Re-encode a decoded jid to its account-level user form — dropping device/agent
  # (we take only `:user`/`:server`) and normalizing c.us → s.whatsapp.net. A
  # malformed jid (`decode/1` → nil) yields "".
  defp to_user_jid(%{user: user, server: "c.us"}),
    do: encode(%{user: user, server: "s.whatsapp.net"})

  defp to_user_jid(%{user: user, server: server}), do: encode(%{user: user, server: server})
  defp to_user_jid(_), do: ""

  @doc """
  Compares two JIDs to see if they represent the same user.

  Divergence from Baileys (deliberate): two undecodable jids are **not** the same
  user. Baileys' `areJidsSameUser` returns `true` for two nils; we don't — nil is
  the absence of an identity, not a shared one.
  """
  @spec are_jids_same_user?(binary() | nil, binary() | nil) :: boolean()
  def are_jids_same_user?(jid1, jid2) do
    case {decode(jid1), decode(jid2)} do
      {%{user: u}, %{user: u}} -> true
      _ -> false
    end
  end

  @doc """
  Copies the device id of `from_jid` onto `to_jid` (device 0 when the source has none).

  Divergence from Baileys (deliberate): an undecodable `to_jid` yields `""` rather
  than throwing — callers already treat `""` as "no jid", so a soft failure keeps
  the pipeline going instead of crashing the connection.
  """
  @spec transfer_device(binary(), binary()) :: binary()
  def transfer_device(from_jid, to_jid) do
    device_id =
      case decode(from_jid) do
        %{device: device} -> device
        _ -> 0
      end

    case decode(to_jid) do
      %{user: user, server: server} ->
        encode(%{user: user, server: server, device: device_id})

      _ ->
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
        decode_user_agent(user_agent, server, parse_int(device))

      [user_agent] ->
        decode_user_agent(user_agent, server, nil)
    end
  end

  defp decode_user_agent(user_agent, server, device) do
    case String.split(user_agent, "_", parts: 2) do
      [user, agent] ->
        domain_type = get_domain_type(server, parse_int(agent))
        build_result(user, server, device, domain_type)

      [user] ->
        domain_type = get_domain_type(server, nil)
        build_result(user, server, device, domain_type)
    end
  end

  # JIDs are server-supplied; a malformed device/agent segment degrades to nil
  # rather than crashing the decode.
  defp parse_int(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
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
