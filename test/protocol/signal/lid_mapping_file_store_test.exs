defmodule Amarula.Protocol.Signal.LidMappingFileStoreTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Signal.LidMappingFileStore, as: Store

  @pn "10000000001@s.whatsapp.net"
  @lid "20000000001@lid"

  setup do
    dir = Path.join(System.tmp_dir!(), "amarula_lidmap_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir, conn: Amarula.TestConn.new(dir)}
  end

  describe "store_mappings/2" do
    test "stores a {lid, pn} pair and resolves both directions", %{conn: conn} do
      assert {1, [{@lid, @pn}]} = Store.store_mappings(conn, [{@lid, @pn}])

      assert Store.lid_for_pn(conn, @pn) == "20000000001"
      assert Store.pn_for_lid(conn, @lid) == "10000000001"
    end

    test "accepts the pair in either order", %{conn: conn} do
      assert {1, [_]} = Store.store_mappings(conn, [{@pn, @lid}])
      assert Store.lid_for_pn(conn, @pn) == "20000000001"
    end

    test "skips invalid pairs (two PNs, two LIDs, junk)", %{conn: conn} do
      pairs = [
        {@pn, "10000000002@s.whatsapp.net"},
        {@lid, "20000000002@lid"},
        {"not-a-jid", "also-not"}
      ]

      assert {0, []} = Store.store_mappings(conn, pairs)
      assert Store.lid_for_pn(conn, @pn) == nil
    end

    test "counts but does not re-report a pair that already matched", %{conn: conn} do
      assert {1, [{@lid, @pn}]} = Store.store_mappings(conn, [{@lid, @pn}])
      # second store: still counted, but not newly stored
      assert {1, []} = Store.store_mappings(conn, [{@lid, @pn}])
      assert Store.lid_for_pn(conn, @pn) == "20000000001"
    end

    test "stores multiple pairs", %{conn: conn} do
      pairs = [
        {@lid, @pn},
        {"20000000002@lid", "10000000002@s.whatsapp.net"}
      ]

      assert {2, newly} = Store.store_mappings(conn, pairs)
      assert length(newly) == 2
      assert Store.lid_for_pn(conn, "10000000002@s.whatsapp.net") == "20000000002"
    end
  end

  describe "canonical_jid building blocks" do
    # `Amarula.Connection.canonical_jid/2` (public facade `Amarula.canonical_jid/2`)
    # is built on `pn_for_lid/2` + `JID`. These guard the pieces it depends on so
    # the facade helper keeps producing `<pn>@s.whatsapp.net` from a mapped LID.
    test "a mapped LID resolves to its PN user, ready to re-encode as a PN jid", %{conn: conn} do
      Store.store_mappings(conn, [{@lid, @pn}])

      pn_user = Store.pn_for_lid(conn, @lid)
      assert pn_user == "10000000001"

      canonical =
        Amarula.Protocol.Binary.JID.encode(%{
          user: pn_user,
          server: "s.whatsapp.net",
          device: 0
        })

      assert canonical == @pn
    end

    test "an unmapped LID has no PN (helper leaves it unchanged)", %{conn: conn} do
      assert Store.pn_for_lid(conn, "99999999999@lid") == nil
    end
  end

  describe "lookups" do
    test "return nil when unmapped", %{conn: conn} do
      assert Store.lid_for_pn(conn, @pn) == nil
      assert Store.pn_for_lid(conn, @lid) == nil
    end

    test "persist across calls (separate reads hit disk)", %{conn: conn} do
      Store.store_mappings(conn, [{@lid, @pn}])
      # fresh lookup reads the file written earlier
      assert Store.pn_for_lid(conn, @lid) == "10000000001"
    end
  end
end
