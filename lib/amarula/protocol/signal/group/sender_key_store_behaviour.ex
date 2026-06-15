defmodule Amarula.Protocol.Signal.Group.SenderKeyStoreBehaviour do
  @moduledoc """
  Behaviour for sender key storage operations.

  This behaviour defines the contract for storing and retrieving
  sender key records used in group encryption.
  """

  alias Amarula.Protocol.Signal.Group.{SenderKeyName, SenderKeyRecord}

  @doc """
  Loads a sender key record for the given sender key name.
  """
  @callback load_sender_key(SenderKeyName.t()) ::
              {:ok, SenderKeyRecord.t()} | {:error, :not_found}

  @doc """
  Stores a sender key record for the given sender key name.
  """
  @callback store_sender_key(SenderKeyName.t(), SenderKeyRecord.t()) :: :ok | {:error, String.t()}
end
