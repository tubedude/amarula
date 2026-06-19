defmodule Amarula.Protocol.Signal.LIDMappingStoreTest do
  # async: false — the stub key_store is a single named Agent, reset per test.
  use ExUnit.Case, async: false

  alias Amarula.Protocol.Signal.{LIDMapping, LIDMappingStore}

  # In-memory key_store satisfying the contract LIDMappingStore uses:
  #   transaction(mappings_map, "lid-mapping") :: :ok
  #   get("lid-mapping", [key]) :: %{key => value} | %{}
  # The store calls these as bare module functions from its OWN process, so the
  # state can't ride in the test's process dict — back it with a named Agent any
  # process can reach. ExUnit owns the Agent's lifecycle (start_supervised!), so
  # it is fully torn down before the next test starts — no leak, no cross-test
  # collision on the shared name.
  defmodule MemKeyStore do
    use Agent

    def start_link(_), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

    def transaction(mappings, _ns) when is_map(mappings) do
      Agent.update(__MODULE__, &Map.merge(&1, mappings))
      :ok
    end

    def get(_ns, [key]) do
      Agent.get(__MODULE__, fn m ->
        case Map.fetch(m, key) do
          {:ok, v} -> %{key => v}
          :error -> %{}
        end
      end)
    end
  end

  setup do
    start_supervised!(MemKeyStore)
    server = start_supervised!({LIDMappingStore, name: nil, key_store: MemKeyStore})
    {:ok, server: server}
  end

  # Lookups take FULL JIDs (the store decodes them to the bare user internally).
  @pn "5511999999999@s.whatsapp.net"
  @lid "200200200@lid"

  describe "store + lookup" do
    setup %{server: server} do
      assert :ok = LIDMappingStore.store_lid_pn_mappings(server, [LIDMapping.new(@pn, @lid)])
      :ok
    end

    test "get_lid_for_pn returns the lid user", %{server: server} do
      assert {:ok, "200200200@lid"} = LIDMappingStore.get_lid_for_pn(server, @pn)
    end

    test "get_pn_for_lid reconstructs the pn jid (reverse mapping)", %{server: server} do
      assert {:ok, "5511999999999@s.whatsapp.net"} =
               LIDMappingStore.get_pn_for_lid(server, @lid)
    end

    test "an unknown pn has no lid", %{server: server} do
      assert {:error, _} = LIDMappingStore.get_lid_for_pn(server, "9990000@s.whatsapp.net")
    end
  end

  describe "validation" do
    test "rejects a non-pn jid passed to get_lid_for_pn", %{server: server} do
      assert {:error, _} = LIDMappingStore.get_lid_for_pn(server, "200200200@lid")
    end

    test "rejects a non-lid jid passed to get_pn_for_lid", %{server: server} do
      assert {:error, _} = LIDMappingStore.get_pn_for_lid(server, @pn)
    end

    test "stores several valid mappings at once", %{server: server} do
      mappings = [
        LIDMapping.new("5511111111111@s.whatsapp.net", "100100100@lid"),
        LIDMapping.new("5522222222222@s.whatsapp.net", "300300300@lid")
      ]

      assert :ok = LIDMappingStore.store_lid_pn_mappings(server, mappings)

      assert {:ok, "100100100@lid"} =
               LIDMappingStore.get_lid_for_pn(server, "5511111111111@s.whatsapp.net")

      assert {:ok, "300300300@lid"} =
               LIDMappingStore.get_lid_for_pn(server, "5522222222222@s.whatsapp.net")
    end
  end

  describe "init/1" do
    test "requires a key_store" do
      assert {:error, _} = LIDMappingStore.start_link(name: nil, key_store: nil)
    end
  end
end
