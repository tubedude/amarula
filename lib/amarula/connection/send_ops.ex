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

  alias Amarula.Protocol.Messages.MessageEncoder

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
  def media(jid, message), do: {jid, %{message: message}, &default_send_reply/2}

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
end
