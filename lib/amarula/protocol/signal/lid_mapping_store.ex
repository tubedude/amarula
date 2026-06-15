defmodule Amarula.Protocol.Signal.LIDMappingStore do
  @moduledoc """
  LID mapping store for managing Phone Number to Local ID mappings.

  This store handles the conversion between PN (Phone Number) JIDs and LID (Local ID) JIDs
  using caching and persistent storage. It supports both forward (PN → LID) and reverse
  (LID → PN) mappings.
  """

  use GenServer
  require Logger
  alias Amarula.Protocol.Signal.LIDMapping

  # Cache configuration (for future use)
  # @cache_ttl 7 * 24 * 60 * 60 * 1000  # 7 days in milliseconds
  # @cache_max_size 10000

  @type pn_to_lid_func :: (list(String.t()) -> {:ok, list(LIDMapping.t())} | {:error, String.t()})

  @type t :: %__MODULE__{
          cache: :ets.tid(),
          key_store: module(),
          pn_to_lid_func: pn_to_lid_func() | nil,
          logger: module()
        }

  defstruct cache: nil, key_store: nil, pn_to_lid_func: nil, logger: nil

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the LID mapping store.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Stores LID-PN mappings.
  """
  @spec store_lid_pn_mappings(GenServer.server(), list(LIDMapping.t())) ::
          :ok | {:error, String.t()}
  def store_lid_pn_mappings(server \\ __MODULE__, mappings) do
    GenServer.call(server, {:store_mappings, mappings})
  end

  @doc """
  Gets LID for a single PN.
  """
  @spec get_lid_for_pn(GenServer.server(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def get_lid_for_pn(server \\ __MODULE__, pn) do
    case get_lids_for_pns(server, [pn]) do
      {:ok, [%LIDMapping{lid: lid}]} -> {:ok, lid}
      {:ok, []} -> {:error, "No LID mapping found for PN: #{pn}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets LIDs for multiple PNs.
  """
  @spec get_lids_for_pns(GenServer.server(), list(String.t())) ::
          {:ok, list(LIDMapping.t())} | {:error, String.t()}
  def get_lids_for_pns(server \\ __MODULE__, pns) do
    GenServer.call(server, {:get_lids_for_pns, pns})
  end

  @doc """
  Gets PN for a LID.
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
    pn_to_lid_func = Keyword.get(opts, :pn_to_lid_func)
    logger = Keyword.get(opts, :logger, Logger)

    if is_nil(key_store) do
      {:error, "key_store is required"}
    else
      # Create ETS table for caching with unique name
      table_name = :"lid_mapping_cache_#{System.unique_integer([:positive])}"
      cache = :ets.new(table_name, [:set, :private, :named_table])

      state = %__MODULE__{
        cache: cache,
        key_store: key_store,
        pn_to_lid_func: pn_to_lid_func,
        logger: logger
      }

      {:ok, state}
    end
  end

  @impl GenServer
  def handle_call({:store_mappings, mappings}, _from, state) do
    try do
      # Validate and process mappings
      pair_map = validate_and_process_mappings(mappings, state)

      if map_size(pair_map) == 0 do
        {:reply, :ok, state}
      else
        # Store in key store and update cache
        case store_mappings_in_key_store(state.key_store, pair_map) do
          :ok ->
            update_cache(state.cache, pair_map)
            Logger.debug("Stored #{map_size(pair_map)} LID-PN mappings")
            {:reply, :ok, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      end
    rescue
      error ->
        {:reply, {:error, "Failed to store mappings: #{inspect(error)}"}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_lids_for_pns, pns}, _from, state) do
    try do
      result = process_pns_for_lids(pns, state)
      {:reply, result, state}
    rescue
      error ->
        {:reply, {:error, "Failed to get LIDs for PNs: #{inspect(error)}"}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_pn_for_lid, lid}, _from, state) do
    try do
      result = process_lid_for_pn(lid, state)
      {:reply, result, state}
    rescue
      error ->
        {:reply, {:error, "Failed to get PN for LID: #{inspect(error)}"}, state}
    end
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  @spec validate_and_process_mappings(list(LIDMapping.t()), t()) :: map()
  defp validate_and_process_mappings(mappings, state) do
    Enum.reduce(mappings, %{}, fn %LIDMapping{pn: pn, lid: lid}, acc ->
      if valid_mapping?(pn, lid) do
        case {LIDMapping.decode_jid(pn), LIDMapping.decode_jid(lid)} do
          {{:ok, pn_decoded}, {:ok, lid_decoded}} ->
            pn_user = pn_decoded.user
            lid_user = lid_decoded.user

            # Check if mapping already exists
            case get_cached_mapping(state.cache, "pn:#{pn_user}") do
              ^lid_user ->
                Logger.debug("LID mapping already exists for #{pn_user} → #{lid_user}")
                acc

              _ ->
                Map.put(acc, pn_user, lid_user)
            end

          _ ->
            Logger.warning("Invalid LID-PN mapping: #{pn}, #{lid}")
            acc
        end
      else
        state.logger.warning("Invalid LID-PN mapping: #{pn}, #{lid}")
        acc
      end
    end)
  end

  @spec valid_mapping?(String.t(), String.t()) :: boolean()
  defp valid_mapping?(pn, lid) do
    (LIDMapping.is_pn_user?(pn) and LIDMapping.is_lid_user?(lid)) or
      (LIDMapping.is_pn_user?(lid) and LIDMapping.is_lid_user?(pn))
  end

  @spec store_mappings_in_key_store(module(), map()) :: :ok | {:error, String.t()}
  defp store_mappings_in_key_store(key_store, pair_map) do
    # Store both forward and reverse mappings
    mappings =
      Enum.reduce(pair_map, %{}, fn {pn_user, lid_user}, acc ->
        Map.merge(acc, %{
          pn_user => lid_user,
          "#{lid_user}_reverse" => pn_user
        })
      end)

    # Use key store transaction if available
    case key_store.transaction(mappings, "lid-mapping") do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update_cache(:ets.tid(), map()) :: :ok
  defp update_cache(cache, pair_map) do
    Enum.each(pair_map, fn {pn_user, lid_user} ->
      :ets.insert(cache, {"pn:#{pn_user}", lid_user})
      :ets.insert(cache, {"lid:#{lid_user}", pn_user})
    end)
  end

  @spec get_cached_mapping(:ets.tid(), String.t()) :: String.t() | nil
  defp get_cached_mapping(cache, key) do
    case :ets.lookup(cache, key) do
      [{^key, value}] -> value
      [] -> nil
    end
  end

  @spec process_pns_for_lids(list(String.t()), t()) ::
          {:ok, list(LIDMapping.t())} | {:error, String.t()}
  defp process_pns_for_lids(pns, state) do
    {successful_pairs, usync_fetch} =
      Enum.reduce(pns, {%{}, %{}}, fn pn, {pairs, usync} ->
        if LIDMapping.is_pn_user?(pn) or LIDMapping.is_hosted_pn_user?(pn) do
          case LIDMapping.decode_jid(pn) do
            {:ok, decoded} ->
              pn_user = decoded.user
              device = decoded.device

              # Check cache first
              case get_cached_mapping(state.cache, "pn:#{pn_user}") do
                nil ->
                  # Cache miss - check database
                  case get_database_mapping(state.key_store, pn_user) do
                    {:ok, lid_user} ->
                      # Update cache and create mapping
                      update_cache(state.cache, %{pn_user => lid_user})
                      device_specific_lid = construct_device_lid(lid_user, device, decoded.domain)
                      device_specific_pn = construct_device_pn(pn_user, device, decoded.domain)

                      new_pairs =
                        Map.put(
                          pairs,
                          pn,
                          LIDMapping.new(device_specific_pn, device_specific_lid)
                        )

                      {new_pairs, usync}

                    {:error, :not_found} ->
                      # Need to fetch from USync
                      normalized_pn = normalize_pn_for_usync(pn)
                      new_usync = Map.update(usync, normalized_pn, [device], &[device | &1])
                      {pairs, new_usync}
                  end

                lid_user ->
                  # Cache hit
                  device_specific_lid = construct_device_lid(lid_user, device, decoded.domain)
                  device_specific_pn = construct_device_pn(pn_user, device, decoded.domain)

                  new_pairs =
                    Map.put(pairs, pn, LIDMapping.new(device_specific_pn, device_specific_lid))

                  {new_pairs, usync}
              end

            {:error, _} ->
              {pairs, usync}
          end
        else
          {pairs, usync}
        end
      end)

    # Handle USync fetch if needed
    if map_size(usync_fetch) > 0 do
      case fetch_from_usync(state.pn_to_lid_func, Map.keys(usync_fetch)) do
        {:ok, usync_mappings} ->
          # Store the new mappings
          store_mappings_in_key_store(state.key_store, usync_mappings)
          update_cache(state.cache, usync_mappings)

          # Create device-specific mappings
          new_pairs =
            Enum.reduce(usync_mappings, successful_pairs, fn {pn_user, lid_user}, acc ->
              devices =
                Map.get(usync_fetch, normalize_pn_for_usync("#{pn_user}@s.whatsapp.net"), [])

              Enum.reduce(devices, acc, fn device, device_acc ->
                device_specific_lid = construct_device_lid(lid_user, device, "lid")
                device_specific_pn = construct_device_pn(pn_user, device, "s.whatsapp.net")

                Map.put(
                  device_acc,
                  device_specific_pn,
                  LIDMapping.new(device_specific_pn, device_specific_lid)
                )
              end)
            end)

          {:ok, Map.values(new_pairs)}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, Map.values(successful_pairs)}
    end
  end

  @spec process_lid_for_pn(String.t(), t()) :: {:ok, String.t()} | {:error, String.t()}
  defp process_lid_for_pn(lid, state) do
    if not LIDMapping.is_lid_user?(lid) do
      {:error, "Invalid LID format: #{lid}"}
    else
      case LIDMapping.decode_jid(lid) do
        {:ok, decoded} ->
          lid_user = decoded.user
          device = decoded.device

          # Check cache first
          case get_cached_mapping(state.cache, "lid:#{lid_user}") do
            nil ->
              # Cache miss - check database
              case get_database_mapping(state.key_store, "#{lid_user}_reverse") do
                {:ok, pn_user} ->
                  # Update cache and construct PN
                  update_cache(state.cache, %{lid_user => pn_user})
                  domain = if decoded.domain == "hosted.lid", do: "hosted", else: "s.whatsapp.net"
                  pn_jid = LIDMapping.construct_device_jid(pn_user, device, domain)
                  {:ok, pn_jid}

                {:error, :not_found} ->
                  {:error, "No reverse mapping found for LID user: #{lid_user}"}
              end

            pn_user ->
              # Cache hit
              domain = if decoded.domain == "hosted.lid", do: "hosted", else: "s.whatsapp.net"
              pn_jid = LIDMapping.construct_device_jid(pn_user, device, domain)
              {:ok, pn_jid}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec get_database_mapping(module(), String.t()) :: {:ok, String.t()} | {:error, :not_found}
  defp get_database_mapping(key_store, key) do
    case key_store.get("lid-mapping", [key]) do
      %{^key => value} when is_binary(value) -> {:ok, value}
      _ -> {:error, :not_found}
    end
  end

  @spec fetch_from_usync(pn_to_lid_func() | nil, list(String.t())) ::
          {:ok, map()} | {:error, String.t()}
  defp fetch_from_usync(nil, _pns), do: {:error, "No USync function provided"}

  defp fetch_from_usync(func, pns) do
    case func.(pns) do
      {:ok, mappings} ->
        pair_map =
          Enum.reduce(mappings, %{}, fn %LIDMapping{pn: pn, lid: lid}, acc ->
            case {LIDMapping.decode_jid(pn), LIDMapping.decode_jid(lid)} do
              {{:ok, pn_decoded}, {:ok, lid_decoded}} ->
                Map.put(acc, pn_decoded.user, lid_decoded.user)

              _ ->
                acc
            end
          end)

        {:ok, pair_map}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec normalize_pn_for_usync(String.t()) :: String.t()
  defp normalize_pn_for_usync(pn) do
    case LIDMapping.decode_jid(pn) do
      {:ok, decoded} ->
        if decoded.domain == "hosted" do
          "#{decoded.user}@s.whatsapp.net"
        else
          "#{decoded.user}@s.whatsapp.net"
        end

      {:error, _} ->
        pn
    end
  end

  @spec construct_device_lid(String.t(), non_neg_integer(), String.t()) :: String.t()
  defp construct_device_lid(lid_user, device, domain) do
    lid_domain = if domain == "hosted", do: "hosted.lid", else: "lid"
    LIDMapping.construct_device_jid(lid_user, device, lid_domain)
  end

  @spec construct_device_pn(String.t(), non_neg_integer(), String.t()) :: String.t()
  defp construct_device_pn(pn_user, device, _domain) do
    pn_domain = if device == 99, do: "hosted", else: "s.whatsapp.net"
    LIDMapping.construct_device_jid(pn_user, device, pn_domain)
  end
end
