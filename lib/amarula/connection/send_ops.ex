defmodule Amarula.Connection.SendOps do
  @moduledoc """
  Pure send-path builders for `Amarula.Connection`.

  Each function turns send-callback arguments into a `{target, payload, shape}`
  triple that `Connection.deliver_async/5` dispatches — no socket, no `state`
  mutation, no process. This is the body logic of the `{:send_*}` /
  `{:fetch_history}` / `{:request_resend}` callbacks, lifted out of the GenServer
  module so it is testable without a live connection.

  The callbacks on `Connection` stay thin: they call one of these builders and
  feed the result to `deliver_async`. The ack lifecycle (`park_ack`/`resolve_ack`
  /monitors) is a separate, shared seam and remains on `Connection`.

  `shape` is the reply-shaping fun `deliver_async` applies to the pipe result;
  most sends use `default_send_reply/2`, polls override it to carry the secret.
  """

  alias Amarula.Protocol.Messages.{MessageContent, MessageEncoder}

  @type target :: term()
  @type payload :: map()
  @type shape :: (term(), String.t() -> term())
  @type build :: {target(), payload(), shape()}

  @doc """
  Text → a send build for `jid`. With no reply/mention context it stays the
  lightweight `%{text: text}` shorthand (the sandbox/offline path mints a reply
  without encoding). When `:quoted`/`:mentions` are present we build the full
  `%Proto.Message{}` here (an `extendedTextMessage` carrying the `contextInfo`).
  """
  @spec text(term(), String.t(), keyword()) :: build()
  def text(jid, text, opts \\ []) do
    payload =
      case MessageEncoder.context_info(opts) do
        nil -> %{text: text}
        _ctx -> %{message: MessageEncoder.text(text, opts)}
      end

    {jid, payload, &default_send_reply/2}
  end

  @doc "Pre-built `%Proto.Message{}` → `%{message: message}` for `jid`."
  @spec message(term(), struct()) :: build()
  def message(jid, message), do: {jid, %{message: message}, &default_send_reply/2}

  @doc """
  Poll for `jid`. Builds the poll message + secret, and a `shape` that turns the
  successful `{:ok, id}` reply into `{:ok, id, secret}` so the caller can tally
  votes.
  """
  @spec poll(term(), String.t(), [String.t()], keyword()) :: build()
  def poll(jid, name, options, opts) do
    {message, secret} = MessageEncoder.poll(name, options, opts)

    shape = fn
      :ok, msg_id -> {:ok, msg_id, secret}
      result, msg_id -> default_send_reply(result, msg_id)
    end

    {jid, %{message: message}, shape}
  end

  @doc """
  Built media message (already encrypted + uploaded) → `%{message: message}` for
  `jid`. The encrypt/upload Task lives on `Connection`; this only shapes the
  ready message for dispatch.
  """
  @spec media(term(), struct()) :: build()
  def media(jid, message) do
    # A media message is NOT `type="text"` with a `mediatype` hint on <message> —
    # the server rejects that shape with ack error 479 ("smax-invalid"). The
    # accepted wire shape (verified against a live whatsmeow document send, and
    # whatsmeow send.go getTypeFromMessage / encAttrs): `type="media"` on the
    # <message> node, and `mediatype` on EVERY per-device <enc> child.
    payload =
      case MessageContent.media_type(message) do
        nil ->
          %{message: message}

        type ->
          %{
            message: message,
            stanza_attrs: %{"type" => "media"},
            enc_attrs: %{"mediatype" => type}
          }
      end

    {jid, payload, &default_send_reply/2}
  end

  @doc """
  Placeholder-resend request: a PEER_DATA_OPERATION sent to OURSELVES (`me_id`)
  with the peer category + high push priority so the phone re-delivers the
  original message.
  """
  @spec request_resend(term(), struct()) :: build()
  def request_resend(me_id, message_key) do
    pdo = MessageEncoder.placeholder_resend_request(message_key)

    payload = %{
      message: pdo,
      stanza_attrs: %{"category" => "peer", "push_priority" => "high_force"}
    }

    {me_id, payload, &default_send_reply/2}
  end

  @doc """
  On-demand history request: a PEER_DATA_OPERATION sent to OURSELVES (`me_id`)
  with the peer category + high push priority; the phone replies later with an
  ON_DEMAND HistorySync notification.
  """
  @spec fetch_history(term(), struct(), non_neg_integer(), non_neg_integer()) :: build()
  def fetch_history(me_id, oldest_key, oldest_ts, count) do
    pdo = MessageEncoder.history_sync_on_demand_request(oldest_key, oldest_ts, count)

    payload = %{
      message: pdo,
      stanza_attrs: %{"category" => "peer", "push_priority" => "high_force"}
    }

    {me_id, payload, &default_send_reply/2}
  end

  @doc """
  Default reply shaping for a send: `:ok` → `{:ok, msg_id}`, errors pass through.
  Public so `Connection.deliver_async/5` can use it as the default `shape`.
  """
  @spec default_send_reply(term(), String.t()) :: term()
  def default_send_reply(:ok, msg_id), do: {:ok, msg_id}
  def default_send_reply({:error, reason}, _msg_id), do: {:error, reason}
  def default_send_reply({:halted, reason}, _msg_id), do: {:error, {:halted, reason}}

  @doc """
  Validate and resolve a consumer send `target` (a raw JID string or `%Amarula.Address{}`)
  into `{:ok, jid}` or `{:error, reason}`.

  Refuses unmodelled address kinds, `status@broadcast` (which must go through
  `post_status`), newsletters, broadcast lists, and Meta AI bot targets.
  """
  @spec resolve_target(term()) :: {:ok, String.t()} | {:error, term()}
  # A raw jid STRING has to face the same check as a parsed `%Address{}`.
  # `Address.to_jid/1` passes strings through untouched by design — it is the "I
  # already hold a jid" path — but on the consumer send boundary that is a hole:
  # `send_text(conn, "status@broadcast", …)` would post a status purely because
  # the caller passed a string instead of `msg.channel` (#50).
  #
  # Only unmodelled kinds and the status feed are refused; everything else returns
  # the ORIGINAL string rather than a re-encoded one, so this cannot quietly
  # rewrite a target (`@c.us` would otherwise normalize to `@s.whatsapp.net`).
  def resolve_target(target) when is_binary(target) do
    case Amarula.Address.parse(target) do
      %Amarula.Address{kind: :unsupported, server: server} -> {:error, {:unsupported, server}}
      %Amarula.Address{kind: :status} -> {:error, :status_post_unsupported}
      %Amarula.Address{kind: :newsletter} -> {:error, :newsletter_send_unsupported}
      %Amarula.Address{kind: :broadcast} -> {:error, :broadcast_list_send_unsupported}
      %Amarula.Address{kind: :bot} -> {:error, :bot_send_unsupported}
      _ -> {:ok, target}
    end
  end

  # `status@broadcast` is a real jid, but sending to it POSTS a status to every
  # contact. A bot replying to `msg.channel` of a status post must not do that —
  # the reply belongs to `msg.from`, the author.
  def resolve_target(%Amarula.Address{kind: :status}), do: {:error, :status_post_unsupported}

  # Channel posts are plaintext stanzas of their own, sent only by channel admins —
  # not the Signal send pipeline. Refuse until that is implemented.
  def resolve_target(%Amarula.Address{kind: :newsletter}),
    do: {:error, :newsletter_send_unsupported}

  # Sending to a broadcast list means fanning out to members we do not know.
  def resolve_target(%Amarula.Address{kind: :broadcast}),
    do: {:error, :broadcast_list_send_unsupported}

  # Meta AI takes its own send protocol (bot USync profile, bot metadata), which is
  # not implemented.
  def resolve_target(%Amarula.Address{kind: :bot}), do: {:error, :bot_send_unsupported}
  def resolve_target(target), do: Amarula.Address.to_jid(target)

  @doc """
  Normalize and validate a status audience list into `{:ok, [jid]}` (deduped
  account-level PN/LID JIDs) or `{:error, {:invalid_audience, culprit}}`.
  """
  @spec status_audience(Enumerable.t()) ::
          {:ok, [String.t()]} | {:error, {:invalid_audience, term()}}
  # Account-level PN/LID jids for a status audience, deduped. Anything else (a group,
  # the status feed itself, a non-jid) is refused by name.
  def status_audience(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      case Amarula.Address.parse(entry) do
        %Amarula.Address{kind: kind} = addr when kind in [:pn, :lid] ->
          {:cont, {:ok, [addr |> Amarula.Address.normalize() |> Amarula.Address.to_jid!() | acc]}}

        _ ->
          {:halt, {:error, {:invalid_audience, entry}}}
      end
    end)
    |> case do
      {:ok, []} -> {:error, {:invalid_audience, :empty}}
      {:ok, jids} -> {:ok, jids |> Enum.reverse() |> Enum.uniq()}
      error -> error
    end
  end

  @doc """
  Build the fire-and-forget resend payload for a cached message requested by a
  retry receipt, preserving original `stanza_attrs` and re-deriving `mediatype`
  per-`<enc>` attributes.
  """
  @spec resend_payload(String.t(), struct(), map()) :: map()
  def resend_payload(msg_id, message, stanza_attrs) do
    # Re-encrypt + resend the original (same id, so the recipient replaces
    # rather than duplicates). A fresh ConversationSender pass picks up the
    # session the retry's <keys> bundle just injected. Replay the original
    # stanza_attrs so a peer/edit stanza keeps its category/edit on resend.
    # Per-enc attrs aren't cached — re-derive them from the message itself
    # (deterministic), so a retried MEDIA resend keeps its `mediatype` and
    # the server doesn't 479 the retry.
    # Fire-and-forget: no caller is waiting, so `from` is nil.
    enc_attrs =
      case MessageContent.media_type(message) do
        nil -> %{}
        type -> %{"mediatype" => type}
      end

    %{
      msg_id: msg_id,
      message: message,
      stanza_attrs: stanza_attrs,
      enc_attrs: enc_attrs
    }
  end
end
