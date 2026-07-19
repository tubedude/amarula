defmodule Amarula.MessageSecretStore.ReadOnly do
  @moduledoc """
  A read-only `Amarula.MessageSecretStore` adapter backed by **your** message
  store.

  Use this when your application already persists received messages — which you
  must, to render an edit at all. Pointing the store at that data means Amarula
  keeps **no second copy** (no ETS table, no TTL to size) and, unlike the default
  in-memory adapter, message edits keep working across a connection restart
  because retention is your durable store's, not a process's lifetime.

  **You own writes; Amarula only reads.** This adapter implements no write side —
  it does not define the optional `put/4` callback, so Amarula never attempts a
  write. When an edit arrives, Amarula calls your `get` with the target message's
  `msg_id` and expects that message's secret (and its original sender) back.

  ## Usage

  Pass a `:get` function `fn profile, msg_id -> {:ok, entry} | :error end`, where
  `entry` is `%{secret: binary(), sender: String.t()}`:

      Amarula.new(%{
        profile: :primary,
        message_secret_store:
          {Amarula.MessageSecretStore.ReadOnly,
           get: fn _profile, msg_id ->
             case MyApp.Messages.fetch(msg_id) do
               {:ok, %{message_secret: secret, sender_jid: sender}}
               when is_binary(secret) ->
                 {:ok, %{secret: secret, sender: sender}}

               _ ->
                 :error
             end
           end}
      })

  `:sender` must be the message's **original, server-attested** sender (the bare
  normalized JID Amarula delivered it from), not one taken from the edit itself —
  it is what the author check compares against to reject a forged edit. Return
  `:error` if you no longer have the message (past your retention); Amarula then
  can't decrypt the edit, the same outcome as an in-memory cache miss.

  ## Why a function, not a module

  For the common "wrap my store" case a closure is the whole adapter. If you need
  more (per-profile state, a pooled connection), implement the
  `Amarula.MessageSecretStore` behaviour directly instead — this module is just
  the convenient shape.
  """

  @behaviour Amarula.MessageSecretStore

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
  # Amarula never calls a write here — the consumer's store already holds it.

  @impl true
  def get(%{get: get}, profile, msg_id), do: get.(profile, msg_id)

  # We don't track size; the consumer's store does. Report 0 (introspection only).
  @impl true
  def count(_state, _profile), do: 0
end
