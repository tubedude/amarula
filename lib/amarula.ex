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
        {:whatsapp, :connection_update, %{qr: qr}} when is_binary(qr) ->
          IO.puts(qr)   # render this string as a QR code
      end

      # 3. Once linked you get an :open update — now you can send.
      receive do
        {:whatsapp, :connection_update, %{connection: :open}} -> :ready
      end

      Amarula.send_text(conn, "5511999999999@s.whatsapp.net", "hello from Elixir!")

  `:profile` names this account's stored credentials, so the next run reconnects
  without a new QR. `Amarula.new/1` fills in all protocol defaults; you usually
  pass only `:profile`. For a ready-made supervised wrapper, see
  `Amarula.Examples.Connection`.

  ## The QR code

  The `qr` in a `:connection_update` is a plain string — *you* turn it into a
  scannable image, with whatever you like (a terminal renderer, an `eqrcode`
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
  it as-is — don't reformat the string. Example with `eqrcode`:

      {:whatsapp, :connection_update, %{qr: qr}} when is_binary(qr) ->
        qr |> EQRCode.encode() |> EQRCode.png() |> then(&File.write!("qr.png", &1))

  ## Addressing

  A send target is a wire jid string — `"<number>@s.whatsapp.net"` for a person,
  `"<id>@g.us"` for a group — or an `Amarula.Address` (use `Amarula.Address.pn/1`
  to build one from a bare number).

  ## Sending

  All sends return `{:ok, msg_id}` or `{:error, reason}`:

      Amarula.send_text(conn, jid, "hello")
      Amarula.send_media(conn, :image, jid, image_bytes, caption: "hi")
      Amarula.send_reaction(conn, message_key, "👍")   # "" removes the reaction
      Amarula.send_edit(conn, message_key, "fixed typo")
      Amarula.send_revoke(conn, message_key)            # delete for everyone

  A `message_key` is the `key` field of a message you received (see below) —
  that's how you point a reaction/edit/delete at a specific message.

  ## Receiving

  Incoming events arrive at `parent_pid` as `{:whatsapp, type, data}` tuples (the
  full list is in `t:event/0`). The main one is `:messages_upsert`, whose `data`
  carries `[%Amarula.Msg{}]` — the consumer-friendly message view (`type` +
  `content`), never the raw protobuf. Match on `msg.type`; for media, fetch the
  bytes lazily with `download_media/1`.
  """

  alias Amarula.Protocol.Messages.Media
  alias Amarula.Protocol.Proto
  alias Amarula.Protocol.Socket

  @typedoc "A connection handle: the pid from `connect/2` (or a registered name)."
  @type conn :: GenServer.server()

  @typedoc ~S|A send target: an `Amarula.Address` or a wire jid string (`"<n>@s.whatsapp.net"` / `"<id>@g.us"`).|
  @type jid :: String.t() | Amarula.Address.t()

  @typedoc "The key of a specific message (for reactions/edits/deletes)."
  @type message_key :: Proto.MessageKey.t()

  @typedoc "Result of a send: the assigned message id, or an error."
  @type send_result :: {:ok, msg_id :: String.t()} | {:error, term()}

  @typedoc "A media kind handled by `send_media/5`."
  @type media_type :: :image | :video | :audio | :document | :sticker

  @typedoc """
  Events delivered to `parent_pid` as `{:whatsapp, type, data}`:

    * `:connection_update` — `%{connection: state, qr: qr | nil, ...}` (partial map)
    * `:messages_upsert`   — `%{from: jid, id: id, messages: [%Amarula.Msg{}]}`
    * `:chats_update`      — `[%Amarula.Chat{}]` (from history/app-state sync)
    * `:contacts_update`   — `[%Amarula.Contact{}]`
    * `:group_update`      — `%{group: Address, author: Address | nil, action: ..}`
      a group membership/metadata change (participant add/remove/promote/demote,
      subject, announce, lock — see `Amarula.Protocol.Groups.Notification`)
    * `:receipt_update`    — `%{message_ids, from, participant, status, timestamp}`
      a message we sent was delivered/read/played (`Amarula.Protocol.Messages.Receipt`)
    * `:blocklist_update`  — `[%{jid, action}]` block/unblock changes
    * `:pairing_success`   — `%{jid: jid, lid: lid, platform: platform}`
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
          | :blocklist_update
          | :pairing_success
          | :error

  @doc """
  Build a connection value (`Amarula.Conn`) from `config`, without starting it.

  This is the start of the Req-style builder: attach plugins, then `connect/2`.

      Amarula.new(%{profile: :primary})
      |> MyPlugin.attach(opts)
      |> Amarula.connect()

  Connection/protocol defaults are filled in (see `Amarula.Config`), so `config`
  need only carry `:profile` (+ `:auth` and any overrides).
  """
  @spec new(map()) :: Amarula.Conn.t()
  def new(config) when is_map(config) do
    config |> Amarula.Config.merge() |> Amarula.Conn.new()
  end

  @doc """
  Start a built `Amarula.Conn` and begin connecting. Returns the running `conn`
  handle (a pid). Pair with `new/1`:

      {:ok, pid} = Amarula.new(config) |> Amarula.connect()

  `opts`:
    * `:parent_pid` — process to receive `{:whatsapp, ..}` events (default: caller)
    * `:name`       — optional registered name for the connection
  """
  @spec connect(Amarula.Conn.t(), keyword()) :: {:ok, conn()} | {:error, term()}
  def connect(%Amarula.Conn{} = conn, opts \\ []) do
    with {:ok, pid} <- Socket.make_socket(conn, opts),
         :ok <- Socket.connect(pid) do
      {:ok, pid}
    end
  end

  @doc "Disconnect the connection. Returns `:ok | {:error, reason}`."
  @spec disconnect(conn()) :: :ok | {:error, term()}
  defdelegate disconnect(conn), to: Socket

  @doc """
  Log out / forget this connection: unlink the companion on WhatsApp's side (the
  phone drops the device) and wipe all local storage for its profile, then
  disconnect. After this the profile must be re-paired to use again.
  """
  @spec logout(conn()) :: :ok
  defdelegate logout(conn), to: Socket

  @doc "Current connection state (e.g. `:disconnected`, `:connecting`, `:connected`)."
  @spec connection_state(conn()) :: atom()
  defdelegate connection_state(conn), to: Socket, as: :get_connection_state

  @doc "Send a 1:1/group text message to `jid`."
  @spec send_text(conn(), jid(), String.t()) :: send_result()
  defdelegate send_text(conn, jid, text), to: Socket

  @doc "Set your global presence: `:available` (online) or `:unavailable`. Needs a profile name."
  @spec set_presence(conn(), :available | :unavailable) :: :ok | {:error, term()}
  defdelegate set_presence(conn, type), to: Socket

  @doc "Send a typing indicator to `jid`: `:composing`, `:recording`, or `:paused`."
  @spec send_chatstate(conn(), jid(), :composing | :recording | :paused) :: :ok
  defdelegate send_chatstate(conn, jid, type), to: Socket

  @doc "Subscribe to a contact's presence updates."
  @spec presence_subscribe(conn(), jid()) :: :ok
  defdelegate presence_subscribe(conn, jid), to: Socket

  @doc """
  Send a read receipt for `message_ids` in chat `jid` (pass `participant` for a
  group sender). Marks those messages read on the sender's side.
  """
  @spec mark_read(conn(), [String.t(), ...], jid(), jid() | nil) :: :ok
  def mark_read(conn, message_ids, jid, participant \\ nil),
    do: Socket.mark_read(conn, message_ids, jid, participant)

  @doc "Send a pre-built `%Proto.Message{}` to `jid`."
  @spec send_message(conn(), jid(), Proto.Message.t()) :: send_result()
  defdelegate send_message(conn, jid, message), to: Socket

  @doc """
  Send a poll to `jid`. Returns `{:ok, msg_id, message_secret}` — keep the
  `message_secret` to tally incoming votes (`Amarula.Protocol.Messages.Poll`).
  `opts`: `:selectable` (max picks, default 1), `:announcement`, `:message_secret`.
  """
  @spec send_poll(conn(), jid(), String.t(), [String.t(), ...], keyword()) ::
          {:ok, String.t(), binary()} | {:error, term()}
  def send_poll(conn, jid, name, options, opts \\ []),
    do: Socket.send_poll(conn, jid, name, options, opts)

  @doc "Send a contact (`display_name` + vCard string) to `jid`."
  @spec send_contact(conn(), jid(), String.t(), String.t()) :: send_result()
  defdelegate send_contact(conn, jid, display_name, vcard), to: Socket

  @doc "Send multiple contacts to `jid`: `pairs` is `[{display_name, vcard}, ...]`."
  @spec send_contacts(conn(), jid(), String.t(), [{String.t(), String.t()}, ...]) :: send_result()
  defdelegate send_contacts(conn, jid, display_name, pairs), to: Socket

  @doc "Send a location to `jid`. `opts`: `:name`, `:address`, `:url`, `:is_live`."
  @spec send_location(conn(), jid(), float(), float(), keyword()) :: send_result()
  def send_location(conn, jid, lat, lng, opts \\ []),
    do: Socket.send_location(conn, jid, lat, lng, opts)

  @doc "Fetch a group's metadata (`%Amarula.Group{}`). `group` is an `Address` or jid."
  @spec group_metadata(conn(), jid()) :: {:ok, Amarula.Group.t()} | {:error, term()}
  defdelegate group_metadata(conn, group), to: Socket

  @doc "List all groups we participate in (`[%Amarula.Group{}]`)."
  @spec list_groups(conn()) :: {:ok, [Amarula.Group.t()]} | {:error, term()}
  defdelegate list_groups(conn), to: Socket

  ## Group management ----------------------------------------------------------
  #
  # `group` is a `@g.us` jid string (e.g. from group metadata). These build a
  # `w:g2` IQ via `Amarula.Protocol.Groups.Ops` and parse the reply.

  alias Amarula.Protocol.Groups.Ops, as: GroupOps

  @typedoc "Affected participant in a group op: `%{jid, status}` (status \"200\" = ok)."
  @type affected :: %{jid: String.t() | nil, status: String.t()}

  @doc """
  Create a group named `subject` with the given participant jids. Returns the new
  group's metadata.
  """
  @spec group_create(conn(), String.t(), [String.t()]) ::
          {:ok, Amarula.Group.t()} | {:error, term()}
  def group_create(conn, subject, participants) do
    Socket.group_op(conn, GroupOps.create(subject, participants), &group_meta_result/1)
  end

  @doc "Leave a group."
  @spec group_leave(conn(), String.t()) :: :ok | {:error, term()}
  def group_leave(conn, group) do
    Socket.group_op(conn, GroupOps.leave(group), &ok_result/1)
  end

  @doc "Change a group's subject (title)."
  @spec group_update_subject(conn(), String.t(), String.t()) :: :ok | {:error, term()}
  def group_update_subject(conn, group, subject) do
    Socket.group_op(conn, GroupOps.update_subject(group, subject), &ok_result/1)
  end

  @doc "Set (or clear, with `nil`/`\"\"`) a group's description."
  @spec group_update_description(conn(), String.t(), String.t() | nil) :: :ok | {:error, term()}
  def group_update_description(conn, group, description) do
    Socket.group_op(conn, GroupOps.update_description(group, description), &ok_result/1)
  end

  @doc """
  Add/remove/promote/demote participants. `action` is `:add`/`:remove`/`:promote`/
  `:demote`. Returns the affected participants with per-jid status.
  """
  @spec group_participants(conn(), String.t(), [String.t()], GroupOps.action()) ::
          {:ok, [affected()]} | {:error, term()}
  def group_participants(conn, group, participants, action) do
    Socket.group_op(conn, GroupOps.participants_update(group, participants, action), fn r ->
      r |> reply_node() |> GroupOps.parse_participants(action) |> reply_or_error(r)
    end)
  end

  @doc """
  Change a group setting: `:announcement`/`:not_announcement` (only admins post),
  `:locked`/`:unlocked` (only admins edit info).
  """
  @spec group_setting(conn(), String.t(), GroupOps.setting()) :: :ok | {:error, term()}
  def group_setting(conn, group, setting) do
    Socket.group_op(conn, GroupOps.setting_update(group, setting), &ok_result/1)
  end

  @doc "Who may add members: `:admin_add` (admins only) or `:all_member_add`."
  @spec group_member_add_mode(conn(), String.t(), :admin_add | :all_member_add) ::
          :ok | {:error, term()}
  def group_member_add_mode(conn, group, mode) do
    Socket.group_op(conn, GroupOps.member_add_mode(group, mode), &ok_result/1)
  end

  @doc "Turn join-approval (admin approves joiners) `:on`/`:off`."
  @spec group_join_approval_mode(conn(), String.t(), :on | :off) :: :ok | {:error, term()}
  def group_join_approval_mode(conn, group, mode) do
    Socket.group_op(conn, GroupOps.join_approval_mode(group, mode), &ok_result/1)
  end

  @doc "Toggle disappearing messages. `0` = off; otherwise seconds of expiration."
  @spec group_ephemeral(conn(), String.t(), non_neg_integer()) :: :ok | {:error, term()}
  def group_ephemeral(conn, group, expiration) do
    Socket.group_op(conn, GroupOps.toggle_ephemeral(group, expiration), &ok_result/1)
  end

  @doc "Fetch the group's invite code."
  @spec group_invite_code(conn(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def group_invite_code(conn, group) do
    Socket.group_op(conn, GroupOps.invite_code(group), fn r ->
      r |> reply_node() |> GroupOps.parse_invite_code() |> reply_or_error(r)
    end)
  end

  @doc "Revoke + regenerate the group's invite code. Returns the new code."
  @spec group_revoke_invite(conn(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def group_revoke_invite(conn, group) do
    Socket.group_op(conn, GroupOps.revoke_invite(group), fn r ->
      r |> reply_node() |> GroupOps.parse_invite_code() |> reply_or_error(r)
    end)
  end

  @doc "Join a group by invite `code`. Returns the joined group's jid."
  @spec group_accept_invite(conn(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def group_accept_invite(conn, code) do
    Socket.group_op(conn, GroupOps.accept_invite(code), fn r ->
      r |> reply_node() |> GroupOps.parse_accepted_jid() |> reply_or_error(r)
    end)
  end

  @doc "Look up group metadata from an invite `code` without joining."
  @spec group_invite_info(conn(), String.t()) :: {:ok, Amarula.Group.t()} | {:error, term()}
  def group_invite_info(conn, code) do
    Socket.group_op(conn, GroupOps.invite_info(code), &group_meta_result/1)
  end

  @doc "List pending join-approval requests (a list of attr maps)."
  @spec group_requests(conn(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def group_requests(conn, group) do
    Socket.group_op(conn, GroupOps.request_list(group), fn r ->
      r |> reply_node() |> GroupOps.parse_request_list() |> reply_or_error(r)
    end)
  end

  @doc "Approve/reject pending join requests for `participants`. `action` is `:approve`/`:reject`."
  @spec group_request_update(conn(), String.t(), [String.t()], :approve | :reject) ::
          {:ok, [affected()]} | {:error, term()}
  def group_request_update(conn, group, participants, action) do
    Socket.group_op(conn, GroupOps.request_update(group, participants, action), fn r ->
      r |> reply_node() |> GroupOps.parse_request_update(action) |> reply_or_error(r)
    end)
  end

  # --- group reply transforms (run in the connection process) ---

  # A reply is {:ok, node} | {:error, node}; pull the node (parsers take a node).
  defp reply_node({:ok, node}), do: node
  defp reply_node({:error, node}), do: node

  # Pass a parser's {:ok,_}/{:error,_} through, but if the IQ itself errored,
  # surface the {:group_op_failed, code, text} from the <error> node instead.
  defp reply_or_error(_parsed, {:error, node}), do: {:error, iq_error(node)}
  defp reply_or_error(parsed, {:ok, _node}), do: parsed

  defp ok_result({:ok, _node}), do: :ok
  defp ok_result({:error, node}), do: {:error, iq_error(node)}

  defp group_meta_result({:ok, node}) do
    with {:ok, meta} <- Amarula.Protocol.Groups.Metadata.parse(node),
         do: {:ok, Amarula.Group.from_metadata(meta)}
  end

  defp group_meta_result({:error, node}), do: {:error, iq_error(node)}

  # Extract {:group_op_failed, code, text} from an error IQ's <error> child.
  defp iq_error(%Amarula.Protocol.Binary.Node{} = node) do
    case Amarula.Protocol.Binary.NodeUtils.get_binary_node_child(node, "error") do
      %Amarula.Protocol.Binary.Node{} = err ->
        {:group_op_failed, Amarula.Protocol.Binary.NodeUtils.get_attr(err, "code"),
         Amarula.Protocol.Binary.NodeUtils.get_attr(err, "text")}

      _ ->
        {:error, node}
    end
  end

  defp iq_error(other), do: other

  ## Replies / quoted messages -----------------------------------------------

  @doc """
  Look up a recently-received message by id in the in-memory cache. Returns an
  `%Amarula.Msg{}` or `nil` (evicted / never seen). Best-effort — for a guaranteed
  fetch use `resolve_quoted/2`, which falls back to asking the server.
  """
  @spec get_message(conn(), String.t()) :: Amarula.Msg.t() | nil
  defdelegate get_message(conn, msg_id), to: Socket

  @doc """
  Ask the phone to re-deliver a message by key (a PEER_DATA_OPERATION
  placeholder-resend). The message arrives **asynchronously** later via the normal
  `:messages_upsert` event (and is cached). Returns `{:ok, request_msg_id}`.
  """
  @spec request_resend(conn(), message_key()) :: send_result()
  defdelegate request_resend(conn, message_key), to: Socket

  @doc """
  Resolve the original message a reply quotes, in three tiers:

    1. the inline copy WhatsApp ships in the reply (`msg.quoted.message`) — instant;
    2. the received-message cache (`get_message/2`) — instant if still cached;
    3. otherwise ask the server (`request_resend/2`) — the original re-arrives async
       via `:messages_upsert`.

  Returns `{:ok, %Amarula.Msg{}}` for tiers 1–2, `{:requested, request_msg_id}` for
  tier 3 (watch for it on the event stream), or `{:error, :not_a_reply}`.
  """
  @spec resolve_quoted(conn(), Amarula.Msg.t()) ::
          {:ok, Amarula.Msg.t()} | {:requested, String.t()} | {:error, term()}
  def resolve_quoted(_conn, %Amarula.Msg{quoted: nil}), do: {:error, :not_a_reply}

  def resolve_quoted(conn, %Amarula.Msg{quoted: %{id: id} = q} = msg) do
    cond do
      match?(%Amarula.Msg{}, q.message) -> {:ok, q.message}
      cached = get_message(conn, id) -> {:ok, cached}
      true -> {:requested, request_resend_for_quoted(conn, msg)}
    end
  end

  # Build the MessageKey for the quoted original + ask the server to re-deliver it.
  defp request_resend_for_quoted(conn, %Amarula.Msg{quoted: q} = msg) do
    key = %Proto.MessageKey{
      remoteJid: Amarula.Address.to_wire(q.chat || msg.chat),
      id: q.id,
      participant: q.participant && Amarula.Address.to_wire(q.participant)
    }

    case request_resend(conn, key) do
      {:ok, request_id} -> request_id
      _ -> nil
    end
  end

  @doc "React to a message with `emoji` (empty string removes the reaction)."
  @spec send_reaction(conn(), message_key(), String.t()) :: send_result()
  defdelegate send_reaction(conn, target_key, emoji), to: Socket

  @doc "Edit a message we sent, replacing its text."
  @spec send_edit(conn(), message_key(), String.t()) :: send_result()
  defdelegate send_edit(conn, target_key, new_text), to: Socket

  @doc "Delete a message for everyone (revoke)."
  @spec send_revoke(conn(), message_key()) :: send_result()
  defdelegate send_revoke(conn, target_key), to: Socket

  @doc """
  Send media of `type` (`:image`/`:video`/`:audio`/`:document`/`:sticker`).
  `opts` may carry `:mimetype`, `:caption`, `:width`, `:height`, `:seconds`,
  `:ptt`, `:file_name`, `:title`.
  """
  @spec send_media(conn(), media_type(), jid(), binary(), keyword()) :: send_result()
  defdelegate send_media(conn, type, jid, data, opts \\ []), to: Socket

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
end
