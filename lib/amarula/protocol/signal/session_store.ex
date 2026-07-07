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
  alias Amarula.Protocol.Signal.SessionRecord
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

  @doc """
  Persist a SessionRecord for `addr` on `conn`.

  Prunes oldest closed sessions past the cap first (libsignal's storeRecord:
  `removeOldSessions()` right before `storage.storeSession`), so a persisted
  record never grows unboundedly.
  """
  @spec store_session(Conn.t(), String.t(), map()) :: :ok | {:error, term()}
  def store_session(%Conn{storage: scope, profile: profile}, addr, record) do
    Storage.put(scope, profile, :session, addr, SessionRecord.remove_old_sessions(record))
  end

  @doc """
  Re-key every 1:1 session from a PN identity onto its LID identity.

  When we learn a contact's phone-number identity (`pn_user`, e.g. `"5511…"`) and
  their LID (`lid_user`) are the same account, the live Signal ratchet — keyed under
  the PN signal-address `"<pn_user>.<device>"` — must move to the LID signal-address
  `"<lid_user>_1.<device>"` (the `_1` is the `@lid` domain-type suffix that
  `LidMappingFileStore.plain_signal_address/1` emits). Otherwise a message addressed
  under the other identity looks under an empty key and fails to decrypt.

  Re-keys in place: each PN session is copied onto the LID address (the PN record
  wins over any pre-existing LID session — the PN ratchet is the live one), then the
  PN entry is deleted. No prekey fetch, no renegotiation.
  Returns the number of sessions moved — `0` when the contact had no PN session
  (e.g. first contact after LID adoption), which the caller can treat as "still
  needs a fresh bundle".
  """
  @spec migrate_pn_to_lid(Conn.t(), String.t(), String.t()) :: non_neg_integer()
  def migrate_pn_to_lid(%Conn{storage: scope, profile: profile} = conn, pn_user, lid_user) do
    pn_prefix = pn_user <> "."

    case Storage.list_keys(scope, profile, :session) do
      {:ok, keys} ->
        keys
        |> Enum.filter(&String.starts_with?(&1, pn_prefix))
        |> Enum.reduce(0, &move_session(&1, conn, pn_prefix, lid_user, &2))

      # An adapter that can't enumerate keys can't be migrated in place; treat as
      # "nothing moved" so the caller falls back to a fresh-bundle fetch.
      _ ->
        0
    end
  end

  # Move one PN session onto its LID address ("<lid_user>_1.<device>"), deleting the
  # PN entry. Returns the running count, unchanged when the PN key held no record.
  defp move_session(
         pn_addr,
         %Conn{storage: scope, profile: profile} = conn,
         pn_prefix,
         lid_user,
         moved
       ) do
    device = String.replace_prefix(pn_addr, pn_prefix, "")
    lid_addr = "#{lid_user}_1.#{device}"

    case load_session(conn, pn_addr) do
      nil ->
        moved

      record ->
        store_session(conn, lid_addr, record)
        Storage.delete(scope, profile, :session, pn_addr)
        moved + 1
    end
  end
end
