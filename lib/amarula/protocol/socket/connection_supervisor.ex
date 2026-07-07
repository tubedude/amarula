defmodule Amarula.Protocol.Socket.ConnectionSupervisor do
  @moduledoc """
  Per-connection supervision tree. One `ConnectionSupervisor` owns everything for
  a single WhatsApp connection instance:

      ConnectionSupervisor (:rest_for_one)
      ├── Connection          (THE socket: ws + cipher + IQ + sends + consumer API;
      │                        also owns the retry-cache ETS table)
      └── SenderSupervisor    (DynamicSupervisor) — ConversationSender…

  `Connection.make_socket/2` starts this supervisor and returns the `Connection`
  child pid — the consumer's handle, so the public API (`connect/send_text/...`
  on that pid) lands on Connection directly (no relay).

  This tree has **no Registry child of its own**. The supervisor, its sibling
  roles, and each `ConversationSender` are named in the app-level
  `Amarula.InstanceRegistry`, keyed by the `instance_id` ref — so no atom is
  minted per connection and two connections can never collide. Siblings find each
  other by role via `name/2` / `whereis/2`.

  `:rest_for_one` (not `:one_for_one`) because senders block on Connection's IQ
  replies: if Connection restarts, the senders waiting on it must restart too. A
  sender crash, conversely, never restarts Connection.
  """

  use Supervisor

  alias Amarula.Connection

  @doc """
  Start a connection instance. `opts` may carry `:parent_pid`. Returns
  `{:ok, sup_pid, connection_pid}` — `connection_pid` is the consumer handle.

  The tree is started under the library-owned `Amarula.ConnectionsSupervisor`
  (a `DynamicSupervisor`), **not** linked to the calling consumer. A connection
  crash is therefore observable by the consumer through `parent_pid` events but
  never delivers an exit signal that would take the consumer down.
  """
  @spec start_instance(Amarula.Conn.t(), keyword()) ::
          {:ok, pid(), pid()} | {:error, term()}
  def start_instance(%Amarula.Conn{} = conn, opts \\ []) do
    instance_id = make_ref()
    init_arg = %{instance_id: instance_id, conn: conn, opts: opts}

    spec = %{
      id: instance_id,
      start:
        {Supervisor, :start_link, [__MODULE__, init_arg, [name: supervisor_name(instance_id)]]},
      type: :supervisor,
      restart: :temporary
    }

    with :ok <- ensure_supervisor_running(),
         {:ok, sup} <-
           DynamicSupervisor.start_child(Amarula.Supervisor.connections_supervisor(), spec),
         connection when is_pid(connection) <- whereis(instance_id, :connection) do
      {:ok, sup, connection}
    else
      :undefined -> {:error, :connection_not_started}
      {:error, _} = err -> err
    end
  end

  # `Amarula.Supervisor` is added by the consumer, not started automatically. If it
  # isn't running, raise a message naming the fix instead of exiting with `:noproc`.
  defp ensure_supervisor_running do
    if Process.whereis(Amarula.Supervisor.connections_supervisor()) do
      :ok
    else
      raise """
      Amarula.Supervisor is not running. Add `Amarula.Supervisor` to your supervision \
      tree, before any `{Amarula, …}` connection children:

          children = [Amarula.Supervisor, MyApp.Bot, {Amarula, profile: :me, parent: MyApp.Bot}]
      """
    end
  end

  @doc """
  Stop a whole connection tree by its `instance_id` (the supervisor + all children,
  freeing the profile registration). Returns `:ok`, or `{:error, :not_found}` if no
  such tree is running.
  """
  @spec stop_instance(reference()) :: :ok | {:error, :not_found}
  def stop_instance(instance_id) do
    case GenServer.whereis(supervisor_name(instance_id)) do
      nil -> {:error, :not_found}
      sup -> Supervisor.stop(sup)
    end
  end

  @doc """
  The `:via` tuple naming the tree supervisor, keyed by `instance_id` in the
  app-level `Amarula.InstanceRegistry`. No atom is minted per connection.
  """
  @spec supervisor_name(reference()) :: {:via, Registry, term()}
  def supervisor_name(instance_id) do
    {:via, Registry, {registry_name(instance_id), {:supervisor, instance_id}}}
  end

  @doc "The `:via` tuple addressing a sibling `role` in this instance's registry."
  @spec name(reference(), atom()) :: {:via, Registry, {atom(), {reference(), atom()}}}
  def name(instance_id, role) do
    {:via, Registry, {registry_name(instance_id), {instance_id, role}}}
  end

  @doc "Resolve a sibling `role` to a pid, or `:undefined`."
  @spec whereis(reference(), atom()) :: pid() | :undefined
  def whereis(instance_id, role) do
    case Registry.lookup(registry_name(instance_id), {instance_id, role}) do
      [{pid, _}] -> pid
      [] -> :undefined
    end
  end

  @impl true
  def init(%{instance_id: instance_id, conn: conn, opts: opts}) do
    children = [
      {Connection,
       {conn,
        name: name(instance_id, :connection),
        instance_id: instance_id,
        parent_pid: Keyword.get(opts, :parent_pid)}},
      {DynamicSupervisor, name: name(instance_id, :sender_supervisor), strategy: :one_for_one}
    ]

    # `:rest_for_one`, ordered Connection → sender supervisor. Senders block on
    # Connection's IQ replies, so if Connection restarts the senders (which may be
    # mid-pipe waiting on it) must restart too. The reverse is not true — a sender
    # crash is isolated and never restarts Connection. (Connection owns the retry
    # cache's ETS itself, so there is no separate cache child to coordinate.)
    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc """
  The app-level registry that names this instance's infrastructure. Constant
  (`Amarula.InstanceRegistry`) — keys carry the `instance_id`, so no per-instance
  Registry process and no minted atom.
  """
  def registry_name(_instance_id) do
    Amarula.InstanceRegistry
  end
end
