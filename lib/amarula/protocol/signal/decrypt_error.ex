defmodule Amarula.Protocol.Signal.DecryptError do
  @moduledoc """
  Expected decryption failure (bad MAC, wrong/closed chain, version mismatch).

  This is the trial-decrypt signal: `SessionCipher.decrypt_whisper_message/3`
  tries each session in the record and moves to the next one only on this
  error — programming errors (`KeyError`, `MatchError`, ...) propagate instead
  of being misread as "wrong session".
  """
  defexception [:message]
end
