defmodule Amarula.Protocol.Signal.TcTokenStore do
  @moduledoc """
  Trusted-contact privacy token ("tctoken") store, ported from Baileys
  `Utils/tc-token-utils.ts` + the tctoken branches of `Socket/messages-send.ts`
  and `Socket/messages-recv.ts`.

  ## Why this exists

  WhatsApp gates a device's first messages to a contact behind a "trusted
  contact" token exchange — an anti-spam measure. Sending 1:1 without a token
  the recipient trusts gets the message accepted by the socket but rejected at
  the application layer with ack error **463** (`MessageAccountRestriction`):
  the frame goes out, the send looks like it "succeeded" up to that point, but
  no message is ever delivered. This is invisible unless the consumer inspects
  `send_text/3`'s `{:error, {:send_rejected, "463"}}` result.

  The fix has two halves, both driven from `ConversationSender` (attach) and
  `Amarula.Connection` (issue/recover) for 1:1 sends only — never groups:

    1. **Attach**: if we hold a valid (unexpired) token *for the recipient*
       (i.e. proof they've trusted us before), attach it to the outgoing
       `<message>` as a `<tctoken>` child.
    2. **Issue**: after a 1:1 send (success or 463), fire-and-forget an
       `issuePrivacyTokens` IQ that asks the server to vouch for us to that
       contact, and store whatever token(s) come back in the reply so a *future*
       send has one to attach. This never blocks or retries the message itself —
       retrying a 463'd send only compounds the restriction (see Baileys'
       `handleBadAck` comment).

  ## Where a held token gets attached

  The 1:1 `<message>` is the case that fails loudly, but it is not the only
  consumer. WhatsApp Web attaches the same token to three stanzas, and the shape
  differs between them:

    * `<message>` — a `<tctoken>` child with **empty attrs** (`valid_token/2`).
    * `w:profile:picture` query — a `<tctoken t="...">` nested **inside** the
      `<picture>` node (`token_children/2`). Without it, another user's picture
      comes back empty and indistinguishable from "no picture".
    * `<presence type=subscribe>` — a top-level `<tctoken t="...">`
      (`token_children/2`).

  ## Expiry / reissue windows

  Tokens live in 7-day buckets; a token is expired once its bucket falls
  outside the last ~28 days (`TC_TOKEN_NUM_BUCKETS` buckets). We also track our
  own last-issued bucket (`sender_timestamp`) so we don't re-issue every single
  send — only once per bucket per contact (`should_issue_new?/2`).

  ## Storage

  One entry per contact under the `:tctoken` namespace (see `Amarula.Storage`),
  keyed by the *storage jid* — LID-resolved, matching how Signal sessions are
  keyed (`LidMappingFileStore.signal_address/2`), since WA Web stores tctoken
  state under the LID identity. Each entry is
  `%{token: binary(), timestamp: integer(), sender_timestamp: integer() | nil}`
  — `token`/`timestamp` are the peer's token *we hold*; `sender_timestamp` is
  purely local bookkeeping for the reissue dedupe.

  ## Simplifications vs. Baileys

  Baileys reads two AB test props from the server (`privacyTokenOn1to1`,
  `lidTrustedTokenIssueToLid`) via an `abt`/`props` IQ, each defaulting `true`
  and `false` respectively. Fetching + tracking those props is out of scope
  here — we use the documented defaults unconditionally (send-gate always on,
  issue-to-LID always off), which is the common case and what every account
  runs unless explicitly A/B-flighted otherwise.
  """

  alias Amarula.Conn
  alias Amarula.Protocol.Binary.{JID, Node, NodeUtils}
  alias Amarula.Protocol.Signal.LidMappingFileStore
  alias Amarula.Storage

  # 7-day buckets, ~28-day rolling window — mirrors Baileys' tc-token-utils.ts.
  @bucket_seconds 604_800
  @num_buckets 4

  @doc """
  The (unexpired) token bytes we hold for `jid` **with the timestamp they were
  issued at**, as `{token, timestamp}` — or `nil` if we have none, it expired,
  or storage errors (any of which just means "don't attach", not a hard
  failure).

  The timestamp matters because two of the three places a token goes on the
  wire carry it as the node's `t` attr — see `valid_token/2` for the third.
  """
  @spec valid_entry(Conn.t(), String.t()) :: {binary(), integer()} | nil
  def valid_entry(conn, jid) do
    case read(conn, storage_jid(conn, jid)) do
      %{token: token, timestamp: ts} when is_binary(token) and byte_size(token) > 0 ->
        if expired?(ts), do: nil, else: {token, ts}

      _ ->
        nil
    end
  end

  @doc """
  The (unexpired) token bytes we hold for `jid`, without its timestamp, or `nil`.

  This is what the **message** path wants: Baileys attaches the token to an
  outgoing `<message>` as a bare `<tctoken>` with *empty* attrs
  (`messages-send.ts`), unlike the profile-picture and presence-subscribe paths,
  which go through `buildTcTokenFromJid` and carry `t`. Keeping the two accessors
  distinct is what stops the `t` attr from leaking onto the message stanza.
  """
  @spec valid_token(Conn.t(), String.t()) :: binary() | nil
  def valid_token(conn, jid) do
    case valid_entry(conn, jid) do
      {token, _ts} -> token
      nil -> nil
    end
  end

  @doc """
  The `<tctoken t="...">bytes</tctoken>` child list to attach for `jid`, or `[]`
  when we hold nothing usable. Port of Baileys' `buildTcTokenFromJid`
  (`Utils/tc-token-utils.ts`), used by the profile-picture query and
  `presence subscribe`.

  Returns `[]` for anything that isn't a user jid — a group or newsletter has no
  tctoken, and Baileys gates both call sites the same way. Callers with an extra
  rule of their own (the picture query must also skip our *own* account, which
  the server otherwise never answers) apply it before calling.

  Unlike Baileys we do not clear the stored record when it turns out to be
  expired; this stays a pure read. See the deferred note in `docs/PARITY.md`.
  """
  @spec token_children(Conn.t(), String.t()) :: [Node.t()]
  def token_children(conn, jid) do
    if JID.jid_user?(jid) do
      case valid_entry(conn, jid) do
        {token, ts} -> [Node.create("tctoken", %{"t" => Integer.to_string(ts)}, token)]
        nil -> []
      end
    else
      []
    end
  end

  @doc """
  True if we should fire a new `issuePrivacyTokens` for `jid` — we've never
  issued one, or the last issuance fell in an earlier bucket than the current
  one. Bucket-based, so a burst of sends to the same contact issues at most
  once per ~7 days.
  """
  @spec should_issue_new?(Conn.t(), String.t()) :: boolean()
  def should_issue_new?(conn, jid) do
    case read(conn, storage_jid(conn, jid)) do
      %{sender_timestamp: ts} when is_integer(ts) -> bucket(now()) > bucket(ts)
      _ -> true
    end
  end

  @doc """
  Build the `issuePrivacyTokens` IQ (Baileys `Socket/messages-send.ts`
  `issuePrivacyTokens`): `<iq to=s.whatsapp.net type=set xmlns=privacy>
  <tokens><token jid=.. t=.. type=trusted_contact/></tokens></iq>`.
  """
  @spec build_issue_iq(Conn.t(), String.t(), integer()) :: Node.t()
  def build_issue_iq(conn, jid, timestamp) do
    token =
      Node.create("token", %{
        "jid" => issuance_jid(conn, jid),
        "t" => Integer.to_string(timestamp),
        "type" => "trusted_contact"
      })

    Node.create(
      "iq",
      %{"to" => "s.whatsapp.net", "type" => "set", "xmlns" => "privacy"},
      [Node.create("tokens", %{}, [token])]
    )
  end

  @doc """
  Store any `trusted_contact` tokens carried in an `issuePrivacyTokens` IQ
  result (`<tokens><token type=trusted_contact jid=.. t=..>bytes</token>...`),
  then record `sender_timestamp` for `issued_jid` so `should_issue_new?/2`
  dedupes future issuance — ported from Baileys' `storeTcTokensFromIqResult`
  plus the `.then()` bookkeeping in `messages-send.ts`. Best-effort: storage
  failures are logged, never raised (this always runs off the send's critical
  path).

  In practice the IQ result is often empty — the peer's actual token for us
  typically arrives later as its own `<notification type="privacy_token">`
  (see `store_notification/3`), not synchronously in this reply. Both paths
  funnel through the same token-parsing logic; only the bookkeeping differs.
  """
  @spec store_result(Conn.t(), Node.t() | nil, String.t(), integer()) :: :ok
  def store_result(conn, result_node, issued_jid, issued_at) do
    store_tokens(conn, result_node, issued_jid)
    record_issued(conn, issued_jid, issued_at)
    :ok
  end

  @doc """
  Store token(s) carried in an incoming `<notification type="privacy_token">`
  — ported from Baileys' `handlePrivacyTokenNotification`. This is the actual
  channel a peer's trusted-contact token for us arrives on. `fallback_jid`
  (the notification's `from`, or `sender_lid` when present) is used in place
  of the token node's own `jid` attr, which in a notification is *our own*
  device jid, not the sender's (mirrors Baileys' `fallbackJid || tokenNode.attrs.jid`
  precedence). Unlike `store_result/4`, this never touches `sender_timestamp`
  bookkeeping — it's someone else's token arriving, not proof we issued one.
  """
  @spec store_notification(Conn.t(), Node.t(), String.t()) :: :ok
  def store_notification(conn, node, fallback_jid) do
    store_tokens(conn, node, fallback_jid)
    :ok
  end

  @doc """
  Capture a `<tctoken>` riding along on an incoming `<message>` stanza.

  The **proactive** source, ported from Baileys' `storeTcTokenFromMessageNode`
  (mirroring WA Web's `WAWebSetTcTokenChatAction.handleIncomingTcToken`). The other
  three sources are all reactive — our own issuance IQ result, a `privacy_token`
  notification, and the history-sync blob — so without this one a contact can hand
  us their token in the very message we're about to reply to, and we throw it away:
  the reply then goes out tokenless, the socket accepts it, and the server discards
  it with ack `463`. One wasted send plus an issuance round-trip per warm contact,
  for a token we were already holding in the decoded node.

  Keyed like `handle_privacy_token_notification`: the stanza's `sender_lid` when it
  really is a LID, else the `from` resolved through `storage_jid/2`.

  A token with no `t` attribute is ignored rather than stored — `expired?/1` treats a
  missing timestamp as expired, so storing one would only occupy the key and mask a
  later good token. Skips a token no newer than what we hold (`>=`, as
  `store_history_sync/2` does, not the strict `>` of `store_token/3`: a replayed
  stanza is not a genuine reissue).
  """
  @spec store_message_node(Conn.t(), Node.t()) :: :ok
  def store_message_node(conn, %Node{} = node) do
    with %Node{attrs: token_attrs, content: token} when is_binary(token) <-
           NodeUtils.get_binary_node_child(node, "tctoken"),
         t when is_binary(t) <- Map.get(token_attrs, "t"),
         {ts, ""} <- Integer.parse(t),
         from when is_binary(from) <- NodeUtils.get_attr(node, "from"),
         true <- regular_user?(JID.jid_normalized_user(from)) do
      key = message_token_key(conn, node, from)
      existing = read(conn, key)
      existing_ts = if is_map(existing), do: Map.get(existing, :timestamp, 0) || 0, else: 0

      unless existing_ts > 0 and existing_ts >= ts do
        write(conn, key, Map.merge(entry_map(existing), %{token: token, timestamp: ts}))
      end
    else
      _ -> :ok
    end

    :ok
  end

  # `sender_lid` wins when present and genuinely a LID; otherwise fall back to the
  # stanza `from`, which `storage_jid/2` maps through the LID mapping the same way
  # every other token source does.
  defp message_token_key(conn, node, from) do
    with lid when is_binary(lid) <- NodeUtils.get_attr(node, "sender_lid"),
         user = JID.jid_normalized_user(lid),
         true <- JID.lid_user?(user) do
      user
    else
      _ -> storage_jid(conn, from)
    end
  end

  # Baileys' `isRegularUser` / WA Web's `Wid.isRegularUser()`: a real person, so not
  # the PSA pseudo-contact (`0@`), not a bot by phone pattern, not Meta AI. Gates
  # capture so a system-originated stanza cannot write a token under a nonsense key.
  defp regular_user?(jid) do
    user = jid |> String.split("@", parts: 2) |> hd()

    user != "0" and not JID.jid_bot?(jid) and not JID.jid_meta_ai?(jid) and
      (JID.jid_user?(jid) or String.ends_with?(jid, "@c.us"))
  end

  @doc """
  Persist the tokens a history-sync blob carried — ported from Baileys'
  `storeTcTokensFromHistorySync` (`Utils/process-message.ts`). Each entry is
  `%{jid, token, timestamp, sender_timestamp}` as decoded by
  `Amarula.Protocol.Messages.HistorySync`; `sender_timestamp` may be `nil`.

  This is the bulk source of tokens. Without it a freshly linked device starts
  with an empty store and has to earn a token per contact the slow way — one
  rejected send (ack `463`) and one issuance IQ each — even though the phone
  just handed us every token it holds.

  Skips an entry whose stored timestamp is already **greater than or equal to**
  the incoming one. Note the `>=`: `store_token/3` uses a strict `>` because a
  same-second reissue there is genuinely newer, whereas a history blob only ever
  replays what we may already hold. Best-effort — a storage failure on one entry
  never aborts the rest, since this runs on the history-sync path, not a send.
  """
  @spec store_history_sync(Conn.t(), [map()]) :: :ok
  def store_history_sync(conn, entries) when is_list(entries) do
    Enum.each(entries, &store_history_entry(conn, &1))
  end

  defp store_history_entry(conn, %{jid: jid, token: token, timestamp: ts} = entry)
       when is_binary(jid) and is_binary(token) and is_integer(ts) do
    key = storage_jid(conn, jid)
    existing = read(conn, key)

    unless is_map(existing) and Map.get(existing, :timestamp, 0) >= ts do
      fields = %{token: token, timestamp: ts}

      fields =
        case Map.get(entry, :sender_timestamp) do
          sender_ts when is_integer(sender_ts) -> Map.put(fields, :sender_timestamp, sender_ts)
          _ -> fields
        end

      write(conn, key, Map.merge(entry_map(existing), fields))
    end
  end

  defp store_history_entry(_conn, _entry), do: :ok

  defp store_tokens(_conn, nil, _fallback_jid), do: :ok

  defp store_tokens(conn, result_node, fallback_jid) do
    case NodeUtils.get_binary_node_child(result_node, "tokens") do
      nil ->
        :ok

      tokens_node ->
        tokens_node
        |> NodeUtils.get_binary_node_children("token")
        |> Enum.each(&store_token(conn, &1, fallback_jid))
    end
  end

  defp store_token(conn, %Node{attrs: attrs, content: content}, fallback_jid)
       when is_binary(content) do
    with "trusted_contact" <- Map.get(attrs, "type"),
         t when is_binary(t) <- Map.get(attrs, "t"),
         {ts, ""} <- Integer.parse(t),
         raw_jid when is_binary(raw_jid) <- fallback_jid || Map.get(attrs, "jid") do
      key = storage_jid(conn, raw_jid)
      existing = read(conn, key)

      # Never let a stale reply clobber a newer token for the same contact.
      unless is_map(existing) and Map.get(existing, :timestamp, 0) > ts do
        write(conn, key, Map.merge(entry_map(existing), %{token: content, timestamp: ts}))
      end
    else
      _ -> :ok
    end
  end

  defp store_token(_conn, _token_node, _fallback_jid), do: :ok

  defp record_issued(conn, jid, issued_at) do
    key = storage_jid(conn, jid)
    existing = entry_map(read(conn, key))
    write(conn, key, Map.put(existing, :sender_timestamp, issued_at))
  end

  # --- expiry / bucketing (mirrors tc-token-utils.ts) ---

  defp expired?(ts) when is_integer(ts), do: bucket(now()) - bucket(ts) >= @num_buckets
  defp expired?(_ts), do: true

  defp bucket(unix_ts), do: div(unix_ts, @bucket_seconds)

  defp now, do: System.system_time(:second)

  # --- storage (mirrors LidMappingFileStore's read/write pattern) ---

  # A stored entry to merge onto. The read path already degrades gracefully on a
  # corrupt record; the write paths must too — `Map.merge/2` raises on a truthy
  # non-map, and the `privacy_token` notification writes from the Connection
  # process itself, so a corrupt entry would take the connection down.
  defp entry_map(entry) when is_map(entry), do: entry
  defp entry_map(_), do: %{}

  # The jid we ISSUE against — Baileys `resolveIssuanceJid`. With
  # `lidTrustedTokenIssueToLid` off (the default this module follows) a LID target
  # is issued against its PN, so a LID-addressed contact gets a usable token
  # instead of one the server can't match. Falls back to the LID when we hold no
  # mapping. NOTE: this is the *storage* direction inverted — `storage_jid/2`
  # prefers the LID, issuance prefers the PN.
  defp issuance_jid(conn, jid) do
    user = JID.jid_normalized_user(jid)

    with true <- JID.lid_user?(user),
         pn when is_binary(pn) <- LidMappingFileStore.pn_for_lid(conn, user) do
      JID.encode(%{user: pn, server: "s.whatsapp.net"})
    else
      _ -> user
    end
  end

  # WA Web stores tctoken state under the account-level LID JID when one is
  # known, exactly like Signal sessions (LidMappingFileStore.signal_address/2).
  # Keep the server suffix: notification tokens arrive keyed by `@lid`, and
  # dropping it here made PN sends look under a different storage key.
  defp storage_jid(conn, jid) do
    user = JID.jid_normalized_user(jid)

    cond do
      JID.lid_user?(user) ->
        user

      lid_user = LidMappingFileStore.lid_for_pn(conn, user) ->
        JID.encode(%{user: lid_user, server: "lid"})

      true ->
        user
    end
  end

  defp read(%Conn{storage: scope, profile: profile}, key),
    do: read(scope, profile, key)

  defp read(scope, profile, key),
    do: Storage.fetch(scope, profile, :tctoken, key)

  defp write(%Conn{storage: scope, profile: profile}, key, value),
    do: Storage.put(scope, profile, :tctoken, key, value)
end
