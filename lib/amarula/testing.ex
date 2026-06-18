defmodule Amarula.Testing do
  @moduledoc """
  Test support for **consumers** of Amarula — drive your bot with synthetic
  inbound messages, with no WhatsApp connection.

  A bot built on Amarula receives messages as `{:whatsapp, :messages_upsert,
  %{from, id, messages: [%Amarula.Msg{}]}}` delivered to its `parent_pid`, and
  replies with `Amarula.send_text/3` and friends. To exercise that — "when a
  message like X arrives, does my bot reply with Y?" — you need a connection you
  can feed messages into, and whose sends produce no real-world effect. That's what
  this module gives you: an **offline sandbox connection**.

  In sandbox mode the connection never reaches WhatsApp. Inbound messages are the
  ones you `deliver`; outbound sends short-circuit to `{:ok, msg_id}` without
  encrypting or putting a frame on any wire (see `Amarula.new/1`'s `offline:` mode).
  So your bot's full receive→reply path runs, unchanged, against nothing.

      {:ok, conn} = Amarula.Testing.start_offline(profile: :test)

      # The bot under test: replies "pong" to "ping".
      defp handle({:whatsapp, :messages_upsert, %{messages: msgs}}, conn) do
        for %Amarula.Msg{type: :text, content: "ping", channel: chan} <- msgs do
          Amarula.send_text(conn, Amarula.Address.to_jid!(chan), "pong")
        end
      end

      # Drive it: deliver an inbound message, let the bot react.
      Amarula.Testing.deliver_text(conn, from: "15551234567@s.whatsapp.net", text: "ping")
      assert_receive {:whatsapp, :messages_upsert, %{messages: [_]}} = event
      handle(event, conn)
      # The reply `Amarula.send_text(conn, ..., "pong")` returns `{:ok, id}` and
      # does nothing else — no real message is sent.

  The delivered message is built by the **real** receive pipeline (decode → route →
  classify → `Amarula.Msg.from_proto/2`), so the `%Msg{}` your bot sees is exactly
  what production would produce — these helpers can't fabricate a `Msg` the wire
  could never carry.

  ## Notes

  * `start_offline/1` returns the connection pid (the same handle `Amarula.connect/2`
    returns). Pass it to `Amarula.send_text/3` etc.
  * Sends short-circuit to `{:ok, msg_id}`. `send_media/5` is the exception — it
    uploads media, which needs a live socket, so it does not work in sandbox mode.
  * Events go to `:parent_pid` (defaults to the calling process), so `assert_receive`
    works out of the box in the test that called `start_offline/1`.
  * Stop it with `Amarula.stop/1` (or let the test process exit).
  """

  alias Amarula.Protocol.Auth.AuthUtils
  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Proto

  @typedoc "The connection handle returned by `start_offline/1`."
  @type conn :: pid()

  @doc """
  Start an offline connection: `:connected` immediately, no websocket, no Noise
  handshake, ready to receive injected messages.

  Options:

    * `:profile` — required; the connection profile (e.g. `:test`). One connection
      per profile, so use a unique profile per test to run them async.
    * `:parent_pid` — process that receives `{:whatsapp, _, _}` events. Defaults to
      the caller, so `assert_receive` in your test just works.
    * `:frame_sink` — pid that receives `{:frame_out, %Node{}}` for every outbound
      frame (e.g. the delivery receipt Amarula sends for each inbound message, or
      anything your bot sends). Defaults to the caller. Drain or ignore these.
    * `:auth` — credentials map. Defaults to freshly generated throwaway creds with
      a fake `me` identity, so you needn't pair. Override to control the logged-in
      identity (e.g. to test self-chat / `from_me` handling).
    * `:storage` — storage adapter spec. Defaults to a `File` adapter under a
      throwaway temp dir; clean it up yourself if you need to.

  Returns `{:ok, pid}` or `{:error, reason}` (e.g. `{:already_running, pid}` if a
  connection for this profile is already up).
  """
  @spec start_offline(keyword()) :: {:ok, conn()} | {:error, term()}
  def start_offline(opts) do
    profile = Keyword.fetch!(opts, :profile)
    parent = Keyword.get(opts, :parent_pid, self())
    sink = Keyword.get(opts, :frame_sink, self())
    auth = Keyword.get(opts, :auth, default_auth())
    storage = Keyword.get(opts, :storage, default_storage(profile))

    config = %{
      profile: profile,
      storage: storage,
      connection_state: :connected,
      frame_sink: sink,
      offline: true,
      auth: auth,
      max_retries: 1,
      retry_delay: 100
    }

    config
    |> Amarula.new()
    |> Amarula.connect(parent_pid: parent)
  end

  @doc """
  Deliver a plain-text message to the connection, as if WhatsApp sent it.

  Options:

    * `:from` — required; the sender's JID (e.g. `"15551234567@s.whatsapp.net"`),
      or a group JID for a group message (pair with `:participant`).
    * `:text` — required; the message body.
    * `:id` — the message id; a random one is generated if absent.
    * `:participant`, `:recipient`, `:from_me`, `:notify` — stanza attributes for
      group / self-chat / `from_me` scenarios (see `deliver/2`).

  The bot's `parent_pid` receives `{:whatsapp, :messages_upsert, %{messages:
  [%Amarula.Msg{type: :text, content: text}]}}`.
  """
  @spec deliver_text(conn(), keyword()) :: :ok
  def deliver_text(conn, opts) do
    text = Keyword.fetch!(opts, :text)
    deliver(conn, %Proto.Message{conversation: text}, opts)
  end

  @doc """
  Deliver an arbitrary message proto — the escape hatch for media, reactions,
  locations, and anything else `deliver_text/2` doesn't cover. Build the
  `%Amarula.Protocol.Proto.Message{}` yourself; this wraps it in a `<message>`
  stanza and runs it through the real receive pipeline.

      proto = %Amarula.Protocol.Proto.Message{
        imageMessage: %Amarula.Protocol.Proto.Message.ImageMessage{caption: "look"}
      }
      Amarula.Testing.deliver(conn, proto, from: "15551234567@s.whatsapp.net")

  Options:

    * `:from` — required; the sender's JID.
    * `:id` — message id; random if absent.
    * `:participant` — the writer's JID in a group (when `:from` is the group).
    * `:recipient` — the real recipient (used for `from_me` self/peer disambiguation).
    * `:from_me` — `true` to mark the message as sent by us (default `false`).
    * `:notify` — the sender's display name (becomes `Msg.pushname`).
  """
  @spec deliver(conn(), Proto.Message.t(), keyword()) :: :ok
  def deliver(conn, %Proto.Message{} = proto, opts) do
    from = Keyword.fetch!(opts, :from)
    id = Keyword.get(opts, :id, random_id())

    attrs =
      %{"from" => from, "id" => id, "type" => "text"}
      |> put_attr("participant", opts[:participant])
      |> put_attr("recipient", opts[:recipient])
      |> put_attr("notify", opts[:notify])
      |> put_attr("from_me", if(opts[:from_me], do: "true"))

    enc = Node.create("enc", %{"type" => "plaintext"}, Proto.Message.encode(proto))
    node = Node.create("message", attrs, [enc])

    send(conn, {:inject_node, node})
    :ok
  end

  defp put_attr(attrs, _key, nil), do: attrs
  defp put_attr(attrs, key, value), do: Map.put(attrs, key, value)

  # Throwaway creds with a fake `me` so own-identity derivation (`to`, self-chat)
  # works without pairing. Override via the `:auth` option for identity-specific tests.
  defp default_auth do
    Map.put(AuthUtils.init_auth_creds(), :me, %{
      id: "10000000000@s.whatsapp.net",
      lid: nil,
      name: "Amarula Test"
    })
  end

  defp default_storage(profile) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "amarula_testing_#{profile}_#{System.unique_integer([:positive])}"
      )

    {Amarula.Storage.File, root: dir}
  end

  defp random_id, do: "TEST" <> (:crypto.strong_rand_bytes(8) |> Base.encode16())
end
