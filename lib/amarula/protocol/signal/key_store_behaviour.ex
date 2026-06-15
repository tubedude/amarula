defmodule Amarula.Protocol.Signal.KeyStoreBehaviour do
  @moduledoc """
  Behaviour for key store operations used by LID mapping store.
  """

  @callback get(String.t(), list(String.t())) :: map()
  @callback transaction(map(), String.t()) :: :ok | {:error, String.t()}
end
