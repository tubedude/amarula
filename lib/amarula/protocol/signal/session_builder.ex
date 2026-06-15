defmodule Amarula.Protocol.Signal.SessionBuilder do
  @moduledoc """
  X3DH responder session establishment, ported from
  `node_modules/libsignal/src/session_builder.js`.

  Only the **incoming** (responder) path is implemented — we build a session when
  we receive a PreKeyWhisperMessage. The outgoing/initiator path (needed only to
  send the first message in a new conversation) is out of scope for the
  decrypt-only milestone.

  Keys here are raw 32-byte X25519 keys (the leading 0x05 type byte is stripped
  before DH). `our_identity`, prekeys etc. come from the session store.
  """

  alias Amarula.Protocol.Crypto.Crypto
  alias Amarula.Protocol.Signal.{CryptoHelpers, SessionRecord}

  @doc """
  Process an incoming PreKeyWhisperMessage: build a responder session into
  `record` and return `{updated_record, pre_key_id}`.

  `store` must provide:
    * `load_pre_key.(id)`        -> %{public, private} | nil
    * `load_signed_pre_key.(id)` -> %{public, private}
    * `our_identity`             -> %{public, private}

  `message` is the decoded PreKeyWhisperMessage (see WhisperProtocol).
  """
  @spec init_incoming(SessionRecord.t(), map(), map()) ::
          {SessionRecord.t(), non_neg_integer() | nil}
  def init_incoming(record, message, store) do
    cond do
      SessionRecord.get_session(record, message.base_key) != nil ->
        # Already have this session — we just haven't replied.
        {record, message.pre_key_id}

      true ->
        pre_key_pair =
          if message.pre_key_id, do: store.load_pre_key.(message.pre_key_id), else: nil

        if message.pre_key_id && is_nil(pre_key_pair) do
          raise "Invalid PreKey ID"
        end

        signed_pre_key_pair = store.load_signed_pre_key.(message.signed_pre_key_id)

        if is_nil(signed_pre_key_pair) do
          raise "Missing SignedPreKey"
        end

        record =
          case SessionRecord.get_open_session(record) do
            nil -> record
            open -> SessionRecord.close_session(record, open)
          end

        session =
          init_session(
            false,
            pre_key_pair,
            signed_pre_key_pair,
            message.identity_key,
            message.base_key,
            nil,
            message.registration_id,
            store
          )

        {SessionRecord.set_session(record, session), message.pre_key_id}
    end
  end

  @doc """
  Initiator X3DH: build an outgoing session from a fetched prekey bundle,
  ported from libsignal session_builder.js `initOutgoing`.

  `device` is a map with the peer's bundle:
    * `:registration_id`            — integer
    * `:identity_key`               — wire-form pubkey (33B 0x05-prefixed)
    * `:signed_pre_key` => `%{key_id, public, signature}`
    * `:pre_key`        => `%{key_id, public}` | nil (one-time prekey, optional)

  Returns the updated `SessionRecord` with an open session whose
  `pending_pre_key` makes the first send a pkmsg (SessionCipher.encrypt wraps
  it). `store.our_identity` supplies our identity for the DH legs.
  """
  @spec init_outgoing(SessionRecord.t(), map(), map()) :: SessionRecord.t()
  def init_outgoing(record, device, store) do
    spk = device.signed_pre_key

    # Verify the signed prekey signature against the peer's identity (XEd25519).
    # libsignal signs the wire-form (33B) signed-prekey pubkey with the identity
    # key; verify needs the identity as a raw 32B Montgomery key.
    unless Crypto.verify(spk.public, spk.signature, strip5(device.identity_key)) do
      raise "Invalid signature on device key"
    end

    base_key = Crypto.generate_key_pair()
    device_pre_key = device[:pre_key] && device.pre_key.public

    session =
      init_session(
        true,
        base_key,
        nil,
        device.identity_key,
        device_pre_key,
        spk.public,
        device.registration_id,
        store
      )

    pending =
      %{signed_key_id: spk.key_id, base_key: base_key.public}
      |> then(fn p ->
        if device[:pre_key], do: Map.put(p, :pre_key_id, device.pre_key.key_id), else: p
      end)

    session = Map.put(session, :pending_pre_key, pending)

    record =
      case SessionRecord.get_open_session(record) do
        nil -> record
        open -> SessionRecord.close_session(record, open)
      end

    SessionRecord.set_session(record, session)
  end

  @doc """
  Build the session state (X3DH + initial ratchet). Mirrors libsignal initSession.
  Public keys are passed wire-form (33 bytes with 0x05 prefix); DH strips it.
  """
  def init_session(
        is_initiator,
        our_ephemeral_key,
        our_signed_key,
        their_identity_pub_key,
        their_ephemeral_pub_key,
        their_signed_pub_key,
        registration_id,
        store
      ) do
    {our_signed_key, their_signed_pub_key} =
      if is_initiator do
        if our_signed_key, do: raise("Invalid call to initSession")
        {our_ephemeral_key, their_signed_pub_key}
      else
        if their_signed_pub_key, do: raise("Invalid call to initSession")
        {our_signed_key, their_ephemeral_pub_key}
      end

    our_identity = store.our_identity

    a1 = dh(their_signed_pub_key, our_identity.private)
    a2 = dh(their_identity_pub_key, our_signed_key.private)
    a3 = dh(their_signed_pub_key, our_signed_key.private)

    # 32-byte 0xff discontinuity, then the DH outputs in initiator-dependent order
    discontinuity = :binary.copy(<<0xFF>>, 32)

    ordered =
      if is_initiator do
        [a1, a2]
      else
        [a2, a1]
      end

    shared =
      discontinuity <> Enum.at(ordered, 0) <> Enum.at(ordered, 1) <> a3

    shared =
      if our_ephemeral_key && their_ephemeral_pub_key do
        a4 = dh(their_ephemeral_pub_key, our_ephemeral_key.private)
        shared <> a4
      else
        shared
      end

    [root_key, _] =
      CryptoHelpers.derive_secrets(shared, :binary.copy(<<0>>, 32), "WhisperText", 2)

    session =
      SessionRecord.create_entry()
      |> Map.put(:registration_id, registration_id)
      |> Map.put(:current_ratchet, %{
        root_key: root_key,
        ephemeral_key_pair:
          if(is_initiator, do: Crypto.generate_key_pair(), else: our_signed_key),
        last_remote_ephemeral_key: their_signed_pub_key,
        previous_counter: 0
      })
      |> Map.put(:index_info, %{
        created: now_ms(),
        used: now_ms(),
        remote_identity_key: their_identity_pub_key,
        base_key: if(is_initiator, do: our_ephemeral_key.public, else: their_ephemeral_pub_key),
        base_key_type:
          if(is_initiator,
            do: SessionRecord.base_key_ours(),
            else: SessionRecord.base_key_theirs()
          ),
        closed: -1
      })

    if is_initiator do
      calculate_sending_ratchet(session, their_signed_pub_key)
    else
      session
    end
  end

  @doc "Set up the initiator's first sending chain (used only on the initiator path)."
  def calculate_sending_ratchet(session, remote_key) do
    ratchet = session.current_ratchet
    shared = dh(remote_key, ratchet.ephemeral_key_pair.private)

    [new_root, chain_key] =
      CryptoHelpers.derive_secrets(shared, ratchet.root_key, "WhisperRatchet", 2)

    session
    |> SessionRecord.add_chain(ratchet.ephemeral_key_pair.public, %{
      message_keys: %{},
      chain_key: %{counter: -1, key: chain_key},
      chain_type: SessionRecord.chain_sending()
    })
    |> put_in([:current_ratchet, :root_key], new_root)
  end

  # X25519 DH: strip the 0x05 type byte from the 33-byte wire pubkey if present.
  defp dh(<<5, pub::binary-size(32)>>, priv), do: Crypto.shared_key(priv, pub)
  defp dh(<<pub::binary-size(32)>>, priv), do: Crypto.shared_key(priv, pub)

  defp strip5(<<5, k::binary-size(32)>>), do: k
  defp strip5(<<k::binary-size(32)>>), do: k

  defp now_ms, do: System.system_time(:millisecond)
end
