defmodule Amarula.Protocol.Signal.DecryptError do
  @moduledoc """
  Expected decryption failure (bad MAC, wrong/closed chain, version mismatch).

  This is the trial-decrypt signal: `SessionCipher.decrypt_whisper_message/3`
  tries each session in the record and moves to the next one only on this
  error — programming errors (`KeyError`, `MatchError`, ...) propagate instead
  of being misread as "wrong session".

  `:reason` classifies the failure so callers can branch on it structurally
  instead of matching the message text. `:key_unavailable` means the key material
  the message references isn't available — the ratchet counter was already
  consumed, or the one-time prekey it names isn't in our store (consumed by a
  prior decrypt, or an id that was never ours). We can't always tell a redelivery
  from an unknown id, but either way a retry can't succeed, so the receive path
  acks rather than retries. `nil` is any other expected trial-decrypt failure
  (bad MAC, closed/sending chain, version mismatch).
  """
  defexception [:message, :reason]

  @type t :: %__MODULE__{message: String.t() | nil, reason: :key_unavailable | nil}
end
