defmodule Amarula.Protocol.Signal.PreKeysTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Crypto.Crypto
  alias Amarula.Protocol.Signal.PreKeys

  defp fresh_creds do
    identity = Crypto.generate_key_pair()
    signed_pair = Crypto.generate_key_pair()

    %{
      registration_id: 12_345,
      signed_identity_key: identity,
      signed_pre_key: %{
        key_pair: signed_pair,
        key_id: 1,
        signature: :binary.copy(<<7>>, 64)
      },
      next_pre_key_id: 1,
      first_unuploaded_pre_key_id: 1,
      pre_keys: %{}
    }
  end

  test "generate_or_get_pre_keys generates only the missing range" do
    creds = fresh_creds()

    {new_keys, last_id, {first_id, range}} = PreKeys.generate_or_get_pre_keys(creds, 5)

    assert map_size(new_keys) == 5
    assert Map.keys(new_keys) |> Enum.sort() == [1, 2, 3, 4, 5]
    assert last_id == 5
    assert {first_id, range} == {1, 5}

    # With 3 generated-but-unuploaded keys, only 2 more are needed for range 5.
    creds = %{creds | next_pre_key_id: 4, pre_keys: %{1 => :a, 2 => :b, 3 => :c}}
    {new_keys, last_id, {first_id, _}} = PreKeys.generate_or_get_pre_keys(creds, 5)

    assert Map.keys(new_keys) |> Enum.sort() == [4, 5]
    assert last_id == 5
    assert first_id == 1
  end

  test "get_next_pre_keys_node advances watermarks and stores the new keys" do
    {creds, _node} = PreKeys.get_next_pre_keys_node(fresh_creds(), 5)

    assert creds.next_pre_key_id == 6
    assert creds.first_unuploaded_pre_key_id == 6
    assert map_size(creds.pre_keys) == 5
    assert %{public: <<_::256>>, private: <<_::256>>} = creds.pre_keys[3]
  end

  test "get_next_pre_keys_node builds the upload IQ matching getNextPreKeysNode" do
    creds = fresh_creds()
    {updated_creds, node} = PreKeys.get_next_pre_keys_node(creds, 5)

    assert %Node{tag: "iq"} = node
    attrs = Map.new(node.attrs)
    assert attrs == %{"xmlns" => "encrypt", "type" => "set", "to" => "@s.whatsapp.net"}

    # registration: 4-byte big-endian
    assert NodeUtils.get_child_content(node, "registration") == <<12_345::32>>
    # KEY_BUNDLE_TYPE
    assert NodeUtils.get_child_content(node, "type") == <<5>>
    assert NodeUtils.get_child_content(node, "identity") == creds.signed_identity_key.public

    list = NodeUtils.get_binary_node_child(node, "list")
    keys = NodeUtils.get_binary_node_children(list, "key")
    assert length(keys) == 5

    first = hd(keys)
    # prekey ids: 3-byte big-endian
    assert NodeUtils.get_child_content(first, "id") == <<0, 0, 1>>
    assert NodeUtils.get_child_content(first, "value") == updated_creds.pre_keys[1].public

    skey = NodeUtils.get_binary_node_child(node, "skey")
    assert NodeUtils.get_child_content(skey, "id") == <<0, 0, 1>>
    assert NodeUtils.get_child_content(skey, "value") == creds.signed_pre_key.key_pair.public
    assert NodeUtils.get_child_content(skey, "signature") == creds.signed_pre_key.signature
  end

  test "creds without prekey fields (pre-upgrade saves) default to id 1" do
    creds = fresh_creds() |> Map.drop([:next_pre_key_id, :first_unuploaded_pre_key_id, :pre_keys])

    {updated_creds, node} = PreKeys.get_next_pre_keys_node(creds, 3)

    assert updated_creds.next_pre_key_id == 4
    assert updated_creds.first_unuploaded_pre_key_id == 4
    assert map_size(updated_creds.pre_keys) == 3

    list = NodeUtils.get_binary_node_child(node, "list")
    assert length(NodeUtils.get_binary_node_children(list, "key")) == 3
  end
end
