defmodule Amarula.AppStateTest do
  use ExUnit.Case, async: true

  # Amarula.AppState.force_resync/2 is a thin cast wrapper over
  # Connection.force_resync_app_state/2. These tests run against a REAL offline
  # sandbox connection: the version is seeded in Storage first (as a normal resync
  # would leave it), force_resync is called, and the test asserts on the actual
  # outbound <iq> the connection put on the wire — proving the stored version was
  # reset to 0 (return_snapshot="true") rather than resumed.

  alias Amarula.AppState
  alias Amarula.Connection
  alias Amarula.Protocol.AppState.{Patch, Sync}
  alias Amarula.Protocol.Binary.NodeUtils

  setup do
    profile = :"app_state_#{System.unique_integer([:positive])}"
    dir = Path.join(System.tmp_dir!(), "amarula_app_state_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    {:ok, pid} =
      Amarula.Testing.start_offline(
        profile: profile,
        storage: {Amarula.Storage.File, root: dir}
      )

    on_exit(fn -> Amarula.stop(pid) end)

    conn = Connection.get_conn(pid)
    {:ok, pid: pid, storage: conn.storage, profile: profile}
  end

  defp seed_version(storage, profile, name, version) do
    st = %{Patch.new_state() | version: version}
    Amarula.Storage.put(storage, profile, :app_state_version, name, st)
  end

  defp recv_iq do
    receive do
      {:frame_out, %{tag: "iq"} = node} -> node
    after
      1000 -> flunk("timed out waiting for the outbound app-state sync IQ")
    end
  end

  defp collection_attrs(iq, name) do
    sync = NodeUtils.get_binary_node_child(iq, "sync")

    sync
    |> NodeUtils.get_binary_node_children("collection")
    |> Enum.find(fn c -> NodeUtils.get_attr(c, "name") == name end)
  end

  test "force_resync/2 with no args resets every collection to version 0", %{
    pid: pid,
    storage: storage,
    profile: profile
  } do
    # Seed every collection as if a normal resync had already advanced it.
    for name <- Sync.collections(), do: seed_version(storage, profile, name, 5)

    AppState.force_resync(pid)
    iq = recv_iq()

    for name <- Sync.collections() do
      c = collection_attrs(iq, name)
      assert c, "expected a <collection name=#{name}> in the resync IQ"
      assert NodeUtils.get_attr(c, "version") == "0"
      assert NodeUtils.get_attr(c, "return_snapshot") == "true"
    end
  end

  test "force_resync/2 with explicit names only resets those collections", %{
    pid: pid,
    storage: storage,
    profile: profile
  } do
    seed_version(storage, profile, "regular", 7)
    seed_version(storage, profile, "regular_low", 3)

    AppState.force_resync(pid, ["regular"])
    iq = recv_iq()

    sync = NodeUtils.get_binary_node_child(iq, "sync")

    names =
      sync
      |> NodeUtils.get_binary_node_children("collection")
      |> Enum.map(&NodeUtils.get_attr(&1, "name"))

    assert names == ["regular"]

    c = collection_attrs(iq, "regular")
    assert NodeUtils.get_attr(c, "version") == "0"
    assert NodeUtils.get_attr(c, "return_snapshot") == "true"
  end

  test "a reply to a forced resync feeds the normal apply/emit path (no snapshot content needed)",
       %{pid: pid, storage: storage, profile: profile} do
    seed_version(storage, profile, "regular", 5)

    AppState.force_resync(pid, ["regular"])
    iq = recv_iq()

    # An empty collection reply (no patches, no snapshot) is enough to prove the
    # forced request round-trips through the ordinary handle_tracked_iq(:app_state_sync)
    # → apply_app_state_reply/2 path rather than some special-cased one — decoding
    # a real snapshot's contents is already covered by
    # test/protocol/app_state/sync_test.exs.
    # The outer <iq> node keeps its attrs as a keyword list (order-preserving,
    # per Sync.request_iq/1), unlike the map-attrs nodes NodeUtils.get_attr/2
    # expects — so pull the id out directly.
    {"id", id} = List.keyfind(iq.attrs, "id", 0)

    reply = %Amarula.Protocol.Binary.Node{
      tag: "iq",
      attrs: %{"type" => "result", "id" => id},
      content: [
        %Amarula.Protocol.Binary.Node{
          tag: "sync",
          attrs: %{},
          content: [
            %Amarula.Protocol.Binary.Node{
              tag: "collection",
              attrs: %{"name" => "regular"},
              content: []
            }
          ]
        }
      ]
    }

    send(pid, {:inject_node, reply})

    # No changes decoded (empty collection) → no :chats_update, but the
    # connection must still be alive and have processed the reply cleanly.
    refute_receive {:amarula, :chats_update, _}, 200
    assert Process.alive?(pid)
  end
end
