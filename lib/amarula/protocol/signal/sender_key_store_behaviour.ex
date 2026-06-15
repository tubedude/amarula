defmodule Amarula.Protocol.Signal.SenderKeyStoreBehaviour do
  @moduledoc """
  Behaviour for a Signal Protocol Sender Key Store.
  """

  @callback get_sender_key_record(module(), Amarula.Protocol.Signal.Group.SenderKeyName.t()) ::
              {:ok, Amarula.Protocol.Signal.Group.SenderKeyRecord.t()} | {:error, String.t()}

  @callback store_sender_key_record(
              module(),
              Amarula.Protocol.Signal.Group.SenderKeyName.t(),
              Amarula.Protocol.Signal.Group.SenderKeyRecord.t()
            ) ::
              :ok | {:error, String.t()}

  @callback load_sender_key(Amarula.Protocol.Signal.Group.SenderKeyName.t()) ::
              {:ok, Amarula.Protocol.Signal.Group.SenderKeyRecord.t()}
              | {:error, :not_found}
              | {:error, String.t()}
end
