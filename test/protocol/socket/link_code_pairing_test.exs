defmodule Amarula.Protocol.Socket.LinkCodePairingTest do
  @moduledoc """
  Drives the real `Amarula.Connection` through the link-code (phone-number)
  pairing flow using the same test seams as send_flow_test:

    * `connection_state: :connected` — skip the handshake
    * `frame_sink: self()` — capture outbound nodes (the companion_hello /
      companion_finish IQs)
    * `{:inject_node, node}` — feed the synthetic server notification

  Asserts the request side (mints an 8-char code + frames companion_hello), the
  finish side (companion_finish IQ shape, registered=true, adv re-keyed), the
  Baileys #2600 guard (a fieldless notification is skipped, not a crash), and
  custom-code validation.
  """
  # async: false — these start real Connections that register in the shared,
  # process-global Amarula.ProfileRegistry; running them concurrently races
  # registration/deregistration across tests.
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Amarula.Connection
  alias Amarula.Protocol.Auth.AuthUtils
  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Crypto.Crypto

  setup do
    dir = Path.join(System.tmp_dir!(), "amarula_linkcode_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    config = %{
      wa_websocket_url: "wss://test.example.com/ws",
      max_retries: 1,
      retry_delay: 100,
      connection_state: :connected,
      frame_sink: self(),
      browser: ["Mac OS", "Chrome", "14.4.1"],
      # Unique per test: the profile registry (one Connection per profile) would
      # otherwise reject a second concurrent start of the same profile.
      profile: :"linkcode_test_#{System.unique_integer([:positive])}",
      storage: {Amarula.Storage.File, root: dir},
      auth: AuthUtils.init_auth_creds()
    }

    # A unique registered name: start_link defaults to `name: Amarula.Connection`,
    # which collides across this async test file's concurrent starts.
    {:ok, pid} =
      Connection.start_link(config,
        name: :"linkcode_conn_#{System.unique_integer([:positive])}",
        parent_pid: self()
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    {:ok, pid: pid}
  end

  describe "request_pairing_code/3" do
    test "mints an 8-char code, sets me, and frames a companion_hello IQ", %{pid: pid} do
      assert {:ok, code} = Connection.request_pairing_code(pid, "15551234567")
      assert byte_size(code) == 8
      assert code =~ ~r/^[123456789ABCDEFGHJKLMNPQRSTVWXYZ]{8}$/

      # Consumer is told the code.
      assert_receive {:amarula, :pairing_code, %{code: ^code}}

      iq = recv_frame()
      assert iq.tag == "iq"
      assert attr(iq, "xmlns") == "md"
      assert attr(iq, "type") == "set"

      reg = NodeUtils.get_binary_node_child(iq, "link_code_companion_reg")
      assert attr(reg, "stage") == "companion_hello"
      assert attr(reg, "jid") == "15551234567@s.whatsapp.net"

      # All five companion_hello children present.
      for tag <- ~w(link_code_pairing_wrapped_companion_ephemeral_pub
                    companion_server_auth_key_pub companion_platform_id
                    companion_platform_display link_code_pairing_nonce) do
        assert NodeUtils.get_binary_node_child(reg, tag), "missing child #{tag}"
      end

      # Chrome on Mac OS → platform id "1", display "Chrome (Mac OS)".
      assert child_content(reg, "companion_platform_id") == "1"
      assert child_content(reg, "companion_platform_display") == "Chrome (Mac OS)"
      assert child_content(reg, "link_code_pairing_nonce") == "0"

      # The wrapped key is salt(32)+iv(16)+ciphered(32) = 80 bytes.
      wrapped = child_content(reg, "link_code_pairing_wrapped_companion_ephemeral_pub")
      assert byte_size(wrapped) == 80

      creds = Connection.get_auth_creds(pid)
      assert creds.pairing_code == code
      assert creds.me.id == "15551234567@s.whatsapp.net"
    end

    test "strips non-digits from the phone number", %{pid: pid} do
      assert {:ok, _code} = Connection.request_pairing_code(pid, "+1 (555) 123-4567")
      _hello = recv_frame()
      assert Connection.get_auth_creds(pid).me.id == "15551234567@s.whatsapp.net"
    end

    test "accepts a valid 8-char custom code", %{pid: pid} do
      assert {:ok, "ABCD2345"} =
               Connection.request_pairing_code(pid, "15551234567", custom_code: "ABCD2345")

      assert_receive {:amarula, :pairing_code, %{code: "ABCD2345"}}
    end

    test "rejects a custom code that isn't exactly 8 chars", %{pid: pid} do
      assert {:error, :custom_pairing_code_must_be_8_chars} =
               Connection.request_pairing_code(pid, "15551234567", custom_code: "SHORT")
    end
  end

  describe "link_code_companion_reg notification (finish)" do
    test "finishes pairing: companion_finish IQ, registered=true, adv re-keyed", %{pid: pid} do
      assert {:ok, code} = Connection.request_pairing_code(pid, "15551234567")
      assert_receive {:amarula, :pairing_code, %{code: ^code}}
      _hello = recv_frame()

      before = Connection.get_auth_creds(pid)
      refute before.registered

      # Build a synthetic server notification carrying the phone's primary
      # identity pub + a wrapped ephemeral pub the connection can decipher with
      # the code it just minted.
      primary_identity_pub = Crypto.generate_key_pair().public
      code_pairing = Crypto.generate_key_pair()
      ref = "pair-ref-123"

      salt = Crypto.random_bytes(32)
      iv = Crypto.random_bytes(16)
      key = Crypto.derive_pairing_code_key(code, salt)
      wrapped = salt <> iv <> Crypto.aes_encrypt_ctr(code_pairing.public, key, iv)

      notif =
        Node.create("notification", %{"type" => "link_code_companion_reg", "id" => "n1"}, [
          Node.create("link_code_companion_reg", %{}, [
            Node.create("link_code_pairing_ref", %{}, ref),
            Node.create("primary_identity_pub", %{}, primary_identity_pub),
            Node.create("link_code_pairing_wrapped_primary_ephemeral_pub", %{}, wrapped)
          ])
        ])

      send(pid, {:inject_node, notif})

      finish = recv_iq("companion_finish")
      reg = NodeUtils.get_binary_node_child(finish, "link_code_companion_reg")
      assert attr(reg, "stage") == "companion_finish"
      assert child_content(reg, "link_code_pairing_ref") == ref

      # Bundle = salt(32) + iv(12) + GCM(96-byte payload + 16 tag) = 156 bytes.
      bundle = child_content(reg, "link_code_pairing_wrapped_key_bundle")
      assert byte_size(bundle) == 32 + 12 + 96 + 16

      after_creds = Connection.get_auth_creds(pid)
      assert after_creds.registered
      assert after_creds.adv_secret_key != before.adv_secret_key
      assert_receive {:amarula, :pairing_success, %{via: :link_code}}
    end

    test "a fieldless notification is skipped, not a crash (Baileys #2600)", %{pid: pid} do
      {:ok, _code} = Connection.request_pairing_code(pid, "15551234567")
      _hello = recv_frame()

      # The same tag arrives as a fieldless notification — the #2600 crash case.
      notif =
        Node.create("notification", %{"type" => "link_code_companion_reg", "id" => "n2"}, [
          Node.create("link_code_companion_reg", %{}, nil)
        ])

      send(pid, {:inject_node, notif})

      # No companion_finish is framed and the connection stays up.
      refute_receive {:frame_out, %Node{tag: "iq"}}, 200
      assert Process.alive?(pid)
      refute Connection.get_auth_creds(pid).registered
    end
  end

  defp recv_frame do
    receive do
      {:frame_out, node} -> node
    after
      1000 -> flunk("timed out waiting for an outbound frame")
    end
  end

  # Drain frames until an iq carrying a link_code_companion_reg at the given stage.
  defp recv_iq(stage) do
    iq = recv_frame()

    reg = NodeUtils.get_binary_node_child(iq, "link_code_companion_reg")

    if (iq.tag == "iq" and reg) && attr(reg, "stage") == stage do
      iq
    else
      recv_iq(stage)
    end
  end

  defp attr(%Node{attrs: attrs}, key) when is_list(attrs) do
    case List.keyfind(attrs, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  defp attr(node, key), do: NodeUtils.get_attr(node, key)

  defp child_content(node, tag) do
    case NodeUtils.get_binary_node_child(node, tag) do
      %Node{content: content} -> content
      nil -> nil
    end
  end
end
