defmodule Amarula.Protocol.Signal.DeviceListCacheTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Signal.DeviceListCache, as: Cache

  @jid "10000000001@s.whatsapp.net"
  @devices [
    %{
      user: "10000000001",
      device: 0,
      server: "s.whatsapp.net",
      jid: "10000000001:0@s.whatsapp.net"
    },
    %{
      user: "10000000001",
      device: 2,
      server: "s.whatsapp.net",
      jid: "10000000001:2@s.whatsapp.net"
    }
  ]

  setup do
    dir = Path.join(System.tmp_dir!(), "amarula_devcache_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir, conn: Amarula.TestConn.new(dir)}
  end

  describe "get/put" do
    test "round-trips a device list by user", %{conn: conn} do
      assert Cache.get(conn, @jid) == nil
      assert Cache.put(conn, @jid, @devices) == :ok
      assert Cache.get(conn, @jid) == @devices
    end

    test "keys by user, not full jid (device suffix ignored)", %{conn: conn} do
      Cache.put(conn, @jid, @devices)
      assert Cache.get(conn, "10000000001:5@s.whatsapp.net") == @devices
    end

    test "expired entries read as a miss", %{conn: conn} do
      Cache.put(conn, @jid, @devices)
      # @ttl_ms is 1h; query far in the future
      future = System.system_time(:millisecond) + 2 * 60 * 60 * 1000
      assert Cache.get(conn, @jid, future) == nil
    end
  end

  describe "get_many/2" do
    test "splits hits and misses", %{conn: conn} do
      Cache.put(conn, @jid, @devices)

      {hits, misses} = Cache.get_many(conn, [@jid, "20000000002@s.whatsapp.net"])

      assert hits == %{"10000000001" => @devices}
      assert misses == ["20000000002"]
    end

    test "all-miss when nothing cached", %{conn: conn} do
      {hits, misses} = Cache.get_many(conn, [@jid])
      assert hits == %{}
      assert misses == ["10000000001"]
    end
  end

  describe "put_many/2 and delete/2" do
    test "stores several users", %{conn: conn} do
      Cache.put_many(conn, %{
        "10000000001" => @devices,
        "20000000002" => []
      })

      assert Cache.get(conn, @jid) == @devices
      assert Cache.get(conn, "20000000002@s.whatsapp.net") == []
    end

    test "delete removes an entry; deleting a missing one is ok", %{conn: conn} do
      Cache.put(conn, @jid, @devices)
      assert Cache.delete(conn, @jid) == :ok
      assert Cache.get(conn, @jid) == nil
      assert Cache.delete(conn, @jid) == :ok
    end
  end
end
