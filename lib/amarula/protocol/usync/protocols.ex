defmodule Amarula.Protocol.USync.Protocols do
  @moduledoc """
  USync protocol definitions.

  Port of `src/WAUSync/Protocols/`. Each protocol contributes three things to
  a USync query:

    * `query_element/1` — the node placed inside `<query>` (what to fetch)
    * `user_element/2`  — the per-user node placed inside `<user>` (may be `nil`)
    * `parse/2`         — turns a result child node into a parsed value

  Protocols are addressed by atom (`:devices`, `:contact`, `:status`,
  `:disappearing_mode`, `:bot_profile`, `:lid`, `:username`). `parse/2` is also
  keyed by the wire tag string so the result parser can dispatch directly.
  """

  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Binary.NodeUtils

  # --- query elements (inside <query>) ---

  @spec query_element(atom()) :: Node.t()
  def query_element(:devices),
    do: %Node{tag: "devices", attrs: %{"version" => "2"}, content: nil}

  def query_element(:contact), do: %Node{tag: "contact", attrs: %{}, content: nil}
  def query_element(:status), do: %Node{tag: "status", attrs: %{}, content: nil}

  def query_element(:disappearing_mode),
    do: %Node{tag: "disappearing_mode", attrs: %{}, content: nil}

  def query_element(:bot_profile), do: %Node{tag: "bot_profile", attrs: %{}, content: nil}
  def query_element(:lid), do: %Node{tag: "lid", attrs: %{}, content: nil}
  def query_element(:username), do: %Node{tag: "username", attrs: %{}, content: nil}

  # --- user elements (inside <user>); nil means "omit for this user" ---

  @spec user_element(atom(), map()) :: Node.t() | nil
  def user_element(:devices, _user), do: nil
  def user_element(:status, _user), do: nil
  def user_element(:disappearing_mode, _user), do: nil
  def user_element(:bot_profile, _user), do: nil

  def user_element(:lid, %{lid: lid}) when is_binary(lid),
    do: %Node{tag: "lid", attrs: %{"jid" => lid}, content: nil}

  def user_element(:lid, _user), do: nil

  def user_element(:contact, %{phone: phone}) when is_binary(phone),
    do: %Node{tag: "contact", attrs: %{}, content: phone}

  def user_element(:contact, %{username: username} = user) when is_binary(username) do
    attrs =
      %{"username" => username}
      |> maybe_put("pin", Map.get(user, :username_key))
      |> maybe_put("lid", Map.get(user, :lid))

    %Node{tag: "contact", attrs: attrs, content: nil}
  end

  def user_element(:contact, %{type: type}) when is_binary(type),
    do: %Node{tag: "contact", attrs: %{"type" => type}, content: nil}

  def user_element(:contact, _user), do: %Node{tag: "contact", attrs: %{}, content: nil}

  def user_element(:username, _user), do: nil

  # --- result parsing (keyed by wire tag) ---

  @doc """
  Parse a result child node by its wire tag. Returns `nil` when the value
  should be dropped from the result map (matches Baileys' `null` filtering).
  """
  @spec parse(String.t(), Node.t()) :: any()
  def parse("devices", %Node{} = node), do: parse_devices(node)
  def parse("contact", %Node{} = node), do: NodeUtils.get_attr(node, "type") == "in"
  def parse("status", %Node{} = node), do: parse_status(node)
  def parse("lid", %Node{} = node), do: NodeUtils.get_attr(node, "val")
  def parse(_tag, _node), do: nil

  # devices → %{device_list: [...], key_index: %{...} | nil}
  defp parse_devices(node) do
    device_list_node = NodeUtils.get_binary_node_child(node, "device-list")
    key_index_node = NodeUtils.get_binary_node_child(node, "key-index-list")

    %{
      device_list: parse_device_list(device_list_node),
      key_index: parse_key_index(key_index_node)
    }
  end

  defp parse_device_list(%Node{content: content}) when is_list(content) do
    content
    |> Enum.filter(&match?(%Node{tag: "device"}, &1))
    |> Enum.map(fn %Node{attrs: _} = device ->
      %{
        id: device |> NodeUtils.get_attr("id") |> to_int(),
        key_index: device |> NodeUtils.get_attr("key-index") |> to_int(),
        is_hosted: NodeUtils.get_attr(device, "is_hosted") == "true"
      }
    end)
  end

  defp parse_device_list(_), do: []

  defp parse_key_index(%Node{tag: "key-index-list", attrs: _, content: content} = node) do
    %{
      timestamp: node |> NodeUtils.get_attr("ts") |> to_int(),
      signed_key_index: if(is_binary(content), do: content),
      expected_timestamp: node |> NodeUtils.get_attr("expected_ts") |> to_int_or_nil()
    }
  end

  defp parse_key_index(_), do: nil

  # status → %{status: string | nil, set_at: DateTime | nil}
  defp parse_status(node) do
    raw = status_content(node)
    code = node |> NodeUtils.get_attr("code") |> to_int_or_nil()

    status =
      cond do
        is_binary(raw) and raw != "" -> raw
        code == 401 -> ""
        true -> nil
      end

    # A missing `t` means "unknown", not the Unix epoch.
    set_at =
      case node |> NodeUtils.get_attr("t") |> to_int_or_nil() do
        nil -> nil
        unix -> DateTime.from_unix!(unix)
      end

    %{status: status, set_at: set_at}
  end

  defp status_content(%Node{content: content}) when is_binary(content), do: content
  defp status_content(_), do: nil

  # --- helpers ---

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp to_int(nil), do: 0
  defp to_int(value) when is_integer(value), do: value

  defp to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp to_int_or_nil(nil), do: nil

  defp to_int_or_nil(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end
end
