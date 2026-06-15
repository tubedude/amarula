defmodule Amarula.Protocol.Signal.Group.SenderKeyStore do
  @moduledoc """
  File-backed sender key store for group Signal sessions.

  Mirrors `SessionStore` for 1:1 sessions. `build/1` returns a store map with
  `load_sender_key` and `store_sender_key` function fields that `GroupCipher`
  and `GroupSessionBuilder` call. Each sender key is persisted via
  `Amarula.Storage` (the `:sender_key` namespace, keyed by the sender-key-name
  string), scoped to the connection `conn` (`Amarula.Conn`).
  """

  alias Amarula.Conn
  alias Amarula.Protocol.Signal.Group.SenderKeyName
  alias Amarula.Protocol.Signal.Group.SenderKeyRecord
  alias Amarula.Storage

  @doc """
  Build a store map bound to `conn`.

      store = SenderKeyStore.build(conn)
      {:ok, record} = store.load_sender_key(sk_name)
      :ok = store.store_sender_key(sk_name, updated_record)
  """
  @spec build(Conn.t()) :: %{
          load_sender_key: (SenderKeyName.t() ->
                              {:ok, SenderKeyRecord.t()} | {:error, :not_found}),
          store_sender_key: (SenderKeyName.t(), SenderKeyRecord.t() -> :ok | {:error, term()})
        }
  def build(%Conn{} = conn) do
    %{
      load_sender_key: fn sk_name -> load_sender_key(conn, sk_name) end,
      store_sender_key: fn sk_name, record -> store_sender_key(conn, sk_name, record) end
    }
  end

  @doc "Load a SenderKeyRecord for `sk_name` on `conn`, or {:error, :not_found}."
  @spec load_sender_key(Conn.t(), SenderKeyName.t()) ::
          {:ok, SenderKeyRecord.t()} | {:error, :not_found}
  def load_sender_key(%Conn{storage: scope, profile: profile}, sk_name) do
    case Storage.get(scope, profile, :sender_key, key(sk_name)) do
      {:ok, record} -> {:ok, record}
      :error -> {:error, :not_found}
    end
  end

  @doc "Persist a SenderKeyRecord for `sk_name` on `conn`."
  @spec store_sender_key(Conn.t(), SenderKeyName.t(), SenderKeyRecord.t()) ::
          :ok | {:error, term()}
  def store_sender_key(%Conn{storage: scope, profile: profile}, sk_name, record) do
    Storage.put(scope, profile, :sender_key, key(sk_name), record)
  end

  defp key(sk_name), do: SenderKeyName.to_string_repr(sk_name)
end
