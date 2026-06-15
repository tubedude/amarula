defmodule Amarula.Protocol.Signal.SessionStore do
  @moduledoc """
  Storage glue for the 1:1 Signal session cipher.

  Two responsibilities:

  1. Build the `store` map that `SessionBuilder`/`SessionCipher` need — our
     identity keypair and prekey lookups — sourced from the auth creds map.
  2. Persist `SessionRecord`s via `Amarula.Storage` (the `:session` namespace,
     keyed by signal address). Survives restart so ratchet state isn't lost.

  Persistence is scoped to the connection: the `conn` (`Amarula.Conn`) supplies
  the storage scope and name passed to every `Amarula.Storage` call.

  Keys here are raw 32-byte X25519 (no 0x05 prefix); the cipher/DH handle wire
  prefixing where needed.
  """

  alias Amarula.Conn
  alias Amarula.Storage

  @doc """
  Build the cipher store from auth creds.

  `creds` must have `signed_identity_key` (%{public, private}), `signed_pre_key`
  (%{key_pair: %{public, private}, key_id, ...}). One-time prekeys come from
  `creds.pre_keys` (integer id => %{public, private}, populated by
  `Signal.PreKeys` at upload time); when the id is unknown — e.g. already
  consumed — `load_pre_key` returns nil and the responder X3DH falls back to
  the 4-DH path (no a4), which libsignal supports.
  """
  @spec build(map()) :: map()
  def build(creds) do
    signed = creds.signed_pre_key

    %{
      our_identity: %{
        public: creds.signed_identity_key.public,
        private: creds.signed_identity_key.private
      },
      our_registration_id: Map.get(creds, :registration_id),
      load_signed_pre_key: fn id ->
        if id == signed.key_id or is_nil(id) do
          %{public: signed.key_pair.public, private: signed.key_pair.private}
        else
          nil
        end
      end,
      load_pre_key: fn id -> load_one_time_pre_key(creds, id) end
    }
  end

  # One-time prekeys live under creds.pre_keys (a map id => %{public, private})
  # once prekey upload is implemented; until then this is empty.
  defp load_one_time_pre_key(creds, id) do
    case creds do
      %{pre_keys: pks} when is_map(pks) -> Map.get(pks, id)
      _ -> nil
    end
  end

  @doc "Load a SessionRecord for `addr` on `conn`, or nil if none saved."
  @spec load_session(Conn.t(), String.t()) :: map() | nil
  def load_session(%Conn{storage: scope, profile: profile}, addr) do
    Storage.fetch(scope, profile, :session, addr)
  end

  @doc "Persist a SessionRecord for `addr` on `conn`."
  @spec store_session(Conn.t(), String.t(), map()) :: :ok | {:error, term()}
  def store_session(%Conn{storage: scope, profile: profile}, addr, record) do
    Storage.put(scope, profile, :session, addr, record)
  end
end
