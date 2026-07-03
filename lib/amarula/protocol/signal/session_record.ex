defmodule Amarula.Protocol.Signal.SessionRecord do
  @moduledoc """
  Signal session storage, ported from `node_modules/libsignal/src/session_record.js`.

  A SessionRecord holds one or more session entries keyed by the base key. Each
  entry is a plain map:

      %{
        registration_id: integer | nil,
        current_ratchet: %{
          root_key: binary,
          ephemeral_key_pair: %{public: binary, private: binary},
          last_remote_ephemeral_key: binary,
          previous_counter: integer
        },
        index_info: %{
          created: integer, used: integer,
          remote_identity_key: binary,
          base_key: binary, base_key_type: 1|2,  # OURS | THEIRS
          closed: integer   # -1 = open
        },
        chains: %{ base64_pubkey => chain },
        pending_pre_key: map | nil
      }

  The record is a map: `%{sessions: %{base64_basekey => entry}}`. We persist via
  `:erlang.term_to_binary`, so unlike the JS impl no base64-of-buffers is needed
  for storage — but `chains`/`sessions` are still keyed by base64 strings to match
  libsignal's lookup-by-pubkey semantics exactly.
  """

  @base_key_ours 1
  @base_key_theirs 2
  @chain_sending 1
  @chain_receiving 2
  @closed_sessions_max 40

  def base_key_ours, do: @base_key_ours
  def base_key_theirs, do: @base_key_theirs
  def chain_sending, do: @chain_sending
  def chain_receiving, do: @chain_receiving

  @type t :: %{sessions: %{optional(binary) => map()}}

  @doc "An empty record."
  @spec new() :: t()
  def new, do: %{sessions: %{}}

  @doc "A fresh session entry shell (libsignal createEntry — chains start empty)."
  @spec create_entry() :: map()
  def create_entry, do: %{chains: %{}}

  defp b64(key), do: Base.encode64(key)

  # --- chain helpers (operate on an entry) ---

  @spec add_chain(map(), binary(), map()) :: map()
  def add_chain(entry, key, chain) do
    id = b64(key)

    if Map.has_key?(entry.chains, id) do
      raise "Overwrite attempt"
    end

    put_in(entry.chains[id], chain)
  end

  @spec get_chain(map(), binary()) :: map() | nil
  def get_chain(entry, key), do: Map.get(entry.chains, b64(key))

  @spec put_chain(map(), binary(), map()) :: map()
  def put_chain(entry, key, chain), do: put_in(entry.chains[b64(key)], chain)

  @spec delete_chain(map(), binary()) :: map()
  def delete_chain(entry, key) do
    id = b64(key)

    unless Map.has_key?(entry.chains, id) do
      raise "Not Found"
    end

    %{entry | chains: Map.delete(entry.chains, id)}
  end

  # --- record-level operations ---

  @doc "Look up a session by base key. Raises if it resolves to one of our own base keys."
  @spec get_session(t(), binary()) :: map() | nil
  def get_session(record, key) do
    session = Map.get(record.sessions, b64(key))

    if session && session.index_info.base_key_type == @base_key_ours do
      raise "Tried to lookup a session using our basekey"
    end

    session
  end

  @doc "First open (closed == -1) session, or nil."
  @spec get_open_session(t()) :: map() | nil
  def get_open_session(record) do
    record.sessions
    |> Map.values()
    |> Enum.find(fn s -> not closed?(s) end)
  end

  @doc "Store/replace a session, keyed by its index_info.base_key."
  @spec set_session(t(), map()) :: t()
  def set_session(record, session) do
    put_in(record.sessions[b64(session.index_info.base_key)], session)
  end

  @doc "All sessions, most-recently-used first (by index_info.used)."
  @spec get_sessions(t()) :: [map()]
  def get_sessions(record) do
    record.sessions
    |> Map.values()
    |> Enum.sort_by(fn s -> s.index_info.used || 0 end, :desc)
  end

  @spec closed?(map()) :: boolean()
  def closed?(session), do: session.index_info.closed != -1

  @doc "Close a session (mark it with a closed timestamp). Idempotent."
  @spec close_session(t(), map()) :: t()
  def close_session(record, session) do
    if closed?(session) do
      record
    else
      closed = %{session | index_info: %{session.index_info | closed: now_ms()}}
      put_in(record.sessions[b64(session.index_info.base_key)], closed)
    end
  end

  @doc "Drop oldest closed sessions while over CLOSED_SESSIONS_MAX."
  @spec remove_old_sessions(t()) :: t()
  def remove_old_sessions(record) do
    if map_size(record.sessions) <= @closed_sessions_max do
      record
    else
      closed =
        record.sessions
        |> Enum.filter(fn {_k, s} -> closed?(s) end)
        |> Enum.sort_by(fn {_k, s} -> s.index_info.closed end)

      case closed do
        [{oldest_key, _} | _] ->
          record
          |> Map.update!(:sessions, &Map.delete(&1, oldest_key))
          |> remove_old_sessions()

        [] ->
          raise "Corrupt sessions object"
      end
    end
  end

  defp now_ms, do: System.system_time(:millisecond)
end
