defmodule Amarula.RetryCache.Step do
  @moduledoc """
  The built-in send-pipeline step that records each outgoing message in the
  `Amarula.RetryCache`, so it can be re-encrypted and resent if the recipient
  asks for a retry. Attached by default (see `Amarula.Conn`); a side-effect step
  that never transforms or halts.

  Expects the send ctx to carry `:retry_cache` (scope), `:profile`, `:msg_id`,
  `:message`, `:to`, and (optionally) `:stanza_attrs`.
  """

  alias Amarula.RetryCache

  @doc "Record the outgoing message, then continue unchanged."
  @spec record(map()) :: {:cont, map()}
  def record(%{retry_cache: scope, profile: profile, msg_id: msg_id} = ctx) do
    entry = %{
      recipient_jid: ctx.to,
      message: ctx.message,
      # Replayed verbatim on a retry-receipt resend so a peer/edit stanza keeps
      # its category/edit attrs (without these, a retried peer PDO loses
      # category=peer and is dropped as :not_on_whatsapp).
      stanza_attrs: Map.get(ctx, :stanza_attrs, %{}),
      ts: System.system_time(:millisecond)
    }

    RetryCache.put(scope, profile, msg_id, entry)
    {:cont, ctx}
  end

  # No cache scope in ctx (e.g. a context that doesn't carry it) — skip.
  def record(ctx), do: {:cont, ctx}
end
