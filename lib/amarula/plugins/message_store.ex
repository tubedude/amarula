defmodule Amarula.Plugins.MessageStore do
  @moduledoc """
  Example/reference plugin: a persistent message store.

  Amarula is a library — it does not keep long-term message history itself. This
  optional plugin shows the intended pattern for a consumer-side store:

    * subscribe to the socket's `{:whatsapp, :messages_upsert, ..}` events and
      persist incoming messages,
    * remember our own outgoing messages,
    * expose `get_message/2`, which the library calls (via the `:get_message`
      config callback) to re-encrypt + resend a message on a `type="retry"`
      receipt when its built-in recent-message cache has already evicted it.

  It's a GenServer backed by DETS so history survives restarts. A real consumer
  would likely use its own database; this is the minimal working reference.

  ## Wiring

      {:ok, store} = Amarula.Plugins.MessageStore.start_link(dir: "./amarula_store")

      config =
        base_config
        |> Map.put(:get_message, Amarula.Plugins.MessageStore.get_message_fun(store))

      # Make the store the socket's parent_pid so it sees the events directly,
      # or forward `{:whatsapp, :messages_upsert, ..}` to it from your own process.
      {:ok, socket} = Amarula.new(config) |> Amarula.connect(parent_pid: store)
  """

  use GenServer

  alias Amarula.Protocol.Messages.MessageContent

  # --- API ---

  @doc "Start the store. `:dir` sets where the DETS file lives (default ./amarula_store)."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc """
  Record an outgoing message we sent (so a retry can re-fetch it). `key` is a map
  with at least `:remote_jid` and `:id`.
  """
  @spec put(GenServer.server(), %{remote_jid: String.t(), id: String.t()}, struct()) :: :ok
  def put(store, %{remote_jid: jid, id: id}, message) do
    GenServer.cast(store, {:put, id, jid, message})
  end

  @doc "Fetch a stored message by id: `{recipient_jid, %Proto.Message{}}` or nil."
  @spec get_message(GenServer.server(), String.t()) :: {String.t(), struct()} | nil
  def get_message(store, msg_id) do
    GenServer.call(store, {:get_message, msg_id})
  end

  @doc """
  A `fn msg_id -> {recipient_jid, message} | nil` closure to pass as the socket's
  `:get_message` config callback.
  """
  @spec get_message_fun(GenServer.server()) :: (String.t() -> {String.t(), struct()} | nil)
  def get_message_fun(store), do: fn msg_id -> get_message(store, msg_id) end

  # --- GenServer ---

  @impl true
  def init(opts) do
    dir = Keyword.get(opts, :dir, "./amarula_store")
    File.mkdir_p!(dir)
    path = dir |> Path.join("messages.dets") |> String.to_charlist()

    {:ok, table} =
      :dets.open_file(:"amarula_msgstore_#{:erlang.phash2(dir)}", file: path, type: :set)

    {:ok, %{table: table}}
  end

  @impl true
  def handle_cast({:put, id, jid, message}, %{table: table} = state) do
    :dets.insert(table, {id, {jid, message}})
    {:noreply, state}
  end

  @impl true
  def handle_call({:get_message, id}, _from, %{table: table} = state) do
    reply =
      case :dets.lookup(table, id) do
        [{^id, {jid, message}}] -> {jid, message}
        _ -> nil
      end

    {:reply, reply, state}
  end

  # Persist incoming messages delivered as socket events (when used as parent_pid).
  @impl true
  def handle_info(
        {:whatsapp, :messages_upsert, %{from: from, id: id, messages: messages}},
        %{table: table} = state
      ) do
    for message <- messages do
      case MessageContent.classify(message) do
        {:text, _} -> :dets.insert(table, {id, {from, message}})
        {:media, _type, _} -> :dets.insert(table, {id, {from, message}})
        _ -> :ok
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_other, state), do: {:noreply, state}
end
