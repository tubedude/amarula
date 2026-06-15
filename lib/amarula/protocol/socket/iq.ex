defmodule Amarula.Protocol.Socket.IQ do
  @moduledoc """
  IQ request/response correlation, extracted from `Connection` as a pure
  module over the pending-IQ map. CM stays the only process and owns the socket,
  timers, and the tracked-kind continuations; this module decides *what to do*
  with a reply/timeout and returns an **effect** for CM to perform.

  An outbound IQ is registered with one of two intents, keyed by its id:

    * `{:tracked, kind, timer}` — an internal bootstrap step; on reply CM runs the
      continuation for `kind` (login/prekey/digest/app-state/…).
    * `{:waiter, from, timer}` / `{:waiter, from, timer, transform}` — a caller
      blocked in `query_iq`; on reply CM `GenServer.reply`s (optionally mapping
      the result through `transform`).

  `resolve/2` and `timeout/2` return `{new_pending, effect}` where effect is:

    * `{:reply, from, result}` — `GenServer.reply(from, result)`
    * `{:reply, from, transform.(result)}` (already applied)
    * `{:tracked, kind, result, timer}` — cancel `timer`, run the continuation
    * `{:cancel_and_reply, timer, from, result}` — cancel `timer`, then reply
    * `:none` — nothing to do (no waiter for this id)

  Timer cancellation is surfaced as part of the effect so this module performs no
  side effects.
  """

  alias Amarula.Protocol.Binary.NodeUtils

  @type kind :: atom()
  @type entry ::
          {:tracked, kind(), reference()}
          | {:waiter, GenServer.from(), reference()}
          | {:waiter, GenServer.from(), reference(), (term() -> term())}
  @type pending :: %{optional(String.t()) => entry()}
  @type effect ::
          {:reply, GenServer.from(), term(), reference()}
          | {:tracked, kind(), term(), reference()}
          | :none

  @doc "Register a tracked IQ (internal bootstrap step) by id."
  @spec track(pending(), String.t(), kind(), reference()) :: pending()
  def track(pending, id, kind, timer), do: Map.put(pending, id, {:tracked, kind, timer})

  @doc "Register a blocking waiter (query_iq), optionally with a result transform."
  @spec wait(pending(), String.t(), GenServer.from(), reference(), (term() -> term()) | nil) ::
          pending()
  def wait(pending, id, from, timer, nil), do: Map.put(pending, id, {:waiter, from, timer})

  def wait(pending, id, from, timer, transform),
    do: Map.put(pending, id, {:waiter, from, timer, transform})

  @doc """
  Resolve an incoming IQ reply `node`. Returns `{pending, effect}`. The result is
  `{:ok, node}` for type=result, else `{:error, node}`.
  """
  @spec resolve(pending(), Amarula.Protocol.Binary.Node.t()) :: {pending(), effect()}
  def resolve(pending, node) do
    id = NodeUtils.get_attr(node, "id")

    result =
      if NodeUtils.get_attr(node, "type") == "result", do: {:ok, node}, else: {:error, node}

    dispatch(Map.pop(pending, id), result)
  end

  @doc "Resolve an IQ timeout for `id`. Returns `{pending, effect}`."
  @spec timeout(pending(), String.t()) :: {pending(), effect()}
  def timeout(pending, id) do
    dispatch(Map.pop(pending, id), {:error, :timeout})
  end

  # --- pop → effect ---

  defp dispatch({nil, pending}, _result), do: {pending, :none}

  defp dispatch({{:waiter, from, timer}, pending}, result),
    do: {pending, {:reply, from, result, timer}}

  defp dispatch({{:waiter, from, timer, transform}, pending}, result),
    do: {pending, {:reply, from, transform.(result), timer}}

  defp dispatch({{:tracked, kind, timer}, pending}, result),
    do: {pending, {:tracked, kind, result, timer}}
end
