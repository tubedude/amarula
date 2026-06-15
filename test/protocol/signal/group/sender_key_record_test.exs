defmodule Amarula.Protocol.Signal.Group.SenderKeyRecordTest do
  use ExUnit.Case, async: true
  alias Amarula.Protocol.Signal.Group.{SenderKeyRecord, SenderKeyState}

  describe "new/0" do
    test "creates an empty record" do
      record = SenderKeyRecord.new()

      assert SenderKeyRecord.empty?(record)
      assert SenderKeyRecord.state_count(record) == 0
    end
  end

  describe "from_serialized/1" do
    test "creates record from serialized data" do
      serialized_data = [
        %{
          sender_key_id: 1,
          sender_chain_key: %{iteration: 5, seed: :crypto.strong_rand_bytes(32)},
          sender_signing_key: %{
            public: :crypto.strong_rand_bytes(32),
            private: :crypto.strong_rand_bytes(32)
          },
          sender_message_keys: []
        }
      ]

      record = SenderKeyRecord.from_serialized(serialized_data)

      refute SenderKeyRecord.empty?(record)
      assert SenderKeyRecord.state_count(record) == 1
    end
  end

  describe "add_sender_key_state/2" do
    test "adds a sender key state" do
      record = SenderKeyRecord.new()
      state = create_test_state(1)

      updated_record = SenderKeyRecord.add_sender_key_state(record, state)

      assert SenderKeyRecord.state_count(updated_record) == 1
      refute SenderKeyRecord.empty?(updated_record)
    end

    test "limits states to max count" do
      record = SenderKeyRecord.new()

      # Add more than max states
      updated_record =
        Enum.reduce(1..6, record, fn i, acc ->
          state = create_test_state(i)
          SenderKeyRecord.add_sender_key_state(acc, state)
        end)

      assert SenderKeyRecord.state_count(updated_record) == 5
    end
  end

  describe "get_sender_key_state/2" do
    test "returns state with matching key ID" do
      record = SenderKeyRecord.new()
      state1 = create_test_state(1)
      state2 = create_test_state(2)

      record =
        record
        |> SenderKeyRecord.add_sender_key_state(state1)
        |> SenderKeyRecord.add_sender_key_state(state2)

      assert {:ok, found_state} = SenderKeyRecord.get_sender_key_state(record, 1)
      assert found_state == state1

      assert {:ok, found_state} = SenderKeyRecord.get_sender_key_state(record, 2)
      assert found_state == state2
    end

    test "returns error for non-existent key ID" do
      record = SenderKeyRecord.new()
      state = create_test_state(1)
      record = SenderKeyRecord.add_sender_key_state(record, state)

      assert {:error, reason} = SenderKeyRecord.get_sender_key_state(record, 999)
      assert reason =~ "Sender key state not found for key ID 999"
    end
  end

  describe "get_sender_key_state/1" do
    test "returns the most recent state" do
      record = SenderKeyRecord.new()
      state1 = create_test_state(1)
      state2 = create_test_state(2)

      record =
        record
        |> SenderKeyRecord.add_sender_key_state(state1)
        |> SenderKeyRecord.add_sender_key_state(state2)

      assert {:ok, most_recent_state} = SenderKeyRecord.get_sender_key_state(record)
      # Most recently added
      assert most_recent_state == state2
    end

    test "returns error for empty record" do
      record = SenderKeyRecord.new()
      assert {:error, reason} = SenderKeyRecord.get_sender_key_state(record)
      assert reason =~ "No sender key states available"
    end
  end

  describe "empty?/1" do
    test "returns true for empty record" do
      record = SenderKeyRecord.new()
      assert SenderKeyRecord.empty?(record)
    end

    test "returns false for non-empty record" do
      record = SenderKeyRecord.new()
      state = create_test_state(1)
      record = SenderKeyRecord.add_sender_key_state(record, state)

      refute SenderKeyRecord.empty?(record)
    end
  end

  describe "state_count/1" do
    test "returns correct count" do
      record = SenderKeyRecord.new()
      assert SenderKeyRecord.state_count(record) == 0

      state1 = create_test_state(1)
      record = SenderKeyRecord.add_sender_key_state(record, state1)
      assert SenderKeyRecord.state_count(record) == 1

      state2 = create_test_state(2)
      record = SenderKeyRecord.add_sender_key_state(record, state2)
      assert SenderKeyRecord.state_count(record) == 2
    end
  end

  describe "serialize/1" do
    test "serializes record to list of maps" do
      record = SenderKeyRecord.new()
      state = create_test_state(1)
      record = SenderKeyRecord.add_sender_key_state(record, state)

      serialized = SenderKeyRecord.serialize(record)

      assert is_list(serialized)
      assert length(serialized) == 1

      [serialized_state] = serialized
      assert serialized_state.sender_key_id == 1
      assert is_map(serialized_state.sender_chain_key)
      assert is_map(serialized_state.sender_signing_key)
      assert is_list(serialized_state.sender_message_keys)
    end
  end

  describe "round-trip serialization" do
    test "serialize and from_serialized are inverse operations" do
      record = SenderKeyRecord.new()
      state1 = create_test_state(1)
      state2 = create_test_state(2)

      original_record =
        record
        |> SenderKeyRecord.add_sender_key_state(state1)
        |> SenderKeyRecord.add_sender_key_state(state2)

      serialized = SenderKeyRecord.serialize(original_record)
      reconstructed_record = SenderKeyRecord.from_serialized(serialized)

      assert SenderKeyRecord.state_count(reconstructed_record) == 2
      assert {:ok, _} = SenderKeyRecord.get_sender_key_state(reconstructed_record, 1)
      assert {:ok, _} = SenderKeyRecord.get_sender_key_state(reconstructed_record, 2)
    end
  end

  # Helper function to create a test state
  defp create_test_state(key_id) do
    signing_key = %{public: :crypto.strong_rand_bytes(32), private: :crypto.strong_rand_bytes(32)}
    SenderKeyState.new(key_id, 5, :crypto.strong_rand_bytes(32), signing_key)
  end
end
