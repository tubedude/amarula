defmodule Amarula.MessageSecretStore.Scope do
  @moduledoc """
  A message-secret-store scope: the resolved adapter plus its state. Handed to an
  adapter (with the connection `profile`) on each call. Mirrors
  `Amarula.RetryCache.Scope` but for the message-secret concern (issue #30).
  """

  @enforce_keys [:adapter, :state]
  defstruct [:adapter, :state]

  @type t :: %__MODULE__{adapter: module(), state: Amarula.MessageSecretStore.adapter_state()}
end
