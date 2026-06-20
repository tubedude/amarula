defmodule Amarula do
  @moduledoc """
  Amarula — a WhatsApp Web client for Elixir.

  Connect to WhatsApp the way the web/desktop app does: pair once by scanning a
  QR code with your phone, then send and receive messages from Elixir. Every call
  takes a `conn` handle, so you can run many accounts at once — there is no global
  connection.

  ## Quick start

  Pair a device (first run), then send a message:

      # 1. Start a connection. Events (the QR code, incoming messages) are sent
      #    to `parent_pid` — here, the current process.
      {:ok, conn} =
        Amarula.new(%{profile: :me})
        |> Amarula.connect(parent_pid: self())

      # 2. On the first run you get a QR code to scan with your phone:
      #    WhatsApp → Settings → Linked Devices → Link a device.
      receive do
        {:amarula, :connection_update, %{qr: qr}} when is_binary(qr) ->
          IO.puts(qr)   # render this string as a QR code
      end

      # 3. Once linked you get an :open update — now you can send.
      receive do
        {:amarula, :connection_update, %{connection: :open}} -> :ready
      end

      Amarula.send_text(conn, "5511999999999@s.whatsapp.net", "hello from Elixir!")

  `:profile` names this account's stored credentials, so the next run reconnects
  without a new QR. `Amarula.new/1` fills in all protocol defaults; you usually
  pass only `:profile`. For a ready-made supervised wrapper, see
  `Amarula.Examples.Connection`.

  ## Testing your bot

  To test your message-handling logic without a real WhatsApp connection, use
  `Amarula.Testing` — it starts an offline connection and lets you deliver
  synthetic inbound messages that flow through the real receive pipeline.

  ## The QR code

  The `qr` in a `:connection_update` is a plain string — *you* turn it into a
  scannable image, with whatever you like (a terminal renderer, a `qr_code`
  PNG, an HTML `<img>`, …). There is no built-in renderer and no login-phase
  plugin hook: rendering is entirely the consumer's, via this event. (The
  handshake/pairing crypto is deliberately closed to plugins — the send/receive
  pipelines run only *after* a message is decrypted.)

  The string is four comma-separated fields:

      "<ref>,<noiseKeyB64>,<identityKeyB64>,<advSecretKeyB64>"

    * `ref` — a server-issued pairing reference (from the `<pair-device>` IQ); it
      rotates every ~20s, so each rotation emits a fresh `:connection_update` with
      a new `qr` — re-render on each.
    * `noiseKeyB64` — our Noise static public key (base64).
    * `identityKeyB64` — our signed identity public key (base64).
    * `advSecretKeyB64` — the companion adv secret key (base64).

  The phone reads our public keys + ref from the image to link the device. Render
  it as-is — don't reformat the string. Example with `qr_code` (note its API is
  `Result`-tuple based — `create/1` returns `{:ok, qr}` and `render/2` takes that
  tuple, so you pipe straight through):

      {:amarula, :connection_update, %{qr: qr}} when is_binary(qr) ->
        qr |> QRCode.create() |> QRCode.render(:png) |> QRCode.save("qr.png")

  ## Addressing

  A send target is a jid string — `"<number>@s.whatsapp.net"` for a person,
  `"<id>@g.us"` for a group — or an `Amarula.Address` (use `Amarula.Address.pn/1`
  to build one from a bare number).

  ## Sending

  All sends return `{:ok, msg_id}` or `{:error, reason}`:

      Amarula.send_text(conn, jid, "hello")
      Amarula.send_media(conn, jid, :image, image_bytes, caption: "hi")
      Amarula.send_reaction(conn, message_key, "👍")   # "" removes the reaction
      Amarula.send_edit(conn, message_key, "fixed typo")
      Amarula.send_revoke(conn, message_key)            # delete for everyone

  A `message_key` is the `key` field of a message you received (see below) —
  that's how you point a reaction/edit/delete at a specific message.

  ## Receiving

  Incoming events arrive at `parent_pid` as `{:amarula, type, data}` tuples (the
  full list is in `t:event/0`). The main one is `:messages_upsert`, whose `data`
  carries `[%Amarula.Msg{}]` — the consumer-friendly message view (`type` +
  `content`), never the raw protobuf. Match on `msg.type`; for media, fetch the
  bytes lazily with `download_media/1`.

  ## What Amarula does NOT store

  Amarula keeps only what the *protocol* needs (credentials, Signal sessions,
  device/LID mappings). It is **not** a message archive and keeps **no chat or
  DM list**: there is no "list my conversations" call, and incoming messages are
  delivered once via `:messages_upsert` and then forgotten. If your app needs an
  inbox, a contact list, or scrollback, persist it yourself from the events —
  Amarula won't do it for you.

  History *sync* (`:history_sync` events, and `fetch_history/4` to pull more on
  demand) delivers WhatsApp's own history to you the same way — as events to
  store, not a queryable archive Amarula maintains. `resolve_quoted/2` is the one
  read-back helper, and only for a reply's quoted message you still hold.
  """

  alias Amarula.Connection
  alias Amarula.ProfileRegistry
  alias Amarula.Protocol.Messages.{Media, MessageEncoder}
  alias Amarula.Protocol.Proto

  # A send blocks the caller until the per-recipient sender finishes (up to three
  # IQ round-trips for a new recipient); the call timeout must exceed that worst
  # case. Mirrors Connection's own bound — the facade calls the process directly.
  @send_call_timeout 90_000

  @typedoc """
  A connection handle: the pid from `connect/2`, a registered name, or the `:via`
  tuple from `via/1` (resolve a profile to a restart-safe handle with `whereis/1`).
  """
  @type conn :: GenServer.server()

  @typedoc "A connection's profile name (its identity + storage scope)."
  @type profile :: atom() | String.t()

  @typedoc ~S|A send target: an `Amarula.Address` or a jid string (`"<n>@s.whatsapp.net"` / `"<id>@g.us"`).|
  @type jid :: String.t() | Amarula.Address.t()

  @typedoc """
  A reference to a specific existing message (for reactions / edits / deletes /
  poll votes). Either:

    * the `%Amarula.Msg{}` you received (carries its chat, sender, id), or
    * a `{jid, msg_id}` tuple — the chat `jid` plus the message id string.

  Both are self-contained. (Quote *replies* use the `:quoted` opt on `send_text`,
  which takes the `%Amarula.Msg{}` directly.)
  """
  @type message_ref :: Amarula.Msg.t() | {jid(), String.t()}

  @typedoc "A raw message key — used by the low-level on-demand history request."
  @type message_key :: Proto.MessageKey.t()

  @typedoc "Result of a send: the assigned message id, or an error."
  @type send_result :: {:ok, msg_id :: String.t()} | {:error, term()}

  @typedoc "A media kind handled by `send_media/5`."
  @type media_type :: :image | :video | :audio | :document | :sticker

  @typedoc """
  Events delivered to `parent_pid` as `{:amarula, type, data}`:

    * `:connection_update` — `%{connection: state, qr: qr | nil, ...}` (partial map)
    * `:messages_upsert`   — `%{from: jid, id: id, messages: [%Amarula.Msg{}]}`
    * `:chats_update`      — `[%Amarula.Chat{}]` (from history/app-state sync)
    * `:contacts_update`   — `[%Amarula.Contact{}]`
    * `:group_update`      — `%{group: Address, author: Address | nil, action: ..}`
      a group membership/metadata change (participant add/remove/promote/demote,
      subject, announce, lock — see `Amarula.Protocol.Groups.Notification`)
    * `:receipt_update`    — `%{message_ids, from, participant, status, timestamp}`
      a message we sent was delivered/read/played (`Amarula.Protocol.Messages.Receipt`)
    * `:presence_update`   — `%{jid: Address, participant: Address, presence, last_seen}`
      a contact/group member's presence (`:available`/`:unavailable`) or typing
      state (`:composing`/`:recording`) — `Amarula.Protocol.Presence`
    * `:blocklist_update`  — `[%{jid, action}]` block/unblock changes
    * `:pairing_code`      — `%{code: code}` the 8-char link-code (phone-number)
      pairing code to display (from `request_pairing_code/3`)
    * `:pairing_success`   — `%{jid, lid, platform}` (QR) or `%{via: :link_code}`
      (phone-number pairing)
    * `:history_sync`      — a batch of synced history (chats/contacts/messages)
      delivered asynchronously after connect (`Amarula.Protocol.Messages.HistorySync`)
    * `:error`             — a connection error term

  Credentials are persisted by Amarula itself (scoped to the connection's
  `:profile`), so there is no `:creds_update` to handle — name a profile and the
  next connect reloads its creds automatically.
  """
  @type event ::
          :connection_update
          | :messages_upsert
          | :chats_update
          | :contacts_update
          | :group_update
          | :receipt_update
          | :presence_update
          | :blocklist_update
          | :pairing_code
          | :pairing_success
          | :history_sync
          | :error

  @doc """
  Build a connection value (`Amarula.Conn`) from `config`, without starting it.

  This is the start of the Req-style builder: attach plugins, then `connect/2`.

      Amarula.new(%{profile: :primary})
      |> MyPlugin.attach(opts)
      |> Amarula.connect()

  Connection/protocol defaults are filled in (see `Amarula.Config`), so `config`
  need only carry `:profile` (+ `:auth` and any overrides).

  ## Offline (sandbox) mode

  `offline: true` runs the connection with no socket: it never reaches WhatsApp,
  and every `send_*` short-circuits to `{:ok, msg_id}` without encrypting or
  emitting a frame. Combined with `Amarula.Testing.deliver_*` (which feeds
  synthetic inbound messages), this lets you run your bot end to end — receive a
  message, reply to it — with no real-world effect. See `Amarula.Testing`.
  """
  @spec new(map()) :: Amarula.Conn.t()
  def new(config) when is_map(config) do
    config |> Amarula.Config.merge() |> Amarula.Conn.new()
  end

  @doc """
  Start a built `Amarula.Conn` and begin connecting. Returns the running `conn`
  handle (a pid). Pair with `new/1`:

      {:ok, pid} = Amarula.new(config) |> Amarula.connect()

  > #### The returned pid is not restart-safe {: .warning}
  >
  > A raw pid is returned on purpose — you can `Process.monitor/1` it to detect a
  > crash, or `Process.alive?/1` it. But if the connection crashes, its supervision
  > tree restarts it under a **new pid**, and the one returned here then points at a
  > dead process. So for anything you hold across time (a GenServer state field, a
  > long-lived process), store the **profile** and address the connection with
  > `via/1` instead:
  >
  >     conn = Amarula.via(profile)          # always resolves to the current pid
  >     Amarula.send_text(conn, jid, "hi")
  >
  > `via/1`/`whereis/1` resolve through `Amarula.ProfileRegistry`, which the
  > connection re-registers on every restart. The raw pid is fine for a quick,
  > short-lived script that won't outlive a crash.

  Only one connection per profile may run at a time (within the registry's reach —
  one per node by default; see `Amarula.ProfileRegistry`). Connecting a profile
  that's already live returns `{:error, {:already_running, pid}}` — use `whereis/1`
  to get the existing one.

  `opts`:
    * `:parent_pid` — process to receive `{:amarula, ..}` events (default: caller)
    * `:name`       — optional registered name for the connection
  """
  @spec connect(Amarula.Conn.t(), keyword()) ::
          {:ok, conn()} | {:error, {:already_running, pid()}} | {:error, term()}
  def connect(%Amarula.Conn{} = conn, opts \\ []) do
    with {:ok, pid} <- Connection.make_socket(conn, opts),
         :ok <- Connection.connect(pid) do
      {:ok, pid}
    end
  end

  @doc """
  The live connection pid for `profile`, or `nil`. A restart-safe handle: the pid
  changes if the connection restarts, but the profile resolves to the current one.

  Assumes the default `Amarula.ProfileRegistry`. With a custom `:registry` config,
  pass the `Conn` (or config) as the first arg: `whereis(conn, profile)`.
  """
  @spec whereis(profile()) :: pid() | nil
  def whereis(profile), do: ProfileRegistry.whereis(%{}, profile)

  @doc "As `whereis/1`, but resolves through `conn_or_config`'s `:registry`."
  @spec whereis(Amarula.Conn.t() | map(), profile()) :: pid() | nil
  defdelegate whereis(conn_or_config, profile), to: ProfileRegistry

  @doc """
  A `:via` handle for `profile` — usable anywhere a `conn()` is accepted, so calls
  route to whatever pid currently holds the profile (restart-safe). Assumes the
  default registry; for a custom one, build it from the `Conn` via
  `Amarula.ProfileRegistry.via/2`.
  """
  @spec via(profile()) :: {:via, module(), {atom(), profile()}}
  def via(profile), do: ProfileRegistry.via(%{}, profile)

  @doc """
  Close the connection's websocket without taking the supervision tree down.
  Pair with `reconnect/1` to bring it back up; use `stop/1` to release the
  profile entirely. Returns `:ok | {:error, reason}`.
  """
  @spec disconnect(conn()) :: :ok | {:error, term()}
  def disconnect(conn), do: GenServer.call(conn, :disconnect)

  @doc """
  (Re)open the connection's websocket on an already-started connection — the
  inverse of `disconnect/1`. Runs the handshake and logs in again with the
  profile's stored credentials. Returns `:ok | {:error, reason}`.
  """
  @spec reconnect(conn()) :: :ok | {:error, term()}
  def reconnect(conn), do: GenServer.call(conn, :connect)

  @doc """
  Stop a connection entirely — the whole supervision tree — and release its profile
  so it can be started again (here or, with a cluster registry, on another node).

  Unlike `disconnect/1` (which only closes the websocket; the supervised tree stays
  up and may reconnect), `stop/1` takes the tree down and frees the profile slot.
  Accepts a connection pid or a `profile` (resolved via the default registry).
  Returns `:ok | {:error, :not_found}`.
  """
  @spec stop(conn() | profile()) :: :ok | {:error, :not_found}
  def stop(pid) when is_pid(pid), do: Connection.stop(pid)

  def stop(profile) do
    case whereis(profile) do
      nil -> {:error, :not_found}
      pid -> Connection.stop(pid)
    end
  end

  @doc """
  Destructively forget this connection's profile: unlink the companion on
  WhatsApp's side (the phone drops the device), wipe **all** local storage for it
  (creds, sessions, keys, mappings), then disconnect. After this the profile must
  be re-paired to use again.

  For a non-destructive teardown that keeps the credentials, use `disconnect/1`
  (websocket only) or `stop/1` (the whole tree, freeing the profile slot).
  """
  @spec wipe_credentials(conn()) :: :ok | {:error, term()}
  def wipe_credentials(conn), do: GenServer.call(conn, :wipe_credentials)

  @doc """
  List every profile that has stored credentials in `storage`.

  Takes a storage source rather than a live connection: a `t:Amarula.Storage.Scope.t/0`,
  a built `%Amarula.Conn{}` (use its scope), or a `{adapter, opts}` / bare-opts
  storage spec (the same value `new/1` accepts as `:storage`). Returns the profile
  names that have a `:creds` entry — what you'd pass as `:profile` to reconnect.

      Amarula.list_profiles(root: "./amarula_data")
      #=> {:ok, [:primary, "work"]}

  `{:error, :not_supported}` if the storage adapter can't enumerate profiles.
  """
  @spec list_profiles(
          Amarula.Storage.Scope.t()
          | Amarula.Conn.t()
          | {module(), keyword()}
          | keyword()
        ) ::
          {:ok, [Amarula.Storage.profile()]} | {:error, term()}
  def list_profiles(%Amarula.Conn{storage: scope}), do: Amarula.Storage.list_profiles(scope)
  def list_profiles(%Amarula.Storage.Scope{} = scope), do: Amarula.Storage.list_profiles(scope)

  def list_profiles(storage_spec),
    do: Amarula.Storage.list_profiles(Amarula.Storage.scope(storage_spec))

  @doc """
  Like `list_profiles/1`, but each entry carries the logged-in identity read from
  that profile's stored creds — for building a friendlier account picker:

      Amarula.list_profiles_with_metadata(root: "./amarula_data")
      #=> {:ok, [%{profile: :primary, jid: "5511...@s.whatsapp.net",
      #           lid: "12345@lid", name: "Alice"}]}

  Costs one extra storage read per profile. `name`/`jid`/`lid` are `nil` for a
  profile that hasn't finished pairing. Accepts the same storage sources as
  `list_profiles/1`.
  """
  @spec list_profiles_with_metadata(
          Amarula.Storage.Scope.t()
          | Amarula.Conn.t()
          | {module(), keyword()}
          | keyword()
        ) :: {:ok, [Amarula.Storage.profile_info()]} | {:error, term()}
  def list_profiles_with_metadata(%Amarula.Conn{storage: scope}),
    do: Amarula.Storage.list_profiles_with_metadata(scope)

  def list_profiles_with_metadata(%Amarula.Storage.Scope{} = scope),
    do: Amarula.Storage.list_profiles_with_metadata(scope)

  def list_profiles_with_metadata(storage_spec),
    do: Amarula.Storage.list_profiles_with_metadata(Amarula.Storage.scope(storage_spec))

  @doc "Current connection state (e.g. `:disconnected`, `:connecting`, `:connected`)."
  @spec connection_state(conn()) :: atom()
  def connection_state(conn), do: GenServer.call(conn, :get_connection_state)

  ## Identity -----------------------------------------------------------------

  @doc """
  This connection's own identity as an `Amarula.Address` — our phone-number address,
  carrying our companion **device** id (`creds.me.id`).

  Always returns an `Address`: before login (no identity yet) it returns
  `Amarula.Address.empty/0`, so you never have to nil-check. `own_address(conn).device`
  is `nil` for the primary
  device / phone, or the linked-device number (e.g. `29`) for a companion like this app.

  Use it to detect messages this app/device itself sent — e.g. to ignore the agent's
  own self-chat sends and avoid a feedback loop. This does a call into the connection,
  and our own device is constant after login, so **read it once** and reuse the device:

      own_device = Amarula.own_address(conn).device

      # then, per received message:
      if msg.from_me and msg.from.device == own_device do
        :ignore   # this device sent it
      end
  """
  @spec own_address(conn()) :: Amarula.Address.t()
  def own_address(conn) do
    case conn |> GenServer.call(:get_auth_creds) |> get_in([:me, :id]) do
      id when is_binary(id) -> Amarula.Address.parse(id) || Amarula.Address.empty()
      _ -> Amarula.Address.empty()
    end
  end

  @doc """
  Whether `msg` is in our **own** chat (the "Message Yourself" chat): `from_me` and
  addressed `to` our own account. The check a self-chat command channel needs — drive
  an agent by messaging yourself.

  Handles the LID/PN duality: the self chat may be addressed by our PN or our LID, so it
  matches `msg.to` against both of our own identities (see `Amarula.Connection.own_chat?/2`).

  On a single connection there's no feedback loop — a reply this connection sends to the
  self chat is not delivered back to it (the sender's own device is excluded from
  delivery), so you don't need to filter your own sends. Dedupe by `msg_id` only when
  running two connections on the same account.
  """
  @spec own_chat?(conn(), Amarula.Msg.t()) :: boolean()
  def own_chat?(conn, msg), do: GenServer.call(conn, {:own_chat?, msg})

  @doc """
  Send a 1:1/group text message to `jid`. `opts`:

    * `:quoted` — reply to an `%Amarula.Msg{}` (threads the quote).
    * `:mentions` — list of jids/`%Amarula.Address{}` to tag (`@mention`).
  """
  @spec send_text(conn(), jid(), String.t(), keyword()) :: send_result()
  def send_text(conn, jid, text, opts \\ []),
    do: GenServer.call(conn, {:send_text, jid, text, opts}, @send_call_timeout)

  @doc "Set your global presence: `:available` (online) or `:unavailable`. Needs a profile name."
  @spec set_presence(conn(), :available | :unavailable) :: :ok | {:error, term()}
  def set_presence(conn, type), do: GenServer.call(conn, {:set_presence, type})

  @doc "Send a typing indicator to `jid`: `:composing`, `:recording`, or `:paused`."
  @spec send_chatstate(conn(), jid(), :composing | :recording | :paused) :: :ok
  def send_chatstate(conn, jid, type), do: GenServer.call(conn, {:send_chatstate, jid, type})

  @doc "Subscribe to a contact's presence updates."
  @spec subscribe_presence(conn(), jid()) :: :ok
  def subscribe_presence(conn, jid), do: GenServer.call(conn, {:presence_subscribe, jid})

  @doc """
  Request a link-code (phone-number) pairing code for `phone` (E.164 digits;
  any `+`, spaces, or dashes are stripped).

  Call this during the QR window while unregistered — on the first
  `:connection_update` carrying a `qr`. Returns `{:ok, code}` with an 8-char
  code the user types into WhatsApp → Linked Devices → "Link with phone number".
  Amarula finishes the handshake internally; the usual 515 restart then logs in
  (watch for `:pairing_success` then `connection: :open`). The same code is also
  delivered as a `:pairing_code` event.

  `opts`: `:custom_code` — a fixed 8-char code to use instead of a random one.
  """
  @spec request_pairing_code(conn(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def request_pairing_code(conn, phone, opts \\ []) do
    digits = String.replace(phone, ~r/\D/, "")
    GenServer.call(conn, {:request_pairing_code, digits, Keyword.get(opts, :custom_code)})
  end

  @doc """
  Send a read receipt for `message_ids` in chat `jid` (pass `participant` for a
  group sender). Marks those messages read on the sender's side.
  """
  @spec mark_read(conn(), jid(), [String.t(), ...], jid() | nil) :: :ok
  def mark_read(conn, jid, message_ids, participant \\ nil),
    do: GenServer.call(conn, {:mark_read, jid, message_ids, participant})

  @doc """
  Send a poll to `jid`. Returns `{:ok, msg_id, message_secret}` — keep the
  `message_secret` to tally incoming votes (`Amarula.Protocol.Messages.Poll`).
  `opts`: `:selectable` (max picks, default 1), `:announcement`, `:message_secret`.
  """
  @spec send_poll(conn(), jid(), String.t(), [String.t(), ...], keyword()) ::
          {:ok, String.t(), binary()} | {:error, term()}
  def send_poll(conn, jid, name, options, opts \\ []),
    do: GenServer.call(conn, {:send_poll, jid, name, options, opts}, @send_call_timeout)

  @doc """
  Cast a vote on an existing poll. `poll` is a `message_ref` for the poll-creation
  message (a `%Amarula.Msg{}` or `{jid, msg_id}` tuple); `message_secret` is the
  poll's 32-byte secret (from `send_poll/5`, or the poll's `messageContextInfo`);
  `option_names` are the chosen options. The vote is encrypted under the secret.

  The poll's creator is taken from the ref (a `%Amarula.Msg{}`'s sender, or the
  `{jid, _}` chat for a 1:1 poll). For a group poll referenced by tuple, pass the
  creator explicitly with `:creator` in `opts`.
  """
  @spec send_poll_vote(conn(), message_ref(), binary(), [String.t()], keyword()) :: send_result()
  def send_poll_vote(conn, poll, message_secret, option_names, opts \\ []) do
    {jid, key} = message_key(poll)
    creator = opts[:creator] |> resolve_creator(key)
    voter = Amarula.Address.to_jid!(own_address(conn))
    message = MessageEncoder.poll_vote(key, creator, voter, message_secret, option_names)
    send_built(conn, jid, message)
  end

  defp resolve_creator(nil, %Proto.MessageKey{participant: p}) when is_binary(p), do: p
  defp resolve_creator(nil, %Proto.MessageKey{remoteJid: jid}), do: jid
  defp resolve_creator(creator, _key), do: Amarula.Address.to_jid!(creator)

  @doc "Send a contact (`display_name` + vCard string) to `jid`."
  @spec send_contact(conn(), jid(), String.t(), String.t()) :: send_result()
  def send_contact(conn, jid, display_name, vcard),
    do: send_built(conn, jid, MessageEncoder.contact(display_name, vcard))

  @doc "Send multiple contacts to `jid`: `pairs` is `[{display_name, vcard}, ...]`."
  @spec send_contacts(conn(), jid(), String.t(), [{String.t(), String.t()}, ...]) :: send_result()
  def send_contacts(conn, jid, display_name, pairs),
    do: send_built(conn, jid, MessageEncoder.contacts(display_name, pairs))

  @doc "Send a location to `jid`. `opts`: `:name`, `:address`, `:url`, `:is_live`."
  @spec send_location(conn(), jid(), float(), float(), keyword()) :: send_result()
  def send_location(conn, jid, lat, lng, opts \\ []),
    do: send_built(conn, jid, MessageEncoder.location(lat, lng, opts))

  # Contacts, profile and groups live in their own modules:
  #   * `Amarula.Contacts` — on_whatsapp/2, fetch_status/2, resolve_lid/2
  #   * `Amarula.Profile`  — picture_url/3, update_picture/3, remove_picture/2, update_status/2
  #   * `Amarula.Group`    — create/3, leave/2, metadata/2, list/1, invites, requests, …

  ## Replies / quoted messages -----------------------------------------------

  @doc """
  Ask the phone for older history of a chat (a PEER_DATA_OPERATION on-demand
  request). `oldest_key` is the oldest message you already have, `oldest_ts` its
  millisecond timestamp, and `count` how many older messages to request. The
  history arrives **asynchronously** later via the normal `:history_sync` event.
  Returns `{:ok, request_msg_id}` or `{:error, :not_authenticated}`.
  """
  @spec fetch_history(conn(), message_key(), integer(), non_neg_integer()) :: send_result()
  def fetch_history(conn, oldest_key, oldest_ts, count),
    do: GenServer.call(conn, {:fetch_history, oldest_key, oldest_ts, count}, @send_call_timeout)

  @doc """
  Resolve the original message a reply quotes.

    1. If the reply carries the inline copy WhatsApp ships (`msg.quoted.message`),
       return it immediately — `{:ok, %Amarula.Msg{}}`.
    2. Otherwise ask the server to re-deliver the original — `{:requested, id}`;
       it re-arrives async via `:messages_upsert`.

  `{:error, :not_a_reply}` if `msg` doesn't quote anything.

  > Amarula does not keep an inbound-message store — delivery ends at
  > `:messages_upsert` (the message, its mentions, and the inline quote are all
  > there). If you want to resolve a quote from your own history, look it up in
  > whatever store you keep and skip this; this function only handles the inline
  > copy and the server round-trip.
  """
  @spec resolve_quoted(conn(), Amarula.Msg.t()) ::
          {:ok, Amarula.Msg.t()} | {:requested, String.t()} | {:error, term()}
  def resolve_quoted(_conn, %Amarula.Msg{quoted: nil}), do: {:error, :not_a_reply}

  def resolve_quoted(_conn, %Amarula.Msg{quoted: %{message: %Amarula.Msg{} = inline}}),
    do: {:ok, inline}

  def resolve_quoted(conn, %Amarula.Msg{quoted: q} = msg) do
    key = %Proto.MessageKey{
      remoteJid: Amarula.Address.to_jid!(q.channel || msg.channel),
      id: q.id,
      participant: q.from && Amarula.Address.to_jid!(q.from)
    }

    case GenServer.call(conn, {:request_resend, key}, @send_call_timeout) do
      {:ok, request_id} -> {:requested, request_id}
      {:error, _} = err -> err
    end
  end

  @doc """
  React to a message with `emoji` (empty string removes the reaction). `ref` is a
  `%Amarula.Msg{}` or a `{jid, msg_id}` tuple.
  """
  @spec send_reaction(conn(), message_ref(), String.t()) :: send_result()
  def send_reaction(conn, ref, emoji) do
    {jid, key} = message_key(ref)
    send_built(conn, jid, MessageEncoder.reaction(key, emoji))
  end

  @doc """
  Edit a message we sent, replacing its text. `ref` is a `%Amarula.Msg{}` or a
  `{jid, msg_id}` tuple.
  """
  @spec send_edit(conn(), message_ref(), String.t()) :: send_result()
  def send_edit(conn, ref, new_text) do
    {jid, key} = message_key(ref)
    send_built(conn, jid, MessageEncoder.edit(key, new_text))
  end

  @doc """
  Delete a message for everyone (revoke). `ref` is a `%Amarula.Msg{}` or a
  `{jid, msg_id}` tuple.
  """
  @spec send_revoke(conn(), message_ref()) :: send_result()
  def send_revoke(conn, ref) do
    {jid, key} = message_key(ref)
    send_built(conn, jid, MessageEncoder.revoke(key))
  end

  @doc """
  Send media of `type` (`:image`/`:video`/`:audio`/`:document`/`:sticker`).

  `data` is the **raw file bytes** — not a path, not base64. Read the file
  yourself first:

      bytes = File.read!("photo.jpg")
      Amarula.send_media(conn, jid, :image, bytes, caption: "hi")

  Amarula encrypts and uploads the bytes for you. `opts` may carry `:mimetype`
  (auto-detected per type if omitted), `:caption`, `:width`, `:height`,
  `:seconds`, `:ptt` (voice note), `:file_name`, `:title`.
  """
  @spec send_media(conn(), jid(), media_type(), binary(), keyword()) :: send_result()
  def send_media(conn, jid, type, data, opts \\ [])
      when type in [:image, :video, :audio, :document, :sticker] and is_binary(data),
      do: GenServer.call(conn, {:send_media, jid, type, data, opts}, @send_call_timeout)

  ## Receiving -----------------------------------------------------------------
  #
  # `:messages_upsert` events carry `[%Amarula.Msg{}]` — the consumer-friendly
  # message view (`type` + `content`), never the raw protobuf. See `Amarula.Msg`.

  @doc """
  Download + decrypt an incoming media file. Inbound messages carry only media
  *metadata* (directPath/mediaKey), not the bytes — call this to fetch them
  lazily, passing a `%Amarula.Msg{type: :media}` (or its `content.media` struct
  + kind). Returns `{:ok, bytes}` or `{:error, reason}` (`:bad_mac` on a failed
  integrity check).

      %Amarula.Msg{type: :media} = msg
      {:ok, bytes} = Amarula.download_media(msg)
  """
  @spec download_media(Amarula.Msg.t()) :: {:ok, binary()} | {:error, term()}
  def download_media(%Amarula.Msg{type: :media, content: %{kind: kind, media: m}}),
    do: Media.download(m, kind)

  def download_media(%Amarula.Msg{}), do: {:error, :not_media}

  @spec download_media(map(), media_type()) :: {:ok, binary()} | {:error, term()}
  def download_media(media_struct, type), do: Media.download(media_struct, type)

  # Send an already-built %Proto.Message{} to `jid`. The shared tail of the
  # message-building send helpers (contact/location/reaction/edit/revoke), which
  # construct a message and relay it as a {:send_message, ...} call.
  defp send_built(conn, jid, message),
    do: GenServer.call(conn, {:send_message, jid, message}, @send_call_timeout)

  # Resolve a public message_ref into the chat jid + the %Proto.MessageKey{} the
  # encoders need. A %Amarula.Msg{} carries everything (chat, sender, id, fromMe);
  # a {jid, msg_id} tuple builds the minimal key (no participant/fromMe known).
  defp message_key(%Amarula.Msg{} = msg) do
    jid = Amarula.Address.to_jid!(msg.channel)

    key = %Proto.MessageKey{
      remoteJid: jid,
      id: msg.id,
      fromMe: msg.from_me,
      participant: msg.from && Amarula.Address.to_jid!(msg.from)
    }

    {jid, key}
  end

  defp message_key({jid, msg_id}) when is_binary(msg_id) do
    jid = Amarula.Address.to_jid!(jid)
    {jid, %Proto.MessageKey{remoteJid: jid, id: msg_id, fromMe: false}}
  end
end
