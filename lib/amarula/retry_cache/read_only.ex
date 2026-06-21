defmodule Amarula.RetryCache.ReadOnly do
  @moduledoc """
  A read-only `Amarula.RetryCache` adapter backed by **your** message store.

  Use this when your application already persists the messages it sends (an
  outbox, an event log, a DB table). Pointing the retry cache at that store means
  Amarula keeps **no second copy** — no ETS table, no DETS file, no `max_entries`
  to size — and the retry path reads straight from what you already have.

  **You own writes; Amarula only reads.** This adapter implements no write side at
  all — it does not define the optional `put/4` callback, so Amarula never even
  attempts a write, and never evicts or deletes anything in your store. It is
  *your* data. When a recipient asks the server for a retry, Amarula calls your
  `get` with the `msg_id` and expects the original message back so it can
  re-encrypt and resend it.

  ## Usage

  Pass a `:get` function `fn profile, msg_id -> {:ok, entry} | :error end`:

      Amarula.new(%{
        profile: :primary,
        retry_cache:
          {Amarula.RetryCache.ReadOnly,
           get: fn _profile, msg_id ->
             case MyApp.Outbox.fetch(msg_id) do
               {:ok, %{to: jid, proto: %Amarula.Protocol.Proto.Message{} = m}} ->
                 {:ok, %{recipient_jid: jid, message: m}}

               :error ->
                 :error
             end
           end}
      })

  The returned map needs `:recipient_jid` (the wire JID the message went to) and
  `:message` (the original `%Amarula.Protocol.Proto.Message{}`). Return the message
  **exactly as it was sent** — a re-serialized or transformed copy may not match
  what the recipient is retrying against. Return `:error` if you no longer have it
  (e.g. past your own retention); Amarula then simply can't resend, which is the
  same outcome as a built-in cache miss.

  ## Why a function, not a module

  For the common "wrap my store" case a closure is the whole adapter. If you need
  more (per-profile state, a pooled connection), implement the `Amarula.RetryCache`
  behaviour directly instead — this module is just the convenient shape.
  """

  @behaviour Amarula.RetryCache

  @impl true
  def new(opts) do
    get = Keyword.fetch!(opts, :get)

    unless is_function(get, 2) do
      raise ArgumentError,
            "#{inspect(__MODULE__)} requires a :get function of arity 2 " <>
              "(fn profile, msg_id -> {:ok, entry} | :error end), got: #{inspect(get)}"
    end

    %{get: get}
  end

  # No `put/4`: this adapter is read-only. The behaviour's `put` is optional, so
  # Amarula never calls a write here — the consumer's store already holds the
  # message. There is no write path to misuse.

  @impl true
  def get(%{get: get}, profile, msg_id), do: get.(profile, msg_id)

  # We don't track size; the consumer's store does. Report 0 (introspection only).
  @impl true
  def count(_state, _profile), do: 0
end
