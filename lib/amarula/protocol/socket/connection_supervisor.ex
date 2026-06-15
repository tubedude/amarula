defmodule Amarula.Protocol.Socket.ConnectionSupervisor do
  @moduledoc """
  Per-connection supervision tree. One `ConnectionSupervisor` owns everything for
  a single WhatsApp connection instance:

      ConnectionSupervisor (:one_for_one)
      ├── Registry            (per-instance; keys = {instance_id, role})
      ├── ConnectionManager   (login + socket + IQ correlation)
      ├── SenderSupervisor    (DynamicSupervisor) — ConversationSender…
      └── Socket              (public API; resolves siblings via the Registry)

  Replaces the old approach where `Socket` start_link'd its children inline.
  `Socket.make_socket/2` starts this supervisor and returns the Socket child pid,
  so the public API (`connect/send_text/...` on that pid) is unchanged.

  Siblings find each other through the per-instance `Registry` by role, via
  `name/2` / `whereis/2` — no global atom names, no leaked atoms.
  """

  use Supervisor

  alias Amarula.Protocol.Socket
  alias Amarula.Protocol.Socket.ConnectionManager

  @doc """
  Start a connection instance. `opts` may carry `:parent_pid`. Returns
  `{:ok, sup_pid, socket_pid}` — `socket_pid` is the public handle.
  """
  @spec start_instance(Amarula.Conn.t(), keyword()) ::
          {:ok, pid(), pid()} | {:error, term()}
  def start_instance(%Amarula.Conn{} = conn, opts \\ []) do
    instance_id = make_ref()
    init_arg = %{instance_id: instance_id, conn: conn, opts: opts}

    with {:ok, sup} <- Supervisor.start_link(__MODULE__, init_arg),
         socket when is_pid(socket) <- whereis(instance_id, :socket) do
      {:ok, sup, socket}
    else
      :undefined -> {:error, :socket_not_started}
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
      # ConnectionManager/Socket read them (no lazy create, no race).
      {Amarula.Protocol.Socket.TableOwner, profile: conn.profile},
      {ConnectionManager, {conn, name: name(instance_id, :connection_manager)}},
      {DynamicSupervisor, name: name(instance_id, :sender_supervisor), strategy: :one_for_one},
      {Socket,
       %{
         instance_id: instance_id,
         conn: conn,
         parent_pid: Keyword.get(opts, :parent_pid),
         name: name(instance_id, :socket)
       }}
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
