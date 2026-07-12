defmodule Amarula.Storage.Adapter do
  @moduledoc """
  Ergonomic base for writing an `Amarula.Storage` adapter.

      defmodule MyApp.RedisStore do
        use Amarula.Storage.Adapter

        @impl true
        def new(opts), do: %{conn: connect(opts[:url])}

        @impl true
        def get(%{conn: c}, namespace, key), do: ...

        @impl true
        def put(%{conn: c}, namespace, key, value), do: ...

        @impl true
        def delete(%{conn: c}, namespace, key), do: ...
      end

  Then point a connection at it:

      Amarula.new(%{profile: :p, storage: {MyApp.RedisStore, url: "redis://..."}})
      |> Amarula.connect()

  `use Amarula.Storage.Adapter` declares `@behaviour Amarula.Storage` and gives
  you a default `new/1` that simply returns the opts as a map — override it when
  your adapter needs to build real per-connection state (a pool, a dir, a table).
  `get/3`, `put/4` and `delete/3` have no sensible default, so you must implement
  them; the compiler will tell you if you forget one.

  The value `new/1` returns is the opaque per-connection state threaded back to
  every other callback — this is what lets one adapter module serve many
  independent connections (different accounts) without a global.

  > #### The adapter must not call back into Amarula {: .warning}
  >
  > `get/3`, `put/4` and `delete/3` may touch only the adapter's own backing store
  > (disk, ETS, a network client). They must **never** call into an Amarula process
  > — a `Connection`, a `ConversationSender`, or a `SessionCustodian`. The crypto
  > records are serialized by a per-record `SessionCustodian` that reaches storage
  > *synchronously*; an adapter that called back into one of those processes could
  > deadlock (the custodian waits on the adapter, the adapter waits on the custodian).
  > Keep adapters a dependency leaf: pure I/O against your backend, nothing more.
  >
  > Callbacks must also stay **fast** — well under a second. A `SessionCustodian`
  > holds a record's per-record lock while calling `get`/`put`/`delete`
  > synchronously; a stall there blocks every queued op on that record, and a stall
  > past ~15s exits the caller (the socket owner). A network-backed adapter needs a
  > tight timeout and a local fallback, not an unbounded blocking call.
  """

  defmacro __using__(_opts) do
    quote do
      @behaviour Amarula.Storage

      @impl Amarula.Storage
      def new(opts), do: Map.new(opts)

      defoverridable new: 1
    end
  end
end
