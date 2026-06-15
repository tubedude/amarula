defmodule Amarula.Protocol.USync do
  @moduledoc """
  USync (user sync) query builder and result parser.

  Port of Baileys' `WAUSync` (`src/WAUSync/`). A USync query bundles one or
  more *protocols* (devices, contact, status, lid, ...) and a list of *users*
  to look up, then is serialized into a single `iq` get with `xmlns="usync"`.

  This module is pure: it builds the request `Node` and parses the response
  `Node`. The socket layer is responsible for sending the IQ and correlating
  the reply (see `Amarula.Protocol.Socket.ConnectionManager`'s tracked-IQ
  machinery).

  ## Usage

      USync.new()
      |> USync.with_context("message")
      |> USync.with_protocol(:devices)
      |> USync.with_protocol(:lid)
      |> USync.with_user(%{id: "1234@s.whatsapp.net"})
      |> USync.build_iq()

  Parse the result of the matching `iq` reply with `parse_result/2`:

      USync.parse_result(query, reply_node)
      #=> %{list: [%{"devices" => ..., id: "1234@s.whatsapp.net"}], side_list: []}
  """

  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Binary.NodeUtils
  alias Amarula.Protocol.Crypto.Constants
  alias Amarula.Protocol.USync.Protocols

  @type protocol ::
          :devices | :contact | :status | :disappearing_mode | :bot_profile | :lid | :username

  @type user :: %{
          optional(:id) => String.t(),
          optional(:lid) => String.t(),
          optional(:phone) => String.t(),
          optional(:username) => String.t(),
          optional(:username_key) => String.t(),
          optional(:type) => String.t(),
          optional(:persona_id) => String.t()
        }

  @type t :: %__MODULE__{
          protocols: [protocol()],
          users: [user()],
          context: String.t(),
          mode: String.t()
        }

  defstruct protocols: [], users: [], context: "interactive", mode: "query"

  @type result_entry :: %{required(:id) => String.t(), optional(String.t()) => any()}
  @type result :: %{list: [result_entry()], side_list: [result_entry()]}

  @doc "Start a new, empty USync query."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Set the query mode (default `\"query\"`)."
  @spec with_mode(t(), String.t()) :: t()
  def with_mode(%__MODULE__{} = q, mode), do: %{q | mode: mode}

  @doc "Set the query context (default `\"interactive\"`)."
  @spec with_context(t(), String.t()) :: t()
  def with_context(%__MODULE__{} = q, context), do: %{q | context: context}

  @doc """
  Append a protocol to the query. Order is preserved to match the request
  element order Baileys produces.
  """
  @spec with_protocol(t(), protocol()) :: t()
  def with_protocol(%__MODULE__{protocols: ps} = q, protocol)
      when protocol in [
             :devices,
             :contact,
             :status,
             :disappearing_mode,
             :bot_profile,
             :lid,
             :username
           ] do
    %{q | protocols: ps ++ [protocol]}
  end

  @doc "Append a user to look up."
  @spec with_user(t(), user()) :: t()
  def with_user(%__MODULE__{users: us} = q, user) when is_map(user) do
    %{q | users: us ++ [user]}
  end

  @doc """
  Build the `iq` request node for this query.

  Mirrors Baileys' `executeUSyncQuery`. The caller supplies the `sid`
  (Baileys uses a fresh message tag); `id` is left unset so the socket layer
  can stamp the correlation id when it sends the IQ.

  Returns `{:error, :no_protocols}` if no protocol was added.
  """
  @spec build_iq(t(), String.t()) :: {:ok, Node.t()} | {:error, :no_protocols}
  def build_iq(query, sid \\ nil)

  def build_iq(%__MODULE__{protocols: []}, _sid), do: {:error, :no_protocols}

  def build_iq(%__MODULE__{} = q, sid) do
    sid = sid || generate_sid()

    user_nodes =
      Enum.map(q.users, fn user ->
        %Node{
          tag: "user",
          attrs: user_attrs(user),
          content:
            q.protocols
            |> Enum.map(&Protocols.user_element(&1, user))
            |> Enum.reject(&is_nil/1)
        }
      end)

    list_node = %Node{tag: "list", attrs: %{}, content: user_nodes}

    query_node = %Node{
      tag: "query",
      attrs: %{},
      content: Enum.map(q.protocols, &Protocols.query_element/1)
    }

    usync_node = %Node{
      tag: "usync",
      attrs: %{
        "context" => q.context,
        "mode" => q.mode,
        "sid" => sid,
        "last" => "true",
        "index" => "0"
      },
      content: [query_node, list_node]
    }

    iq = %Node{
      tag: "iq",
      attrs: %{
        "to" => Constants.s_whatsapp_net(),
        "type" => "get",
        "xmlns" => "usync"
      },
      content: [usync_node]
    }

    {:ok, iq}
  end

  @doc """
  Parse a USync `iq` reply for the given query.

  Returns `%{list: [...], side_list: [...]}` where each list entry is a map of
  `protocol_name => parsed_value` plus an `:id` key (the user's jid).
  Returns `nil` if the reply is not a `type="result"` IQ.

  Side-list parsing is not yet implemented (matches the Baileys TODO).
  """
  @spec parse_result(t(), Node.t() | nil) :: result() | nil
  def parse_result(%__MODULE__{} = _query, %Node{attrs: %{"type" => "result"}} = reply) do
    usync = NodeUtils.get_binary_node_child(reply, "usync")
    list_node = usync && NodeUtils.get_binary_node_child(usync, "list")

    %{list: parse_list(list_node), side_list: []}
  end

  def parse_result(_query, _reply), do: nil

  # --- internals ---

  defp parse_list(%Node{content: content}) when is_list(content),
    do: Enum.flat_map(content, &parse_user/1)

  defp parse_list(_), do: []

  # Inbound nodes always carry a map of attrs (the decoder builds them with
  # Map.put), so we can match the jid straight from the head. A user entry without
  # a jid is skipped.
  defp parse_user(%Node{content: content, attrs: %{"jid" => id}}),
    do: [Map.put(parse_user_data(content), :id, id)]

  defp parse_user(_), do: []

  defp parse_user_data(content) when is_list(content) do
    content
    |> Enum.map(fn %Node{tag: tag} = child -> {tag, Protocols.parse(tag, child)} end)
    |> Enum.reject(fn {_tag, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp parse_user_data(_), do: %{}

  # The `jid` attr is set only when looking up by id/lid; a phone lookup omits
  # it (Baileys: `jid: !user.phone ? user.id : undefined`).
  defp user_attrs(%{phone: phone}) when is_binary(phone), do: %{}
  defp user_attrs(%{id: id}) when is_binary(id), do: %{"jid" => id}
  defp user_attrs(_), do: %{}

  defp generate_sid do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
