defmodule Amarula.RetryCache.Scope do
  @moduledoc """
  A retry-cache scope: the resolved adapter plus its state. Handed to a cache
  adapter (with the connection `profile`) on each call. Mirrors
  `Amarula.Storage.Scope` but for the separate retry-cache concern.
  """

  @enforce_keys [:adapter, :state]
  defstruct [:adapter, :state]

  @type t :: %__MODULE__{adapter: module(), state: Amarula.RetryCache.adapter_state()}
end
