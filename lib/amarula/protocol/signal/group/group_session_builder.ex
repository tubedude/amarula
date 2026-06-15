defmodule Amarula.Protocol.Signal.Group.GroupSessionBuilder do
  @moduledoc """
  Group Session Builder for Signal Protocol.

  This module handles the creation and processing of sender key distribution messages
  for group encryption sessions.
  """

  alias Amarula.Protocol.Signal.Group.{
    SenderKeyName,
    SenderKeyRecord,
    SenderKeyState,
    SenderKeyDistributionMessage,
    KeyHelper
  }

  @type t :: %__MODULE__{
          sender_key_store: module()
        }

  defstruct sender_key_store: nil

  @doc """
  Creates a new GroupSessionBuilder.
  """
  @spec new(module()) :: t()
  def new(sender_key_store) do
    %__MODULE__{sender_key_store: sender_key_store}
  end

  @doc """
  Process an incoming sender key distribution message.

  `store` is a map with `load_sender_key` and `store_sender_key` fn fields
  (as returned by `SenderKeyStore.build/1`).

  `item` is a `Proto.Message.SenderKeyDistributionMessage` struct with
  `groupId` (string) and `axolotlSenderKeyDistributionMessage` (raw proto bytes).
  """
  @spec process_sender_key_distribution_message(t(), map(), struct(), String.t()) ::
          :ok | {:error, String.t()}
  def process_sender_key_distribution_message(_builder, sender_key_store, item, author_jid) do
    group_id = item.groupId
    axolotl_bytes = item.axolotlSenderKeyDistributionMessage

    if is_nil(group_id) or is_nil(axolotl_bytes) do
      {:error, "Missing groupId or axolotlSenderKeyDistributionMessage"}
    else
      # axolotl bytes are [version byte][protobuf] — from_serialized strips it.
      with {:ok, skdm} <- SenderKeyDistributionMessage.from_serialized(axolotl_bytes) do
        sender_key_name = SenderKeyName.from_jids(group_id, author_jid)

        existing_record =
          case sender_key_store.load_sender_key.(sender_key_name) do
            {:ok, record} -> record
            {:error, :not_found} -> SenderKeyRecord.new()
          end

        new_state =
          SenderKeyState.new(
            skdm.id || 0,
            skdm.iteration || 0,
            skdm.chain_key,
            %{public: skdm.signature_key, private: nil}
          )

        updated_record = SenderKeyRecord.add_sender_key_state(existing_record, new_state)

        case sender_key_store.store_sender_key.(sender_key_name, updated_record) do
          :ok -> :ok
          {:error, reason} -> {:error, "Failed to store sender key record: #{inspect(reason)}"}
        end
      end
    end
  end

  @doc """
  Creates a sender key distribution message.
  """
  @spec create_sender_key_distribution_message(t(), map(), String.t(), String.t()) ::
          {:ok, SenderKeyDistributionMessage.t()} | {:error, String.t()}
  def create_sender_key_distribution_message(_builder, sender_key_store, group_id, me_id) do
    sender_key_name = SenderKeyName.from_jids(group_id, me_id)

    existing_record =
      case sender_key_store.load_sender_key.(sender_key_name) do
        {:ok, record} -> record
        {:error, :not_found} -> SenderKeyRecord.new()
      end

    with_record =
      if SenderKeyRecord.empty?(existing_record) do
        key_id = KeyHelper.generate_sender_key_id()
        chain_key_seed = KeyHelper.generate_sender_key()
        {signing_pub, signing_priv} = KeyHelper.generate_sender_signing_key()

        new_state =
          SenderKeyState.new(key_id, 0, chain_key_seed, %{
            public: signing_pub,
            private: signing_priv
          })

        updated = SenderKeyRecord.add_sender_key_state(existing_record, new_state)

        case sender_key_store.store_sender_key.(sender_key_name, updated) do
          :ok -> {:ok, updated}
          {:error, reason} -> {:error, "Failed to store: #{inspect(reason)}"}
        end
      else
        {:ok, existing_record}
      end

    with {:ok, record} <- with_record,
         {:ok, state} <- SenderKeyRecord.get_sender_key_state(record) do
      chain_key = state.sender_chain_key

      {:ok,
       SenderKeyDistributionMessage.new(
         state.sender_key_id,
         chain_key.iteration,
         chain_key.seed,
         state.sender_signing_key.public
       )}
    end
  end
end
