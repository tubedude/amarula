defmodule Amarula.Examples.E2E.Plugins do
  @moduledoc """
  Test plugins for the two-client e2e — recv-pipeline steps that auto-respond, so
  the two accounts drive each other hands-off.

  Both are Req-style: `attach(conn, opts)` appends a recv step that inspects the
  incoming message and, if it's text from the expected peer, fires a response via
  the owning `Amarula.Examples.Connection` (`opts[:server]`, injected by the
  GenServer). The send runs in a `Task` so the recv pipeline never blocks.

  Asymmetric roles keep the exchange bounded:
    * `Reply`     — guest's role: text from primary → "ack: <text>" back.
    * `ReactRead` — primary's role: text from guest → 👍 + mark_read (terminal:
      a reaction isn't text, so guest's Reply won't fire again).

  `opts`: `:server` (owning Connection pid, injected), `:from` (peer
  `Amarula.Address` to match), plus per-plugin extras (`:prefix` / `:emoji`).
  """

  defmodule Reply do
    @moduledoc "guest: reply to the peer's text with a prefixed ack."
    @behaviour Amarula.Plugin

    alias Amarula.{Address, Plugin}
    alias Amarula.Examples.Connection
    alias Amarula.Protocol.Messages.MessageContent

    @impl true
    def attach(conn, opts) do
      server = Keyword.fetch!(opts, :server)
      from = Keyword.fetch!(opts, :from)
      prefix = Keyword.get(opts, :prefix, "ack: ")

      Plugin.on_recv(conn, fn ctx ->
        with {:text, body} <- MessageContent.classify(ctx.message),
             true <- Address.same_account?(ctx.from, from) do
          Task.start(fn -> Connection.send_text(server, ctx.from, prefix <> body) end)
        end

        {:cont, ctx}
      end)
    end
  end

  defmodule ReactRead do
    @moduledoc "primary: react 👍 + mark the peer's text as read (terminal)."
    @behaviour Amarula.Plugin

    alias Amarula.{Address, Plugin}
    alias Amarula.Examples.Connection
    alias Amarula.Protocol.Messages.MessageContent
    alias Amarula.Protocol.Proto

    @impl true
    def attach(conn, opts) do
      server = Keyword.fetch!(opts, :server)
      from = Keyword.fetch!(opts, :from)
      emoji = Keyword.get(opts, :emoji, "👍")

      Plugin.on_recv(conn, fn ctx ->
        with {:text, _body} <- MessageContent.classify(ctx.message),
             true <- Address.same_account?(ctx.from, from) do
          key = %Proto.MessageKey{remoteJid: Address.to_jid(ctx.from), id: ctx.id, fromMe: false}

          Task.start(fn ->
            Connection.send_reaction(server, key, emoji)
            Connection.mark_read(server, ctx.from, [ctx.id])
          end)
        end

        {:cont, ctx}
      end)
    end
  end
end
