# Live-test on-demand history fetch (Amarula.fetch_history/4) with a REAL anchor.
#
#   mix run examples/fetch_history.exs
#
# This script is its own event consumer (parent_pid: self()) — it doesn't use
# examples/connection.ex. It connects (needs an already-paired ./amarula_data),
# captures the first real incoming 1:1 message as the "oldest" anchor, then sends
# a PEER_DATA_OPERATION on-demand history request for that chat and waits for the
# phone's ON_DEMAND HistorySync reply (logged as a second :history_sync).

require Logger
alias Amarula.{Address, Msg}
alias Amarula.Protocol.Proto

{:ok, conn} =
  %{profile: :default}
  |> Amarula.new()
  |> Amarula.connect(parent_pid: self())

defmodule Loop do
  require Logger
  alias Amarula.{Address, Msg}

  # Phase 1: wait until :open.
  def await_open(deadline) do
    receive do
      {:amarula, :connection_update, %{connection: :open}} ->
        Logger.info("connection OPEN")
        :ok

      {:amarula, _t, _d} ->
        await_open(deadline)
    after
      timeout(deadline) -> :timeout
    end
  end

  # Phase 2: capture the first real incoming 1:1 (dm, not from us) message — its
  # chat + id + timestamp are a valid oldest-message anchor.
  def first_dm_anchor(deadline) do
    receive do
      {:amarula, :messages_upsert, msgs} ->
        case Enum.find(msgs, &dm_anchor?/1) do
          %Msg{} = m -> {:ok, m}
          nil -> first_dm_anchor(deadline)
        end

      {:amarula, _t, _d} ->
        first_dm_anchor(deadline)
    after
      timeout(deadline) -> :timeout
    end
  end

  # Phase 3: after firing the request, wait for the ON_DEMAND :history_sync reply.
  def await_on_demand(deadline) do
    receive do
      {:amarula, :history_sync, %{sync_type: st} = r} ->
        Logger.info(
          "📜 history sync #{inspect(st)}: #{length(r.chats)} chats, " <>
            "#{length(r.contacts)} contacts"
        )

        if st in [:ON_DEMAND, :on_demand] do
          {:ok, r}
        else
          await_on_demand(deadline)
        end

      {:amarula, _t, _d} ->
        await_on_demand(deadline)
    after
      timeout(deadline) -> :timeout
    end
  end

  # Any 1:1 (pn) message with a usable key is a valid oldest-message anchor —
  # incoming or our own (from_me). We just need a real {chatJid, id, ts}.
  defp dm_anchor?(%Msg{chat: %Address{kind: :pn}, id: id, timestamp: ts})
       when is_binary(id) and is_integer(ts),
       do: true

  defp dm_anchor?(_), do: false

  defp timeout(deadline), do: max(0, deadline - System.monotonic_time(:millisecond))
end

result =
  with :ok <- Loop.await_open(System.monotonic_time(:millisecond) + 40_000),
       {:ok, %Msg{} = anchor} <-
         Loop.first_dm_anchor(System.monotonic_time(:millisecond) + 60_000) do
    chat_jid = Address.to_jid(anchor.chat)

    key = %Proto.MessageKey{
      remoteJid: chat_jid,
      fromMe: anchor.from_me,
      id: anchor.id
    }

    Logger.info(
      "anchor: chat=#{chat_jid} id=#{anchor.id} ts=#{anchor.timestamp} — fetching 50 older"
    )

    ret = Amarula.fetch_history(conn, key, anchor.timestamp * 1000, 50)
    Logger.info("fetch_history returned: #{inspect(ret)}")

    Loop.await_on_demand(System.monotonic_time(:millisecond) + 20_000)
  end

case result do
  {:ok, _} ->
    Logger.info("✅ ON_DEMAND history reply received — fetch_history works end-to-end.")

  :timeout ->
    Logger.warning(
      "⏱️  timed out (no :open, no incoming DM to anchor on, or no ON_DEMAND reply). " <>
        "The request may still have been accepted; check the fetch_history return above."
    )
end
