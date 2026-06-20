defmodule Amarula.Connection.Receive do
  @moduledoc """
  Pure parsers for the receive path of `Amarula.Connection`.

  Most receive-side parsing already lives in dedicated modules (`Receipt.parse`,
  `Presence.parse_update`, `MessageDecryptor`), and the handlers that ack,
  decrypt, resolve acks, and emit events are socket/cipher/state-bound — they
  stay on `Connection`. This module holds the small pure decisions the ack/retry
  handlers make off a node: the `<ack>` outcome and the retry-receipt targets.
  """

  alias Amarula.Protocol.Binary.NodeUtils

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
end
