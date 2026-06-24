defmodule Amarula.Content.PollVote do
  @moduledoc """
  A received poll vote (`content` of a `%Amarula.Msg{type: :poll_vote}`).

  **Not self-contained:** the vote is *encrypted*, and decrypting it needs the
  poll's `message_secret` — which lives on the **original poll** you sent or hold, not
  on the vote. Correlate `:poll_key` back to that poll, then decrypt `:enc_vote`
  with `Amarula.Protocol.Messages.PollCrypto`.

    * `:poll_key` — the poll being voted on, as a `{jid, msg_id}` ref.
    * `:enc_vote` — `%{payload: bytes, iv: bytes}`, the encrypted selection.
    * `:timestamp` — when the vote was cast (ms).
  """

  @type t :: %__MODULE__{
          poll_key: {String.t() | nil, String.t() | nil} | nil,
          enc_vote: %{payload: binary() | nil, iv: binary() | nil},
          timestamp: integer() | nil
        }

  @enforce_keys [:poll_key]
  defstruct [:poll_key, :timestamp, enc_vote: %{payload: nil, iv: nil}]
end
