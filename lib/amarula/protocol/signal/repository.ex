defmodule Amarula.Protocol.Signal.Repository do
  @moduledoc """
  Signal Protocol Repository - Main interface for Signal protocol operations.

  This module provides the high-level API for all Signal protocol operations,
  including group message encryption/decryption, sender key management,
  and LID mapping integration.
  """

  use GenServer
  require Logger
  alias Amarula.Protocol.Signal.{LIDMappingStore}

  alias Amarula.Protocol.Signal.Group.{
    GroupCipher,
    GroupSessionBuilder,
    SenderKeyName,
    SenderKeyStore
  }

  @type t :: %__MODULE__{
          key_store: module(),
          lid_mapping_store: pid(),
          sender_key_store: module(),
          logger: module()
        }

  defstruct key_store: nil, lid_mapping_store: nil, sender_key_store: nil, logger: nil

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the Signal Repository.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Decrypts a group message.
  """
  @spec decrypt_group_message(GenServer.server(), map()) :: {:ok, binary()} | {:error, String.t()}
  def decrypt_group_message(server \\ __MODULE__, %{
        group: group,
        author_jid: author_jid,
        msg: msg
      }) do
    GenServer.call(server, {:decrypt_group_message, group, author_jid, msg})
  end

  @doc """
  Encrypts a group message.
  """
  @spec encrypt_group_message(GenServer.server(), map()) :: {:ok, map()} | {:error, String.t()}
  def encrypt_group_message(server \\ __MODULE__, %{group: group, data: data, me_id: me_id}) do
    GenServer.call(server, {:encrypt_group_message, group, data, me_id})
  end

  @doc """
  Processes a sender key distribution message.
  """
  @spec process_sender_key_distribution_message(GenServer.server(), map()) ::
          :ok | {:error, String.t()}
  def process_sender_key_distribution_message(server \\ __MODULE__, %{
        item: item,
        author_jid: author_jid
      }) do
    GenServer.call(server, {:process_sender_key_distribution_message, item, author_jid})
  end

  @doc """
  Gets LID for a phone number.
  """
  @spec get_lid_for_pn(GenServer.server(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def get_lid_for_pn(server \\ __MODULE__, pn) do
    GenServer.call(server, {:get_lid_for_pn, pn})
  end

  @doc """
  Gets phone number for a LID.
  """
  @spec get_pn_for_lid(GenServer.server(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def get_pn_for_lid(server \\ __MODULE__, lid) do
    GenServer.call(server, {:get_pn_for_lid, lid})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init(opts) do
    key_store = Keyword.get(opts, :key_store)
    auth_dir = Keyword.get(opts, :auth_dir)
    lid_mapping_store = Keyword.get(opts, :lid_mapping_store)
    pn_to_lid_func = Keyword.get(opts, :pn_to_lid_func)
    logger = Keyword.get(opts, :logger, Logger)

    if is_nil(key_store) or is_nil(auth_dir) do
      {:error, "key_store and auth_dir are required"}
    else
      sender_key_store = SenderKeyStore.build(auth_dir)

      lid_mapping_store =
        if lid_mapping_store do
          lid_mapping_store
        else
          {:ok, store} =
            LIDMappingStore.start_link(
              key_store: key_store,
              pn_to_lid_func: pn_to_lid_func,
              logger: logger
            )

          store
        end

      state = %__MODULE__{
        key_store: key_store,
        lid_mapping_store: lid_mapping_store,
        sender_key_store: sender_key_store,
        logger: logger
      }

      {:ok, state}
    end
  end

  @impl GenServer
  def handle_call({:decrypt_group_message, group, author_jid, msg}, _from, state) do
    sender_name = jid_to_signal_sender_key_name(group, author_jid)

    case GroupCipher.decrypt(state.sender_key_store, sender_name, msg) do
      {:ok, plaintext} ->
        {:reply, {:ok, plaintext}, state}

      {:error, reason} ->
        {:reply, {:error, "Failed to decrypt group message: #{reason}"}, state}
    end
  end

  @impl GenServer
  def handle_call({:encrypt_group_message, group, data, me_id}, _from, state) do
    sender_name = jid_to_signal_sender_key_name(group, me_id)

    case GroupCipher.encrypt(state.sender_key_store, sender_name, data) do
      {:ok, encrypted_msg} ->
        {:reply, {:ok, encrypted_msg}, state}

      {:error, reason} ->
        {:reply, {:error, "Failed to encrypt group message: #{reason}"}, state}
    end
  end

  @impl GenServer
  def handle_call({:process_sender_key_distribution_message, item, author_jid}, _from, state) do
    builder = GroupSessionBuilder.new(state.sender_key_store)

    case GroupSessionBuilder.process_sender_key_distribution_message(
           builder,
           state.sender_key_store,
           item,
           author_jid
         ) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, "Failed to process sender key distribution: #{reason}"}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_lid_for_pn, pn}, _from, state) do
    case LIDMappingStore.get_lid_for_pn(state.lid_mapping_store, pn) do
      {:ok, lid} -> {:reply, {:ok, lid}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_pn_for_lid, lid}, _from, state) do
    case LIDMappingStore.get_pn_for_lid(state.lid_mapping_store, lid) do
      {:ok, pn} -> {:reply, {:ok, pn}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  defp jid_to_signal_sender_key_name(group_jid, author_jid) do
    SenderKeyName.from_jids(group_jid, author_jid)
  end
end
