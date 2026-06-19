defmodule Amarula.Examples.Connection do
  @moduledoc """
  A realistic way to embed Amarula in an OTP application: a `GenServer` that owns
  one WhatsApp connection.

  This is how you'd actually use the library — not a `receive` loop in a script.
  The process:

    * starts a connection with itself as `parent_pid`, so every
      `{:amarula, event, data}` arrives as a `handle_info/2`;
    * renders the QR on first pairing (Amarula persists credentials itself,
      scoped to `:profile`, so the next boot skips QR pairing — no creds handling);
    * surfaces incoming messages (here: just logs them — a real app would route
      them to your domain logic);
    * exposes a small API (`send_text/3`) that delegates to the owned connection.

  ## Run it (pairing + listen)

      iex -S mix
      iex> {:ok, _} = Amarula.Examples.Connection.start_link(name: :wa)
      # scan the QR printed to the terminal / /tmp/whatsapp_qr.txt
      iex> Amarula.Examples.Connection.send_text(:wa, Amarula.Address.pn("5511999999999"), "hi")
      # (a plain jid string works too)

  Credentials live under `AMARULA_AUTH_DIR` (default `./amarula_auth`); delete
  that directory to force a fresh pairing.

  In a real app you'd put this under your supervision tree:

      children = [{Amarula.Examples.Connection, name: MyApp.WhatsApp}]
      Supervisor.start_link(children, strategy: :one_for_one)

  ## Multiple accounts (profiles)

  There is no global connection, so you can run several in parallel — one process
  per WhatsApp identity. Give each a `:profile`: storage (creds, sessions, LID
  mappings, device lists) is then scoped to `<storage_root>/<profile>/`, so the
  accounts can't corrupt each other's Signal state:

      {:ok, _} = Connection.start_link(name: :primary, profile: :primary)
      {:ok, _} = Connection.start_link(name: :work, profile: :work)
      # → ./amarula_data/primary/  and  ./amarula_data/work/

  `:profile` goes into the connection **config** (storage is a config concern);
  the GenServer just forwards it. Without a profile it uses the legacy single
  dir (`AMARULA_AUTH_DIR`, default `./amarula_auth`) — unchanged.

  (Distinct devices only — two connections on the *same* identity get kicked by
  the server with a conflict error.)
  """

  use GenServer
  require Logger

  alias Amarula.Protocol.Auth.QRCodeGenerator
  alias Amarula.Protocol.Messages.{Poll, PollCrypto}

  # --- public API ---

  @doc """
  Start the connection process. `opts`:

    * `:name`    — registered name (so callers can address it; default: unregistered)
    * `:profile` — scopes storage to `<storage_root>/<profile>/`; run several
      accounts in parallel by giving each its own. Omit for the legacy single dir.
  """
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Send a text message to `to` (an `Amarula.Address` or a jid string)."
  @spec send_text(GenServer.server(), Amarula.Address.t() | String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def send_text(server, to, text), do: GenServer.call(server, {:send_text, to, text})

  @doc "The current connection state (`:connecting`, `:open`, …)."
  def state(server), do: GenServer.call(server, :connection_state)

  @doc "True once a history-sync has arrived (first-link sync complete)."
  def synced?(server), do: GenServer.call(server, :synced?)

  @doc "The underlying Amarula connection handle, for calling the `Amarula` API directly."
  def socket(server), do: GenServer.call(server, :socket)

  @doc "React to a message (used by e2e plugins)."
  def send_reaction(server, key, emoji),
    do: GenServer.call(server, {:send_reaction, key, emoji})

  @doc "Mark messages read (used by e2e plugins)."
  def mark_read(server, ids, from), do: GenServer.call(server, {:mark_read, ids, from})

  @doc """
  Send a poll to `jid` and remember it, so incoming votes are decrypted + tallied
  live in `handle_info` (demo of `Poll`/`PollCrypto`).
  """
  def start_poll(server, jid, name, options),
    do: GenServer.call(server, {:start_poll, jid, name, options})

  # --- GenServer ---

  @impl true
  def init(opts) do
    config = config(opts)
    profile = config.profile

    # parent_pid: self() routes every {:amarula, _, _} event to handle_info/2.
    # Attach any plugins (Req-style) before connecting; a plugin's opts get this
    # GenServer pid as :server so it can respond through us.
    {:ok, socket} =
      config
      |> Amarula.new()
      |> attach_plugins(Keyword.get(opts, :plugins, []))
      |> Amarula.connect(parent_pid: self())

    Logger.info("Amarula connection starting (profile=#{inspect(profile)})")

    {:ok,
     %{
       socket: socket,
       profile: profile,
       connection: :connecting,
       auto_read: Keyword.get(opts, :auto_read, false),
       # set true when a history-sync arrives (first-link sync done)
       synced: false,
       # set by start_poll: %{id, secret, message} for live vote tally
       poll: nil,
       # `{:phone, "<e164-digits>"}` to pair by phone number instead of QR
       pairing: Keyword.get(opts, :pairing),
       # guards a single request_pairing_code/3 call across QR rotations
       pairing_requested: false
     }}
  end

  @impl true
  def handle_call({:send_text, jid, text}, _from, state) do
    {:reply, Amarula.send_text(state.socket, jid, text), state}
  end

  def handle_call({:send_reaction, key, emoji}, _from, state) do
    {:reply, Amarula.send_reaction(state.socket, key, emoji), state}
  end

  def handle_call({:mark_read, ids, from}, _from, state) do
    {:reply, Amarula.mark_read(state.socket, from, ids), state}
  end

  def handle_call({:start_poll, jid, name, options}, _from, state) do
    {:ok, msg_id, secret} = Amarula.send_poll(state.socket, jid, name, options)
    # Rebuild the creation message (same secret) to tally votes against.
    {message, ^secret} =
      Amarula.Protocol.Messages.MessageEncoder.poll(name, options, message_secret: secret)

    Logger.info("poll sent id=#{msg_id} — vote on your phone")
    {:reply, {:ok, msg_id}, %{state | poll: %{id: msg_id, secret: secret, message: message}}}
  end

  def handle_call(:connection_state, _from, state) do
    {:reply, state.connection, state}
  end

  def handle_call(:socket, _from, state) do
    {:reply, state.socket, state}
  end

  def handle_call(:synced?, _from, state) do
    {:reply, state.synced, state}
  end

  # --- events from the connection (parent_pid messages) ---

  @impl true
  # Phone-number pairing: on the first QR (while unregistered), request a
  # link-code instead of rendering the QR. Guard so QR rotations don't re-request.
  def handle_info(
        {:amarula, :connection_update, %{qr: qr}},
        %{pairing: {:phone, number}, pairing_requested: false} = state
      )
      when not is_nil(qr) do
    case Amarula.request_pairing_code(state.socket, number) do
      {:ok, code} ->
        Logger.info("🔢 Enter this code in WhatsApp → Linked Devices → Link with phone number:")
        Logger.info("    #{code}")

      {:error, reason} ->
        Logger.error("request_pairing_code failed: #{inspect(reason)}")
    end

    {:noreply, %{state | pairing_requested: true}}
  end

  # Already requested a code (or pairing by phone) — ignore QR rotations.
  def handle_info(
        {:amarula, :connection_update, %{qr: qr}},
        %{pairing: {:phone, _}} = state
      )
      when not is_nil(qr) do
    {:noreply, state}
  end

  def handle_info({:amarula, :connection_update, %{qr: qr}}, state) when not is_nil(qr) do
    render_qr(qr)
    {:noreply, state}
  end

  def handle_info({:amarula, :pairing_code, %{code: code}}, state) do
    Logger.info("🔢 Pairing code: #{code}")
    {:noreply, state}
  end

  def handle_info({:amarula, :connection_update, %{connection: :open} = up}, state) do
    Logger.info("Connection OPEN")
    {:noreply, %{state | connection: Map.get(up, :connection, state.connection)}}
  end

  def handle_info({:amarula, :connection_update, up}, state) do
    Logger.info("Connection update: #{inspect(Map.get(up, :connection) || up)}")
    {:noreply, %{state | connection: Map.get(up, :connection, state.connection)}}
  end

  # History sync (first link / incremental): the chat list + contacts arrive here.
  def handle_info({:amarula, :history_sync, result}, state) do
    Logger.info(
      "📜 history sync #{inspect(result.sync_type)}: " <>
        "#{length(result.chats)} chats, #{length(result.contacts)} contacts"
    )

    {:noreply, %{state | synced: true}}
  end

  def handle_info({:amarula, :chats_update, chats}, state) do
    Logger.info("chats_update: #{length(chats)}")
    {:noreply, state}
  end

  def handle_info({:amarula, :contacts_update, contacts}, state) do
    Logger.info("contacts_update: #{length(contacts)}")
    {:noreply, state}
  end

  # A group's membership/metadata changed (someone added/removed, subject edited,
  # announce toggled, ...). The action is a tagged tuple — match what you care for.
  def handle_info({:amarula, :group_update, %{group: group, action: action}}, state) do
    Logger.info("group_update in #{group.user}: #{inspect(action)}")
    {:noreply, state}
  end

  # A message we sent was delivered/read/played. Use this to track delivery state.
  def handle_info({:amarula, :receipt_update, %{status: status, message_ids: ids}}, state) do
    Logger.info("receipt: #{status} for #{inspect(ids)}")
    {:noreply, state}
  end

  # Someone was blocked/unblocked.
  def handle_info({:amarula, :blocklist_update, items}, state) do
    Logger.info("blocklist_update: #{inspect(items)}")
    {:noreply, state}
  end

  # No creds handling: Amarula persists credentials itself (scoped to :profile),
  # so the next boot reconnects without a QR automatically.

  def handle_info({:amarula, :messages_upsert, %{from: from, id: id, messages: messages}}, state) do
    # `from` is an %Amarula.Address{}; each `msg` is an %Amarula.Msg{}.
    for %Amarula.Msg{} = msg <- messages do
      Logger.info("#{inspect(from)} (#{id}): #{msg.type} #{inspect(msg.content)}")
      # Demo: if we created a poll, decrypt + tally any incoming vote for it.
      maybe_tally_vote(msg, from, state)
    end

    # Demo: with auto_read, send a read receipt for each incoming message.
    if state.auto_read do
      Logger.info("auto read #{id} → #{inspect(Amarula.mark_read(state.socket, from, [id]))}")
    end

    {:noreply, state}
  end

  def handle_info({:amarula, :pairing_success, _data}, state) do
    # Pairing done, but login isn't: WA sends stream-error 515, we reconnect and
    # log in, then the connection goes :open. Nothing to do but wait.
    Logger.info("Paired — completing login…")
    {:noreply, state}
  end

  def handle_info({:amarula, :error, error}, state) do
    Logger.error("Connection error: #{inspect(error)}")
    {:noreply, state}
  end

  def handle_info(other, state) do
    Logger.debug("Unhandled event: #{inspect(other)}")
    {:noreply, state}
  end

  # --- helpers ---

  # Config is just the profile; Amarula fills in protocol/connection defaults (see
  # Amarula.Config) AND loads/persists this profile's credentials itself. So a
  # real app names a :profile and does nothing else about creds.
  defp config(opts) do
    %{profile: Keyword.get(opts, :profile, :default)}
  end

  # Decrypt + tally a poll vote for the poll we created (demo of PollCrypto/Poll).
  defp maybe_tally_vote(%Amarula.Msg{type: :poll_vote, content: pum}, from, %{poll: %{} = poll}) do
    alias Amarula.Protocol.Binary.JID
    ck = pum.pollCreationMessageKey

    # The jids that key the vote crypto must be device-normalized. Creator = the
    # poll creation key's author (our own poll → its remoteJid, our LID); voter =
    # the sender of the vote. Poll id = the creation key's id.
    ctx = %{
      message_secret: poll.secret,
      poll_msg_id: ck.id,
      poll_creator_jid: JID.jid_normalized_user(ck.remoteJid),
      voter_jid: from |> Amarula.Address.to_jid() |> JID.jid_normalized_user()
    }

    case PollCrypto.decrypt_vote(pum.vote, ctx) do
      {:ok, decoded} ->
        tally = Poll.tally(poll.message, [{from, decoded}])
        Logger.info("🗳️  vote from #{from} → tally: #{inspect(tally)}")

      {:error, reason} ->
        Logger.warning("vote decrypt failed: #{inspect(reason)}")
    end
  end

  defp maybe_tally_vote(_kind, _from, _state), do: :ok

  # Attach `plugins` (a list of `{module, opts}`) to `conn`, injecting this
  # GenServer's pid as :server so a plugin can respond through us.
  defp attach_plugins(conn, plugins) do
    Enum.reduce(plugins, conn, fn {mod, opts}, c ->
      mod.attach(c, Keyword.put(opts, :server, self()))
    end)
  end

  defp render_qr(qr) do
    case QRCodeGenerator.render_terminal(qr) do
      {:ok, ascii} ->
        IO.puts("\n" <> ascii <> "\n")
        File.write("/tmp/whatsapp_qr.txt", ascii)
        Logger.info("Scan the QR above (also written to /tmp/whatsapp_qr.txt)")

      {:error, reason} ->
        Logger.warning("Could not render QR (#{inspect(reason)}); raw string: #{qr}")
    end
  end
end
