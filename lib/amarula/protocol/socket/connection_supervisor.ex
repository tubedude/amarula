defmodule Amarula.Protocol.Socket.ConnectionSupervisor do
  @moduledoc """
  Per-connection supervision tree. One `ConnectionSupervisor` owns everything for
  a single WhatsApp connection instance:

      ConnectionSupervisor (:one_for_one)
      ├── Registry            (per-instance; keys = {instance_id, role})
      ├── TableOwner          (per-connection retry-cache ETS)
      ├── Connection          (THE socket: ws + cipher + IQ + sends + consumer API)
      └── SenderSupervisor    (DynamicSupervisor) — ConversationSender…

  `Connection.make_socket/2` starts this supervisor and returns the `Connection`
  child pid — the consumer's handle, so the public API (`connect/send_text/...`
  on that pid) lands on Connection directly (no relay).

  Siblings find each other through the per-instance `Registry` by role, via
  `name/2` / `whereis/2` — no global atom names, no leaked atoms.
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
      id: supervisor_name(instance_id),
      start:
        {Supervisor, :start_link, [__MODULE__, init_arg, [name: supervisor_name(instance_id)]]},
      type: :supervisor,
      restart: :temporary
    }

    with {:ok, sup} <-
           DynamicSupervisor.start_child(Amarula.Application.connections_supervisor(), spec),
         connection when is_pid(connection) <- whereis(instance_id, :connection) do
      {:ok, sup, connection}
    else
      :undefined -> {:error, :connection_not_started}
      {:error, _} = err -> err
    end
  end

  @doc """
  Stop a whole connection tree by its `instance_id` (the supervisor + all children,
  freeing the profile registration). Returns `:ok`, or `{:error, :not_found}` if no
  such tree is running.
  """
  @spec stop_instance(reference()) :: :ok | {:error, :not_found}
  def stop_instance(instance_id) do
    case Process.whereis(supervisor_name(instance_id)) do
      nil -> {:error, :not_found}
      sup -> Supervisor.stop(sup)
    end
  end

  @doc "The supervisor's registered name, derived from the instance ref."
  @spec supervisor_name(reference()) :: atom()
  def supervisor_name(instance_id) do
    :"amarula_conn_sup_#{:erlang.phash2(instance_id)}"
  end

  @doc "The `:via` tuple addressing a sibling `role` in this instance's Registry."
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
    registry = registry_name(instance_id)

    children = [
      {Registry, keys: :unique, name: registry},
      # Owns the per-connection ETS caches; first child so the tables exist before
      # Connection reads them (no lazy create, no race).
      {Amarula.Protocol.Socket.TableOwner, profile: conn.profile},
      {Connection,
       {conn,
        name: name(instance_id, :connection),
        instance_id: instance_id,
        parent_pid: Keyword.get(opts, :parent_pid)}},
      {DynamicSupervisor, name: name(instance_id, :sender_supervisor), strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  The per-instance Registry's process name. Derived from the instance ref so it
  is unique per instance and dies with the supervisor.
  """
  def registry_name(instance_id) do
    :"sender_registry_#{:erlang.phash2(instance_id)}"
  end
end
