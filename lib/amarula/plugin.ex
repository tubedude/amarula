defmodule Amarula.Plugin do
  @moduledoc """
  Req-style plugin pipelines for a connection.

  A connection has two pipelines, each an ordered list of **steps** on the
  `Amarula.Conn`:

    * `send_steps` — run over an outgoing message *before encryption*. Use to
      check/authorize a send, transform the message, or drop it.
    * `recv_steps` — run over an incoming message *after decryption*, before the
      consumer sees it. Use to translate, filter, or drop it.

  A **step** is `fn ctx -> {:cont, ctx} | {:halt, reason}`:

    * `{:cont, ctx}` — continue with the (possibly transformed) ctx;
    * `{:halt, reason}` — stop the pipeline. On send the message is not sent
      (`{:error, {:halted, reason}}` to the caller); on receive it is dropped and
      never reaches the consumer.

  The ctx is a map; both pipelines put the message under `:message`. Send ctx also
  carries `:to`/`:profile`/`:msg_id`; receive ctx carries `:from`/`:id`/`:profile`
  (`:id` is the message id, for building a `MessageKey` to react/reply).

  A **plugin** is a module that appends steps via `attach/2`, Req-style:

      defmodule Blocklist do
        def attach(conn, opts \\\\ []) do
          jids = Keyword.get(opts, :jids, [])
          Amarula.Plugin.on_send(conn, fn
            %{to: to} = ctx -> if to in jids, do: {:halt, :blocked}, else: {:cont, ctx}
          end)
        end
      end

      Amarula.new(config) |> Blocklist.attach(jids: [...]) |> Amarula.connect()

  Implementing the `Amarula.Plugin` behaviour (`@behaviour Amarula.Plugin`) is
  optional — any module with a matching `attach/2` works in a pipe.
  """

  alias Amarula.Conn

  @typedoc "A pipeline step."
  @type step :: Conn.step()

  @doc "Attach the plugin's steps to `conn`, returning the updated `conn`."
  @callback attach(Conn.t(), keyword()) :: Conn.t()

  @doc "Append a step to the send pipeline (before encrypt)."
  @spec on_send(Conn.t(), step()) :: Conn.t()
  defdelegate on_send(conn, step), to: Conn, as: :append_send_step

  @doc "Append a step to the receive pipeline (after decrypt)."
  @spec on_recv(Conn.t(), step()) :: Conn.t()
  defdelegate on_recv(conn, step), to: Conn, as: :append_recv_step

  @doc """
  Run `steps` over `ctx`, threading the ctx through each. Returns `{:cont, ctx}`
  if all steps continued (with the final, possibly transformed ctx), or
  `{:halt, reason}` at the first step that halted (remaining steps don't run).
  """
  @spec run([step()], map()) :: {:cont, map()} | {:halt, term()}
  def run(steps, ctx) do
    Enum.reduce_while(steps, {:cont, ctx}, fn step, {:cont, ctx} ->
      case step.(ctx) do
        {:cont, ctx} -> {:cont, {:cont, ctx}}
        {:halt, reason} -> {:halt, {:halt, reason}}
      end
    end)
  end
end
