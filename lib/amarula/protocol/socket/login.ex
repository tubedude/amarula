defmodule Amarula.Protocol.Socket.Login do
  @moduledoc """
  The Noise XX handshake + login-bootstrap stanza builders, extracted from
  `Connection`. Pure: these compute frames/nodes from inputs and return
  values — they do NOT touch the websocket, timers, or emit events. CM stays the
  process: it sends the frames/nodes, transitions state, and emits updates.

  Handshake flow (CM drives it across `:ws_event` frames):

      client_hello(creds, config)  → {:ok, hello_frame, handshake_state}   # CM sends hello_frame
      server_hello(handshake, frame) → {:ok, finish_frame, final_noise}    # CM sends finish_frame
      complete(final_noise)        → transport_noise_state                 # CM enters transport
  """

  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Crypto.{Constants, NoiseHandler}
  alias Amarula.Protocol.Socket.ConnectionValidator

  @doc """
  Build the ClientHello frame + initial handshake state from creds/config.
  Always returns `{:ok, encoded_frame, handshake_state}` (with `sent_intro` set) —
  it is pure key generation plus encoding, with no failure path.
  """
  # Narrowed to the success tuple only: `Connection` matches it directly, so if a
  # failure path is ever added here Dialyzer flags that call site instead of it
  # becoming a MatchError at runtime.
  @spec client_hello(map(), map()) :: {:ok, binary(), map()}
  def client_hello(auth_creds, config) do
    with {:ok, client_hello_message, handshake_state} <-
           ConnectionValidator.generate_client_hello(auth_creds, config),
         {encoded_frame, updated_noise} <-
           NoiseHandler.encode_frame(handshake_state.noise_state, client_hello_message) do
      {:ok, encoded_frame, %{handshake_state | noise_state: updated_noise}}
    end
  end

  @doc """
  Process a ServerHello `frame` against `handshake_state`: decode, validate, and
  produce the ClientFinish frame. Returns `{:ok, finish_frame, final_noise_state}`
  or `{:error, reason}`. (CM sends `finish_frame`, then calls `complete/1`.)
  """
  @spec server_hello(map(), binary()) :: {:ok, binary(), map()} | {:error, term()}
  def server_hello(handshake_state, frame_data) do
    with {:ok, decoded_frame} <- decode_first_frame(handshake_state, frame_data),
         {:ok, client_finish, updated_handshake} <-
           ConnectionValidator.process_server_hello(handshake_state, decoded_frame) do
      {encoded_finish, final_noise} =
        NoiseHandler.encode_frame(updated_handshake.noise_state, client_finish)

      {:ok, encoded_finish, final_noise}
    end
  end

  @doc "Transition the post-ClientFinish noise state into the transport phase."
  @spec complete(map()) :: map()
  def complete(final_noise_state), do: NoiseHandler.finish_init(final_noise_state)

  # --- login-bootstrap stanza builders (pure Node constructors) ---

  @doc "The digest-key-bundle IQ (`<iq get xmlns=encrypt><digest/>`)."
  @spec digest_iq() :: Node.t()
  def digest_iq do
    %Node{
      tag: "iq",
      attrs: [{"to", Constants.s_whatsapp_net()}, {"type", "get"}, {"xmlns", "encrypt"}],
      content: [%Node{tag: "digest", attrs: %{}, content: nil}]
    }
  end

  @doc "The unified-session `<ib><unified_session id=>` node (id per Baileys)."
  @spec unified_session_node() :: Node.t()
  def unified_session_node do
    three_days = 3 * 24 * 60 * 60 * 1000
    seven_days = 7 * 24 * 60 * 60 * 1000
    id = rem(System.system_time(:millisecond) + three_days, seven_days)

    %Node{
      tag: "ib",
      attrs: %{},
      content: [
        %Node{tag: "unified_session", attrs: %{"id" => Integer.to_string(id)}, content: nil}
      ]
    }
  end

  @doc ~S(The `<iq xmlns="passive" type="set">` node, e.g. `"active"`.)
  @spec passive_iq(String.t(), String.t()) :: Node.t()
  def passive_iq(iq_id, tag) do
    %Node{
      tag: "iq",
      attrs: [
        {"to", Constants.s_whatsapp_net()},
        {"xmlns", "passive"},
        {"type", "set"},
        {"id", iq_id}
      ],
      content: [%Node{tag: tag, attrs: %{}, content: nil}]
    }
  end

  @doc "The three init-query `{base_attrs, child}` specs (`abt`/`props`, `blocklist`, `privacy`)."
  @spec init_query_specs() :: [{[{String.t(), String.t()}], Node.t() | nil}]
  def init_query_specs do
    [
      {[{"to", Constants.s_whatsapp_net()}, {"xmlns", "abt"}, {"type", "get"}],
       %Node{tag: "props", attrs: %{"protocol" => "1"}, content: nil}},
      {[{"xmlns", "blocklist"}, {"to", Constants.s_whatsapp_net()}, {"type", "get"}], nil},
      {[{"xmlns", "privacy"}, {"to", Constants.s_whatsapp_net()}, {"type", "get"}],
       %Node{tag: "privacy", attrs: %{}, content: nil}}
    ]
  end

  @doc ~S(The `<iq xmlns="md" type="set"><remove-companion-device .../></iq>` node.)
  @spec remove_companion_iq(String.t(), String.t()) :: Node.t()
  def remove_companion_iq(iq_id, jid) do
    %Node{
      tag: "iq",
      attrs: [
        {"to", Constants.s_whatsapp_net()},
        {"type", "set"},
        {"id", iq_id},
        {"xmlns", "md"}
      ],
      content: [
        %Node{
          tag: "remove-companion-device",
          attrs: %{"jid" => jid, "reason" => "user_initiated"},
          content: nil
        }
      ]
    }
  end

  @doc ~S(The keep-alive `<iq xmlns="w:p" type="get"><ping/></iq>` node.)
  @spec ping_iq(String.t()) :: Node.t()
  def ping_iq(ping_id) do
    %Node{
      tag: "iq",
      attrs: [
        {"id", ping_id},
        {"to", "@s.whatsapp.net"},
        {"type", "get"},
        {"xmlns", "w:p"}
      ],
      content: [%Node{tag: "ping", attrs: %{}, content: nil}]
    }
  end

  @doc ~S(The `<presence type="available" name=...>` stanza.)
  @spec presence_available_node(String.t()) :: Node.t()
  def presence_available_node(name) do
    %Node{
      tag: "presence",
      attrs: [{"name", String.replace(name, "@", "")}, {"type", "available"}],
      content: nil
    }
  end

  @doc """
  Parse an `<ib><dirty .../></ib>` node and build the `<iq xmlns=\"urn:xmpp:whatsapp:dirty\"><clean .../></iq>` reply.
  """
  @spec dirty_clean_iq(Node.t()) :: {:ok, String.t(), Node.t()} | :ignore
  def dirty_clean_iq(node) do
    case NodeUtils.get_binary_node_child(node, "dirty") do
      nil ->
        :ignore

      dirty ->
        type = NodeUtils.get_attr(dirty, "type") || "account_sync"
        ts = NodeUtils.get_attr(dirty, "timestamp")
        clean_attrs = if ts, do: %{"type" => type, "timestamp" => ts}, else: %{"type" => type}

        iq = %Node{
          tag: "iq",
          attrs: [
            {"to", Constants.s_whatsapp_net()},
            {"type", "set"},
            {"xmlns", "urn:xmpp:whatsapp:dirty"}
          ],
          content: [%Node{tag: "clean", attrs: clean_attrs, content: nil}]
        }

        {:ok, type, iq}
    end
  end

  @doc "The `<ib><offline_batch count=\"100\"/></ib>` stanza."
  @spec offline_batch_node() :: Node.t()
  def offline_batch_node do
    %Node{
      tag: "ib",
      attrs: %{},
      content: [%Node{tag: "offline_batch", attrs: %{"count" => "100"}, content: nil}]
    }
  end

  @doc "Read the `count` attribute from an `<ib><offline_preview count=.../></ib>` stanza."
  @spec offline_preview_count(Node.t()) :: String.t()
  def offline_preview_count(node) do
    case NodeUtils.get_binary_node_child(node, "offline_preview") do
      nil -> "?"
      child -> NodeUtils.get_attr(child, "count") || "?"
    end
  end

  @doc "Read the integer `count` from an `<ib><offline count=.../></ib>` stanza."
  @spec offline_complete_count(Node.t()) :: non_neg_integer()
  def offline_complete_count(node) do
    case NodeUtils.get_binary_node_child(node, "offline") do
      nil -> 0
      child -> String.to_integer(NodeUtils.get_attr(child, "count") || "0")
    end
  end

  @doc "Extract binary `routing_info` from an `<ib><edge_routing><routing_info>` stanza."
  @spec routing_info(Node.t()) :: {:ok, binary()} | :ignore
  def routing_info(node) do
    with %Node{} = edge <- NodeUtils.get_binary_node_child(node, "edge_routing"),
         %Node{content: info} when is_binary(info) <-
           NodeUtils.get_binary_node_child(edge, "routing_info") do
      {:ok, info}
    else
      _ -> :ignore
    end
  end

  @doc "Extract `{code, reason}` from a `<stream:error>` stanza (Baileys `getErrorCodeFromStreamError`)."
  @spec stream_error_details(Node.t()) :: {integer(), String.t()}
  def stream_error_details(node) do
    reason =
      case NodeUtils.get_first_child_tag(node) do
        "" -> "unknown"
        tag -> tag
      end

    code =
      case Integer.parse(NodeUtils.get_attr(node, "code") || "") do
        {code, _} -> code
        :error -> 500
      end

    {code, reason}
  end

  @doc "Find our own push name from a `[{jid, name}]` history-sync list when `me.name` is still unset/`\"~\"`."
  @spec own_push_name(map(), [{String.t(), String.t()}]) :: String.t() | nil
  def own_push_name(me, push_names) do
    my_users =
      [Map.get(me, :id), Map.get(me, :lid)]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Amarula.Address.parse/1)

    real_name =
      Enum.find_value(push_names, fn {jid, name} ->
        addr = Amarula.Address.parse(jid)
        if addr && Enum.any?(my_users, &Amarula.Address.same_account?(&1, addr)), do: name
      end)

    if real_name && Map.get(me, :name) in [nil, "~"], do: real_name, else: nil
  end

  # --- internals ---

  defp decode_first_frame(handshake_state, data) do
    # decode_frame/2 only ever returns {:ok, frames, noise} (single return
    # point, and its spec says so), so these two clauses are total.
    case NoiseHandler.decode_frame(handshake_state.noise_state, data) do
      {:ok, [frame | _], _noise} -> {:ok, frame}
      {:ok, [], _noise} -> {:error, :no_handshake_frame}
    end
  end
end
