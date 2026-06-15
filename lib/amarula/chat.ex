defmodule Amarula.Chat do
  @moduledoc """
  A chat update derived from app-state sync — the consumer view of a mutation to
  a conversation. `address` is the chat (`Amarula.Address`: 1:1 or group); the
  other fields are the change carried by the mutation (nil = unchanged).

  Produced by `Amarula.Protocol.AppState.SyncAction.decode/1` and surfaced to the
  consumer as `{:whatsapp, :chats_update, [%Chat{}]}`.
  """

  alias Amarula.Address

  @type t :: %__MODULE__{
          address: Address.t(),
          archived: boolean() | nil,
          pinned: boolean() | nil,
          mute_end: integer() | nil,
          unread: integer() | nil,
          deleted: boolean() | nil
        }

  @enforce_keys [:address]
  defstruct [:address, :archived, :pinned, :mute_end, :unread, :deleted]
end
