defmodule Amarula.Connection.Receive do
  @moduledoc """
  Receive-path parsers, envelope normalizers, and receipt/ack/retry stanza
  builders for `Amarula.Connection`.
  """

  require Logger

  alias Amarula.MessageSecretStore
  alias Amarula.Protocol.Auth.DeviceIdentity
  alias Amarula.Protocol.Binary.{JID, Node, NodeUtils}
  alias Amarula.Protocol.Messages.{EditEnvelope, MessageContent}
  alias Amarula.Protocol.Proto
  alias Amarula.Protocol.Signal.{DecryptError, PreKeys}

  @doc """
  The outcome of a message `<ack>`: `:ok` when there's no error attr, or
  `{:error, {:send_rejected, code}}` when the server rejected the send.
  """
  @spec ack_outcome(term()) :: :ok | {:error, {:send_rejected, String.t()}}
  def ack_outcome(node) do
    case NodeUtils.get_attr(node, "error") do
      nil -> :ok
      code -> {:error, {:send_rejected, code}}
    end
  end

  @doc """
  The `{msg_id, participant}` a retry receipt targets. `participant` falls back
  to `from` when absent (a 1:1 retry). `msg_id` may be nil (caller skips).
  """
  @spec retry_targets(term()) :: {String.t() | nil, String.t() | nil}
  def retry_targets(node) do
    msg_id = NodeUtils.get_attr(node, "id")
    from = NodeUtils.get_attr(node, "from")
    participant = NodeUtils.get_attr(node, "participant") || from
    {msg_id, participant}
  end

  @doc """
  Wrap a decrypted proto into the consumer `%Amarula.Msg{}`, pulling the envelope
  (chat, sender, timestamp, from_me) off the stanza and remapping any embedded
  reply keys to our perspective.
  """
  # `to_addr` is our own identity — constant across a node's messages, so the caller
  # computes it once per batch (via `own_address/1`) and passes it in.
  def build_msg(state, proto, node, from, msg_id, to_addr) do
    # Three address roles (see Amarula.Msg): `channel` is the room (the reply handle —
    # group jid for groups, the peer for DMs). `from` is the writer (the participant in
    # a group, else the channel) and carries the sending device. `to` is whom it was
    # addressed to.
    stanza_from = Amarula.Address.parse(from)
    from_addr = node |> NodeUtils.get_attr("participant") |> maybe_address() || stanza_from
    from_me? = own_account?(state, from_addr)

    # WhatsApp fans every message we send out to our linked devices as a `from_me`
    # stanza whose `from` is our own account — so the stanza `from` is NOT the peer.
    # The real other party is the `recipient` attr (Baileys decode: own message →
    # chatId = recipient). Use it for both the room (`channel`/reply handle) and `to`,
    # so a consumer can tell "I messaged myself" (to == self) from "I messaged someone
    # else" (to == that contact). Falls back to the old behaviour when absent (e.g. a
    # peer-routed self stanza with no recipient).
    # Only for non-group stanzas: a group's room is the group jid (`from`), and
    # group messages carry `participant`, never `recipient` (Baileys applies the
    # recipient override only in the PN/LID-user branch, not the group branch).
    # `stanza_from` is nil when `from` doesn't parse (the decrypt-failure path — a
    # Signal-desynced contact: "Key used already" / old counter / bad PreKey id). Such
    # a message must NOT crash the connection (it'd loop-crash inbound + fetch_groups);
    # skip the recipient override and let the fallback branch carry the nils through.
    recipient =
      if stanza_from && stanza_from.kind != :group,
        do: node |> NodeUtils.get_attr("recipient") |> maybe_address()

    {channel, to} =
      if from_me? && recipient do
        {recipient, recipient}
      else
        {stanza_from, to_addr}
      end

    # Reply-style messages (reaction/edit/revoke/pin/keep/poll-vote) embed a
    # target-message key written from the SENDER'S perspective. Remap it to OURS
    # before the consumer sees it, so a received `key` is safe to feed straight
    # back to `send_reaction`/`send_edit`/… as `Amarula.Msg` promises (#47).
    proto = normalize_reply_keys(state, proto, channel, from_me?, from_addr)

    Amarula.Msg.from_proto(proto, %{
      id: msg_id,
      channel: channel,
      from: from_addr,
      to: to,
      from_me: from_me?,
      # The sender's display name, off the stanza envelope (absent on our own sends).
      pushname: NodeUtils.get_attr(node, "notify"),
      timestamp: parse_ts(NodeUtils.get_attr(node, "t")),
      server_id: NodeUtils.get_attr(node, "server_id"),
      offline: offline_node?(node)
    })
  end

  @doc "True when a stanza was delivered from the server's offline queue."
  @spec offline_node?(Node.t()) :: boolean()
  # Delivered from the server's offline queue (the stanza's `offline` attr).
  # `offline="0"` can appear on online stanzas (Baileys #2810 / #2840) — treat it as online.
  def offline_node?(node), do: NodeUtils.get_attr(node, "offline") not in [nil, "", "0"]

  @doc false
  # An embedded `%Proto.MessageKey{}` names its TARGET from the AUTHOR'S perspective:
  # in a DM the peer's `remoteJid` is *us* and `fromMe` is false-from-their-side, so
  # feeding it straight back to `send_reaction` reacts to ourselves. Rewrite each
  # embedded key to OUR perspective — the same normalisation Baileys does in
  # `processMessage`/`normaliseKey`: `remoteJid` ← the chat as we see it (`channel`,
  # already account-level), `fromMe` recomputed against our own account (PN *and*
  # LID, via `own_account?/2`), and the target's author preserved as `participant`
  # (for a group carrier, filled from the carrier's participant when the sender
  # omitted it). #47. Groups masked the bug (a group jid is identical from every
  # perspective) — the DM case is where it bit.
  #
  # A `from_me?` carrier already embeds keys in our perspective, so leave it alone;
  # ditto when there is no `channel` to remap onto (the decrypt-failure path).
  def normalize_reply_keys(_state, proto, _channel, true, _from), do: proto
  def normalize_reply_keys(_state, proto, nil, _from_me?, _from), do: proto

  def normalize_reply_keys(
        state,
        %Proto.Message{reactionMessage: %{key: key} = r} = proto,
        channel,
        _from_me?,
        from
      )
      when not is_nil(key),
      do: %{proto | reactionMessage: %{r | key: our_perspective(state, key, channel, from)}}

  def normalize_reply_keys(
        state,
        %Proto.Message{pollUpdateMessage: %{pollCreationMessageKey: key} = m} = proto,
        channel,
        _from_me?,
        from
      )
      when not is_nil(key),
      do: %{
        proto
        | pollUpdateMessage: %{
            m
            | pollCreationMessageKey: our_perspective(state, key, channel, from)
          }
      }

  # Only the key-bearing protocol types (edit/revoke) name a message in this chat;
  # other protocolMessages (history sync, key share, …) either carry no key or a key
  # with unrelated semantics — leave those untouched.
  def normalize_reply_keys(
        state,
        %Proto.Message{protocolMessage: %{type: type, key: key} = pm} = proto,
        channel,
        _from_me?,
        from
      )
      when not is_nil(key) and type in [:MESSAGE_EDIT, :REVOKE],
      do: %{proto | protocolMessage: %{pm | key: our_perspective(state, key, channel, from)}}

  def normalize_reply_keys(
        state,
        %Proto.Message{pinInChatMessage: %{key: key} = m} = proto,
        channel,
        _from_me?,
        from
      )
      when not is_nil(key),
      do: %{proto | pinInChatMessage: %{m | key: our_perspective(state, key, channel, from)}}

  def normalize_reply_keys(
        state,
        %Proto.Message{keepInChatMessage: %{key: key} = m} = proto,
        channel,
        _from_me?,
        from
      )
      when not is_nil(key),
      do: %{proto | keepInChatMessage: %{m | key: our_perspective(state, key, channel, from)}}

  def normalize_reply_keys(_state, proto, _channel, _from_me?, _from), do: proto

  # Rewrite one embedded key to our perspective (see `normalize_reply_keys/5`).
  defp our_perspective(state, %Proto.MessageKey{} = key, %Amarula.Address{} = channel, from) do
    author = key.participant || key.remoteJid

    %{
      key
      | remoteJid: Amarula.Address.to_jid!(channel),
        fromMe: key.fromMe != true and own_account?(state, maybe_address(author)),
        participant: key.participant || group_participant(channel, from)
    }
  end

  # The carrier's own participant, but only for a group target — a DM key carries no
  # participant, and fabricating one from the peer would be wrong.
  defp group_participant(%Amarula.Address{kind: :group}, %Amarula.Address{} = from),
    do: Amarula.Address.to_jid!(from)

  defp group_participant(_channel, _from), do: nil

  @doc "Stash each decrypted message's `messageSecret` in `MessageSecretStore`."
  # Stash each decrypted message's messageContextInfo.messageSecret keyed by the
  # stanza id (what a later edit's targetMessageKey.id references), together with
  # the stanza's server-attested author — EditEnvelope's author check compares
  # the editor against it. #30.
  def stash_message_secrets(conn, profile, node, from, messages) do
    msg_id = NodeUtils.get_attr(node, "id")
    sender = JID.jid_normalized_user(NodeUtils.get_attr(node, "participant") || from)

    if is_binary(msg_id) and sender != "" do
      store = conn.message_secret_store

      messages
      |> Enum.map(&MessageContent.message_secret/1)
      |> Enum.filter(&is_binary/1)
      |> Enum.each(&MessageSecretStore.put(store, profile, msg_id, %{secret: &1, sender: sender}))
    end
  end

  @doc "Decrypt a `secretEncryptedMessage` MESSAGE_EDIT envelope back into an inline edit."
  # Decrypt a secretEncryptedMessage MESSAGE_EDIT envelope back into the legacy
  # inline-edit message; anything else passes through untouched. A decryption
  # failure (no stashed secret / expired window / wrong author) logs and passes
  # the envelope through — it classifies {:other, _}, exactly as before #30.
  def decrypt_edit_envelope(conn, profile, node, from, message) do
    ctx = %{
      conn: conn,
      profile: profile,
      stanza_from: from,
      participant: NodeUtils.get_attr(node, "participant")
    }

    case EditEnvelope.decrypt(message, ctx) do
      {:ok, inner} ->
        inner

      :not_an_edit_envelope ->
        message

      {:error, reason} ->
        Logger.warning(
          "Could not decrypt secretEncryptedMessage edit from #{from}: #{inspect(reason)}"
        )

        message
    end
  end

  @doc "Our own identity as an `%Amarula.Address{}`, or empty before login."
  def own_address(me) do
    case me[:id] do
      id when is_binary(id) -> Amarula.Address.parse(id) || Amarula.Address.empty()
      _ -> Amarula.Address.empty()
    end
  end

  @doc "Emit `[:amarula, :message, :received]` telemetry for each decrypted message."
  # One :message,:received per decrypted message — throughput + media volume.
  # media_bytes is the sender's declared fileLength (no eager download). Privacy:
  # counts/kinds/booleans only.
  def emit_message_telemetry(profile, msgs, node, from) do
    group? = JID.jid_group?(from)
    offline? = offline_node?(node)

    Enum.each(msgs, fn msg ->
      {media?, media_kind, bytes} =
        case msg do
          %{type: :media, content: %Amarula.Content.Media{kind: kind, file_length: len}} ->
            {true, kind, len || 0}

          _ ->
            {false, nil, 0}
        end

      Amarula.Telemetry.emit(
        [:amarula, :message, :received],
        profile,
        %{count: 1, media_bytes: bytes},
        %{
          from_me?: msg.from_me,
          group?: group?,
          offline?: offline?,
          media?: media?,
          media_kind: media_kind
        }
      )
    end)
  end

  @doc "True when `addr` is one of our own identities (`id` or `lid`)."
  def own_account?(state, %Amarula.Address{} = addr) do
    me = Map.get(state.auth_creds, :me, %{})

    [me[:id], me[:lid]]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Amarula.Address.parse/1)
    |> Enum.any?(&Amarula.Address.same_account?(&1, addr))
  end

  def own_account?(_state, _), do: false

  # Who actually sent this stanza, server-attested (participant for a group,
  # else the stanza `from`) — the same identity build_msg/6 uses for `from_me?`.
  # Exposed (not private) so it can be unit-tested directly, like build_msg/6.
  #
  # Callers gate the self-only protocolMessage types on this BEFORE any
  # per-message classification: APP_STATE_SYNC_KEY_SHARE and
  # HISTORY_SYNC_NOTIFICATION are only ever legitimate from our own linked
  # device. Baileys shipped this as a security fix (GHSA-qvv5-jq5g-4cgg /
  # CVE-2026-48063) — without it, anyone who can open a session with us can
  # spoof one of these to poison our app-state sync keys or feed us fake
  # history.
  @doc false
  def own_sender?(state, node, from) do
    participant = node |> NodeUtils.get_attr("participant") |> maybe_address()
    own_account?(state, participant || maybe_address(from))
  end

  # A redelivery we can't (and needn't) retry: the key material the stanza
  # references is unavailable — the ratchet counter was consumed, or the pkmsg's
  # one-time prekey isn't in our store. The Signal layer flags this structurally as
  # `%DecryptError{reason: :key_unavailable}` (raised in `SessionCipher`/
  # `SessionBuilder`, propagated through the multi-session trial decrypt), so we
  # match the reason — not error prose, which the `msg` path wraps. It's ~always a
  # duplicate; recognising it each time is what terminates the redelivery loop,
  # which recurs on every 515 reconnect (the server re-fans the undrained stanza)
  # where an in-memory "seen msg_ids" set would be wiped by the restart. Exposed
  # for a direct test.
  @doc false
  def duplicate_decrypt_error?(errors) do
    Enum.any?(errors, &match?(%DecryptError{reason: :key_unavailable}, &1))
  end

  @doc "True when a decrypted `Proto.Message` carries a history-sync notification."
  def history_sync_message?(%{protocolMessage: %{historySyncNotification: hsn}})
      when not is_nil(hsn),
      do: true

  def history_sync_message?(%{deviceSentMessage: %{message: inner}}) when not is_nil(inner),
    do: history_sync_message?(inner)

  def history_sync_message?(_), do: false

  @doc "Extract all `historySyncNotification` payloads from a list of messages."
  def history_notifications(messages) do
    Enum.flat_map(messages, &history_notification/1)
  end

  defp history_notification(%{protocolMessage: %{historySyncNotification: hsn}})
       when not is_nil(hsn),
       do: [hsn]

  defp history_notification(%{deviceSentMessage: %{message: inner}}) when not is_nil(inner),
    do: history_notification(inner)

  defp history_notification(_), do: []

  @doc "Build an `<ack>` stanza for an incoming node (`error_code` for a nack)."
  def ack_stanza(node, me_id, error_code \\ nil) do
    attrs =
      [
        {"id", NodeUtils.get_attr(node, "id")},
        {"to", NodeUtils.get_attr(node, "from")},
        {"class", node.tag}
      ] ++
        optional_attr("error", error_code && Integer.to_string(error_code)) ++
        optional_attr("participant", NodeUtils.get_attr(node, "participant")) ++
        optional_attr("recipient", NodeUtils.get_attr(node, "recipient")) ++
        optional_attr("type", NodeUtils.get_attr(node, "type")) ++
        if(node.tag == "message" and is_binary(me_id), do: [{"from", me_id}], else: [])

    %Node{tag: "ack", attrs: attrs, content: nil}
  end

  @doc "Build the `<receipt type=\"hist_sync\">` node acknowledging initial history sync."
  def hist_sync_receipt(node) do
    from = NodeUtils.get_attr(node, "from")
    jid = JID.jid_normalized_user(from)

    %Node{
      tag: "receipt",
      attrs: [
        {"id", NodeUtils.get_attr(node, "id")},
        {"to", jid},
        {"type", "hist_sync"}
      ],
      content: nil
    }
  end

  @doc "Build the delivery `<receipt>` (or newsletter `<ack>`) node for a decrypted message."
  def delivery_receipt(state, node) do
    from = NodeUtils.get_attr(node, "from")

    if JID.jid_newsletter?(from) do
      ack_stanza(node, get_in(state.auth_creds, [:me, :id]))
    else
      person_receipt(state, node, from)
    end
  end

  # Delivery receipt for a successfully decrypted message, ported from Baileys
  # sendReceipt (messages-send.ts) as called by handleMessage:
  #   <receipt id to [participant] [type]/>
  # type: "peer_msg" for category="peer" stanzas, "sender" for messages sent
  # from our own phone (fromMe), absent = plain delivered.
  defp person_receipt(state, node, from) do
    participant = NodeUtils.get_attr(node, "participant")
    category = NodeUtils.get_attr(node, "category")
    author = participant || from

    type =
      cond do
        category == "peer" -> "peer_msg"
        author_is_me?(state, author) -> "sender"
        true -> nil
      end

    # Baileys: for type="sender" on a 1:1 (pn/lid) jid, recipient=jid and
    # to=participant; otherwise (a group, the status feed, a broadcast list, no
    # participant) the
    # plain to+participant form.
    to_attrs =
      if type == "sender" and is_binary(participant) and person_jid?(from) do
        [{"recipient", from}, {"to", participant}]
      else
        [{"to", from}] ++ optional_attr("participant", participant)
      end

    attrs =
      [{"id", NodeUtils.get_attr(node, "id")}] ++ to_attrs ++ optional_attr("type", type)

    %Node{tag: "receipt", attrs: attrs, content: nil}
  end

  defp person_jid?(jid) do
    match?(%Amarula.Address{kind: kind} when kind in [:pn, :lid], Amarula.Address.parse(jid))
  end

  @doc "Build the `<receipt type=\"retry\">` stanza for a failed decrypt."
  def retry_receipt(node, retry_count, registration_id, extra_children) do
    msg_id = NodeUtils.get_attr(node, "id")
    participant = NodeUtils.get_attr(node, "participant")

    retry_child = %Node{
      tag: "retry",
      attrs: [
        {"count", Integer.to_string(retry_count)},
        {"id", msg_id},
        {"t", NodeUtils.get_attr(node, "t") || ""},
        {"v", "1"},
        {"error", "0"}
      ],
      content: nil
    }

    registration_child = %Node{
      tag: "registration",
      attrs: %{},
      content: <<registration_id::big-unsigned-32>>
    }

    attrs =
      [
        {"id", msg_id},
        {"type", "retry"},
        {"to", NodeUtils.get_attr(node, "from")}
      ] ++
        optional_attr("participant", participant) ++
        optional_attr("recipient", NodeUtils.get_attr(node, "recipient"))

    %Node{
      tag: "receipt",
      attrs: attrs,
      content: [retry_child, registration_child] ++ extra_children
    }
  end

  @doc "Reserve a one-time prekey and build `{updated_creds, keys_node}` for a retry receipt (`count > 1`)."
  # <keys> bundle for a retry receipt: reserves a fresh one-time prekey
  # (persisted internally) and includes identity + signed prekey + device
  # identity, mirroring Baileys' getNextPreKeys(authState, 1) block.
  def retry_keys_node(creds) do
    {updated_creds, [{key_id, pair} | _]} = PreKeys.get_next_pre_keys(creds, 1)

    keys_node = %Node{
      tag: "keys",
      attrs: %{},
      content: [
        %Node{tag: "type", attrs: %{}, content: PreKeys.key_bundle_type()},
        %Node{tag: "identity", attrs: %{}, content: creds.signed_identity_key.public},
        PreKeys.xmpp_pre_key(pair, key_id),
        PreKeys.xmpp_signed_pre_key(creds.signed_pre_key),
        %Node{
          tag: "device-identity",
          attrs: %{},
          content: DeviceIdentity.encode(creds.account, true)
        }
      ]
    }

    {updated_creds, keys_node}
  end

  @doc "Look up a sent message in `RetryCache` or the consumer `get_message` callback."
  def lookup_for_resend(retry_cache, profile, config, msg_id) do
    case Amarula.RetryCache.get(retry_cache, profile, msg_id) do
      {:ok, %{recipient_jid: recipient, message: message} = entry} ->
        {recipient, message, Map.get(entry, :stanza_attrs, %{})}

      :error ->
        case get_message_via_callback(config, msg_id) do
          {recipient, message} -> {recipient, message, %{}}
          nil -> nil
        end
    end
  end

  @doc "Run the receive plugin pipeline over `messages`."
  def run_recv_steps(%{recv_steps: []}, _from, _id, messages), do: messages

  def run_recv_steps(%{recv_steps: steps, profile: profile}, from, id, messages) do
    Enum.flat_map(messages, fn message ->
      ctx = %{message: message, from: from, id: id, profile: profile}

      case Amarula.Plugin.run(steps, ctx) do
        {:cont, %{message: m}} -> [m]
        {:halt, _reason} -> []
      end
    end)
  end

  # config[:get_message] is `fn msg_id -> {recipient_jid, %Proto.Message{}} | nil`,
  # supplied by a consumer store plugin. Absent/erroring callback → no resend.
  defp get_message_via_callback(config, msg_id) do
    case Map.get(config, :get_message) do
      fun when is_function(fun, 1) ->
        case fun.(msg_id) do
          {recipient, %{} = message} when is_binary(recipient) -> {recipient, message}
          _ -> nil
        end

      _ ->
        nil
    end
  rescue
    error ->
      Logger.warning("get_message callback failed for #{msg_id}: #{inspect(error)}")
      nil
  end

  # fromMe: the author is one of our own identities (pn or lid user part).
  defp author_is_me?(state, author) do
    me = Map.get(state.auth_creds, :me) || %{}

    author_user =
      case JID.decode(author) do
        %{user: user} -> user
        _ -> nil
      end

    my_users =
      [Map.get(me, :id), Map.get(me, :lid)]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn jid ->
        case JID.decode(jid) do
          %{user: user} -> user
          _ -> nil
        end
      end)

    author_user != nil and author_user in my_users
  end

  defp maybe_address(nil), do: nil
  defp maybe_address(jid), do: Amarula.Address.parse(jid)

  defp parse_ts(nil), do: nil
  defp parse_ts(t), do: String.to_integer(t)

  defp optional_attr(_key, nil), do: []
  defp optional_attr(key, value), do: [{key, value}]
end
