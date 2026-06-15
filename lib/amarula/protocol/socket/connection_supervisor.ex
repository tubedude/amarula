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
  """
  @spec start_instance(Amarula.Conn.t(), keyword()) ::
          {:ok, pid(), pid()} | {:error, term()}
  def start_instance(%Amarula.Conn{} = conn, opts \\ []) do
    instance_id = make_ref()
    init_arg = %{instance_id: instance_id, conn: conn, opts: opts}

    with {:ok, sup} <- Supervisor.start_link(__MODULE__, init_arg),
         connection when is_pid(connection) <- whereis(instance_id, :connection) do
      {:ok, sup, connection}
    else
      :undefined -> {:error, :connection_not_started}
      {:error, _} = err -> err
    end
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
