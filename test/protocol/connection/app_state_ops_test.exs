defmodule Amarula.Connection.AppStateOpsTest do
  @moduledoc "Unit tests for the app-state helpers — no socket."
  use ExUnit.Case, async: true

  alias Amarula.Connection.AppStateOps

  describe "sync_keys/1 and sync_keys_in/1" do
    test "extracts {key_id_b64, key_data} from a key-share message" do
      msg = %{
        protocolMessage: %{
          appStateSyncKeyShare: %{
            keys: [%{keyId: %{keyId: "ID"}, keyData: %{keyData: "DATA"}}]
          }
        }
      }

      assert AppStateOps.sync_keys(msg) == [{Base.encode64("ID"), "DATA"}]
    end

    test "drops malformed key entries" do
      msg = %{
        protocolMessage: %{
          appStateSyncKeyShare: %{
            keys: [
              %{keyId: %{keyId: "ID"}, keyData: %{keyData: "DATA"}},
              %{keyId: %{keyId: nil}, keyData: %{keyData: "DATA"}},
              %{}
            ]
          }
        }
      }

      assert AppStateOps.sync_keys(msg) == [{Base.encode64("ID"), "DATA"}]
    end

    test "a message without a share yields []" do
      assert AppStateOps.sync_keys(%{protocolMessage: %{}}) == []
      assert AppStateOps.sync_keys(%{conversation: "hi"}) == []
    end

    test "sync_keys_in flattens across a batch" do
      share = fn id ->
        %{
          protocolMessage: %{
            appStateSyncKeyShare: %{keys: [%{keyId: %{keyId: id}, keyData: %{keyData: "D"}}]}
          }
        }
      end

      messages = [share.("A"), %{conversation: "x"}, share.("B")]

      assert AppStateOps.sync_keys_in(messages) ==
               [{Base.encode64("A"), "D"}, {Base.encode64("B"), "D"}]
    end
  end

  describe "store_shared_keys/3" do
    @describetag :tmp_dir

    test "stores new keys but never overwrites one with different data (whatsmeow #1333)",
         %{tmp_dir: dir} do
      conn = Amarula.TestConn.new(dir)

      share = fn id, data ->
        %{
          protocolMessage: %{
            appStateSyncKeyShare: %{keys: [%{keyId: %{keyId: id}, keyData: %{keyData: data}}]}
          }
        }
      end

      store = &AppStateOps.store_shared_keys(conn.storage, conn.profile, &1)

      get =
        &Amarula.Storage.get(conn.storage, conn.profile, :app_state_sync_key, Base.encode64(&1))

      assert store.([share.("A", "OLD")]) == 1

      assert ExUnit.CaptureLog.capture_log(fn -> assert store.([share.("A", "NEW")]) == 0 end) =~
               "Ignoring app-state sync key"

      assert get.("A") == {:ok, "OLD"}
      assert store.([share.("A", "OLD"), share.("B", "D")]) == 2
      assert get.("B") == {:ok, "D"}
    end
  end

  describe "partition_changes/1" do
    test "splits chat and contact changes, preserving order" do
      changes = [{:chat, :c1}, {:contact, :p1}, {:chat, :c2}, {:other, :x}]
      assert AppStateOps.partition_changes(changes) == {[:c1, :c2], [:p1]}
    end

    test "empty in, empty out" do
      assert AppStateOps.partition_changes([]) == {[], []}
    end
  end
end
