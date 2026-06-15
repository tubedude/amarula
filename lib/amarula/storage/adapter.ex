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
