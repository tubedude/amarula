defmodule Amarula.Connection.PreKeyOpsTest do
  @moduledoc "Pure unit tests for the pre-key decision logic — no socket, no state."
  use ExUnit.Case, async: true

  alias Amarula.Connection.PreKeyOps
  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Signal.PreKeys

  describe "count_query_node/0" do
    test "is an encrypt count IQ" do
      node = PreKeyOps.count_query_node()

      assert %Node{tag: "iq"} = node
      assert {"xmlns", "encrypt"} in node.attrs
      assert {"type", "get"} in node.attrs
      assert [%Node{tag: "count"}] = node.content
    end
  end

  describe "server_count/1" do
    test "reads the <count value> attr" do
      node = %Node{tag: "iq", content: [%Node{tag: "count", attrs: %{"value" => "42"}}]}
      assert PreKeyOps.server_count(node) == 42
    end

    test "defaults to 0 when the count node is absent" do
      assert PreKeyOps.server_count(%Node{tag: "iq", content: []}) == 0
    end
  end

  describe "upload_target/1" do
    test "server holding none → the full initial batch" do
      assert PreKeyOps.upload_target(0) == PreKeys.initial_pre_key_count()
    end

    test "server holding some → tops up back toward the initial count (not just min)" do
      # #2643: refill restores the pool to initial, so a non-empty server uploads
      # (initial - server_count), not the old flat min top-up of 5.
      assert PreKeyOps.upload_target(50) == PreKeys.initial_pre_key_count() - 50
      assert PreKeyOps.upload_target(50) > PreKeys.min_pre_key_count()
    end

    test "never uploads fewer than the min, even if the server is already full" do
      assert PreKeyOps.upload_target(PreKeys.initial_pre_key_count()) ==
               PreKeys.min_pre_key_count()
    end
  end

  describe "upload_needed?/3 and missing_current_pre_key?/1" do
    test "uploads when the server pool is at/below the low-water mark" do
      assert PreKeyOps.upload_needed?(3, 0, %{next_pre_key_id: 1, pre_keys: %{}})
      # #2643: the trigger is the low-water mark, not min — a pool that idled at
      # a few dozen keys must still refill before it drains to zero.
      assert PreKeyOps.upload_needed?(PreKeys.low_water_pre_key_count(), 0, %{
               next_pre_key_id: 1,
               pre_keys: %{}
             })
    end

    test "skips when the server pool is above the low-water mark and current prekey is present" do
      creds = %{next_pre_key_id: 3, pre_keys: %{2 => :pair}}
      refute PreKeyOps.upload_needed?(PreKeys.low_water_pre_key_count() + 1, 0, creds)
    end

    test "uploads when the current prekey is missing locally, even with plenty on server" do
      creds = %{next_pre_key_id: 3, pre_keys: %{}}
      assert PreKeyOps.missing_current_pre_key?(creds)
      assert PreKeyOps.upload_needed?(500, 0, creds)
    end

    test "no current prekey to verify when next_pre_key_id is 1" do
      refute PreKeyOps.missing_current_pre_key?(%{next_pre_key_id: 1, pre_keys: %{}})
    end
  end
end
