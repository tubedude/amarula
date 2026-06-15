defmodule Amarula.Protocol.Socket.LoginTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Socket.Login

  # The handshake transforms (client_hello/server_hello/complete) delegate to
  # ConnectionValidator/NoiseHandler (covered by their own tests + the live
  # pairing run). Here we cover the pure login-bootstrap stanza builders.

  test "digest_iq builds <iq get xmlns=encrypt><digest/>" do
    iq = Login.digest_iq()
    attrs = Map.new(iq.attrs)
    assert attrs["type"] == "get"
    assert attrs["xmlns"] == "encrypt"
    assert %Node{tag: "digest"} = NodeUtils.get_binary_node_child(iq, "digest")
  end

  test "unified_session_node builds <ib><unified_session id=>" do
    node = Login.unified_session_node()
    assert node.tag == "ib"
    us = NodeUtils.get_binary_node_child(node, "unified_session")
    assert %Node{tag: "unified_session"} = us
    # id is a string of an integer in [0, 7 days in ms)
    {id, ""} = Integer.parse(NodeUtils.get_attr(us, "id"))
    assert id >= 0 and id < 7 * 24 * 60 * 60 * 1000
  end

  test "client_hello returns {:ok, frame, handshake_state} for valid creds" do
    creds = Amarula.Protocol.Auth.AuthUtils.init_auth_creds()
    config = %{version: [2, 3000, 1_035_194_821], browser: ["Mac OS", "Chrome", "1"]}

    assert {:ok, frame, handshake_state} = Login.client_hello(creds, config)
    assert is_binary(frame) and byte_size(frame) > 0
    assert is_map(handshake_state) and Map.has_key?(handshake_state, :noise_state)
  end
end
