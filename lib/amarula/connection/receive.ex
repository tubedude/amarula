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
  def build_msg(state, proto, node, from, msg_id, to_addr) do
    stanza_from = Amarula.Address.parse(from)
    from_addr = node |> NodeUtils.get_attr("participant") |> maybe_address() || stanza_from
    from_me? = own_account?(state, from_addr)

    recipient =
      if stanza_from && stanza_from.kind != :group,
        do: node |> NodeUtils.get_attr("recipient") |> maybe_address()

    {channel, to} =
      if from_me? && recipient do
        {recipient, recipient}
      else
        {stanza_from, to_addr}
      end

    proto = normalize_reply_keys(state, proto, channel, from_me?, from_addr)

    Amarula.Msg.from_proto(proto, %{
      id: msg_id,
      channel: channel,
      from: from_addr,
      to: to,
      from_me: from_me?,
      pushname: NodeUtils.get_attr(node, "notify"),
      timestamp: parse_ts(NodeUtils.get_attr(node, "t")),
      server_id: NodeUtils.get_attr(node, "server_id"),
      offline: offline_node?(node)
    })
  end

  @doc "True when a stanza was delivered from the server's offline queue."
  @spec offline_node?(Node.t()) :: boolean()
  def offline_node?(node), do: NodeUtils.get_attr(node, "offline") not in [nil, "", "0"]

  @doc false
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

  defp our_perspective(state, %Proto.MessageKey{} = key, %Amarula.Address{} = channel, from) do
    author = key.participant || key.remoteJid

    %{
      key
      | remoteJid: Amarula.Address.to_jid!(channel),
        fromMe: key.fromMe != true and own_account?(state, maybe_address(author)),
        participant: key.participant || group_participant(channel, from)
    }
  end

  defp group_participant(%Amarula.Address{kind: :group}, %Amarula.Address{} = from),
    do: Amarula.Address.to_jid!(from)

  defp group_participant(_channel, _from), do: nil

  @doc "Stash each decrypted message's `messageSecret` in `MessageSecretStore`."
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

  @doc false
  def own_sender?(state, node, from) do
    participant = node |> NodeUtils.get_attr("participant") |> maybe_address()
    own_account?(state, participant || maybe_address(from))
  end

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
