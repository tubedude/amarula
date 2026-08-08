defmodule Amarula.Protocol.Messages.MediaTest do
  use ExUnit.Case, async: false

  alias Amarula.Protocol.Messages.Media
  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Crypto.Crypto
  alias Amarula.Protocol.Proto

  test "encrypt/decrypt round-trips and verifies the MAC" do
    data = :crypto.strong_rand_bytes(5000)
    {:ok, e} = Media.encrypt(data, :image)

    assert byte_size(e.media_key) == 32
    assert e.file_length == 5000
    assert e.file_sha256 == :crypto.hash(:sha256, data)
    assert e.file_enc_sha256 == :crypto.hash(:sha256, e.enc)

    assert {:ok, ^data} = Media.decrypt(e.enc, e.media_key, :image)
  end

  test "decrypt rejects a tampered blob" do
    {:ok, e} = Media.encrypt(<<1, 2, 3>>, :image)
    tampered = binary_part(e.enc, 0, byte_size(e.enc) - 1) <> <<:binary.last(e.enc) + 1>>
    assert {:error, :bad_mac} = Media.decrypt(tampered, e.media_key, :image)
  end

  test "round-trips a block-aligned payload (exercises PKCS#7 full block)" do
    data = :crypto.strong_rand_bytes(48)
    {:ok, e} = Media.encrypt(data, :document)
    assert {:ok, ^data} = Media.decrypt(e.enc, e.media_key, :document)
  end

  describe "download/2 (HTTP stubbed via Req.Test)" do
    setup do
      # Route Media's Req.get through a per-test Req.Test stub instead of the CDN.
      Application.put_env(:amarula, :req_options, plug: {Req.Test, Media})
      on_exit(fn -> Application.delete_env(:amarula, :req_options) end)
      :ok
    end

    test "fetches the blob and decrypts it" do
      data = :crypto.strong_rand_bytes(1000)
      {:ok, e} = Media.encrypt(data, :image)

      Req.Test.stub(Media, fn conn -> Plug.Conn.send_resp(conn, 200, e.enc) end)

      ref = %{direct_path: "/v/t62/enc", media_key: e.media_key}
      assert {:ok, ^data} = Media.download(ref, :image)
    end

    test "accepts a normalized %Amarula.Content.Media{} descriptor (the inbound shape)" do
      data = :crypto.strong_rand_bytes(64)
      {:ok, e} = Media.encrypt(data, :video)

      Req.Test.stub(Media, fn conn -> Plug.Conn.send_resp(conn, 200, e.enc) end)

      ref = %Amarula.Content.Media{
        kind: :video,
        direct_path: "/v/t62/enc",
        media_key: e.media_key
      }

      assert {:ok, ^data} = Media.download(ref, :video)
    end

    test "verifies the declared plaintext hash when present" do
      data = :crypto.strong_rand_bytes(300)
      {:ok, e} = Media.encrypt(data, :image)

      Req.Test.stub(Media, fn conn -> Plug.Conn.send_resp(conn, 200, e.enc) end)

      ref = %{direct_path: "/v/t62/enc", media_key: e.media_key, file_sha256: e.file_sha256}
      assert {:ok, ^data} = Media.download(ref, :image)
    end

    test "a wrong plaintext hash is rejected after decrypt (:bad_file_hash)" do
      data = :crypto.strong_rand_bytes(300)
      {:ok, e} = Media.encrypt(data, :image)

      Req.Test.stub(Media, fn conn -> Plug.Conn.send_resp(conn, 200, e.enc) end)

      ref = %{
        direct_path: "/v/t62/enc",
        media_key: e.media_key,
        file_sha256: :crypto.strong_rand_bytes(32)
      }

      assert {:error, :bad_file_hash} = Media.download(ref, :image)
    end

    test "surfaces a non-200 (expired URL) as {:http, status}" do
      Req.Test.stub(Media, fn conn -> Plug.Conn.send_resp(conn, 404, "gone") end)

      ref = %{direct_path: "/v/t62/expired", media_key: :crypto.strong_rand_bytes(32)}
      assert {:error, {:http, 404}} = Media.download(ref, :image)
    end

    # Contract: a malformed descriptor must return {:error, _} per the @spec — not
    # raise a Req/BadMapError up through a typed caller (which forced consumers to
    # wrap the call in rescue). No HTTP stub needed; these short-circuit before Req.
    test "a descriptor missing the URL/path returns {:error, :invalid_media}" do
      assert {:error, :invalid_media} = Media.download(%{media_key: "k"}, :image)
    end

    test "a descriptor missing the media key returns {:error, :invalid_media}" do
      assert {:error, :invalid_media} = Media.download(%{direct_path: "/v/x"}, :image)
    end

    test "a nil / non-map descriptor returns {:error, :invalid_media} (does not raise)" do
      assert {:error, :invalid_media} = Media.download(nil, :image)
      assert {:error, :invalid_media} = Media.download(%{}, :image)
    end

    # A 200 whose body is not a media blob at all (a CDN error page, a truncated
    # response) must come back as an error tuple. These used to raise out of
    # binary_part/crypto — which is why consumers wrapped the call in a rescue.
    test "a 200 that is not a blob errors instead of raising" do
      for body <- ["", "nope", "<html>404</html>", :crypto.strong_rand_bytes(11)] do
        Req.Test.stub(Media, fn conn -> Plug.Conn.send_resp(conn, 200, body) end)

        ref = %{direct_path: "/v/t62/enc", media_key: :crypto.strong_rand_bytes(32)}
        assert {:error, reason} = Media.download(ref, :image)
        assert reason in [:bad_mac, :bad_padding]
      end
    end

    test "an unknown media type errors instead of raising in key derivation" do
      ref = %{direct_path: "/v/t62/enc", media_key: :crypto.strong_rand_bytes(32)}
      assert {:error, :invalid_media} = Media.download(ref, :gif)
    end

    test "a wrong-sized media key returns {:error, :invalid_media}" do
      ref = %{direct_path: "/v/t62/enc", media_key: <<0::248>>}
      assert {:error, :invalid_media} = Media.download(ref, :image)
    end

    test "a corrupt blob fails the MAC check" do
      data = :crypto.strong_rand_bytes(200)
      {:ok, e} = Media.encrypt(data, :image)
      corrupt = :binary.part(e.enc, 0, byte_size(e.enc) - 1) <> <<:binary.last(e.enc) + 1>>

      Req.Test.stub(Media, fn conn -> Plug.Conn.send_resp(conn, 200, corrupt) end)

      ref = %{direct_path: "/v/t62/enc", media_key: e.media_key}
      assert {:error, :bad_mac} = Media.download(ref, :image)
    end
  end

  # A descriptor rebuilt from stored or transported data can name any host in its
  # `:url`. download/2 decides where to fetch from, so the check belongs here — not
  # in every consumer that rehydrates one.
  describe "download/2 locator validation" do
    setup do
      Application.put_env(:amarula, :req_options, plug: {Req.Test, Media})
      on_exit(fn -> Application.delete_env(:amarula, :req_options) end)

      # Any request at all is a failure in this block: validation runs before Req.
      Req.Test.stub(Media, fn conn ->
        flunk("download/2 issued an HTTP request to #{conn.host}#{conn.request_path}")
      end)
    end

    test "refuses a :url that is not https on a WhatsApp host" do
      for url <- [
            "https://evil.example.com/v/enc",
            "https://mmg.whatsapp.net.evil.example.com/v/enc",
            "http://mmg.whatsapp.net/v/enc",
            "https://mmg.whatsapp.net@evil.example.com/v/enc",
            "https://mmg.whatsapp.net/v/ enc",
            "https://mmg.whatsapp.net/v/enc\r\nX-Injected: 1",
            "file:///etc/passwd"
          ] do
        ref = %{url: url, media_key: :crypto.strong_rand_bytes(32)}

        assert {:error, :untrusted_media_url} = Media.download(ref, :image),
               "expected #{url} to be refused"
      end
    end

    test "refuses a :direct_path that could reach the authority" do
      for path <- ["@evil.example.com/v/enc", "v/enc", "/v/enc\r\nX: 1"] do
        ref = %{direct_path: path, media_key: :crypto.strong_rand_bytes(32)}

        assert {:error, :unsafe_direct_path} = Media.download(ref, :image),
               "expected #{inspect(path)} to be refused"
      end
    end

    test "an untrusted :url alongside a good :direct_path is simply not used" do
      data = :crypto.strong_rand_bytes(64)
      {:ok, e} = Media.encrypt(data, :image)
      Req.Test.stub(Media, fn conn -> Plug.Conn.send_resp(conn, 200, e.enc) end)

      ref = %{
        direct_path: "/v/t62/enc",
        url: "https://evil.example.com/x",
        media_key: e.media_key
      }

      assert {:ok, ^data} = Media.download(ref, :image)
    end

    test "accepts a WhatsApp :url when it is the only locator (any subdomain, any case)" do
      data = :crypto.strong_rand_bytes(64)
      {:ok, e} = Media.encrypt(data, :image)
      Req.Test.stub(Media, fn conn -> Plug.Conn.send_resp(conn, 200, e.enc) end)

      for url <- ["https://media-fra3-1.whatsapp.net/v/enc", "https://MMG.WhatsApp.NET/v/enc"] do
        assert {:ok, ^data} = Media.download(%{url: url, media_key: e.media_key}, :image)
      end
    end
  end

  describe "upload/4 (HTTP stubbed via Req.Test)" do
    alias Amarula.Protocol.Binary.Node

    setup do
      Application.put_env(:amarula, :req_options, plug: {Req.Test, Media})
      on_exit(fn -> Application.delete_env(:amarula, :req_options) end)
      :ok
    end

    # A minimal stand-in for Connection: answers the one query_iq call
    # (media_conn) that upload/4 makes before PUTting to the hosts.
    defp stub_conn(media_conn_reply) do
      spawn_link(fn ->
        receive do
          {:"$gen_call", from, {:query_iq, _node}} ->
            GenServer.reply(from, {:ok, media_conn_reply})
        end
      end)
    end

    test "the upload PUT routes through req_options like download does" do
      reply = %Node{
        tag: "iq",
        attrs: %{"type" => "result"},
        content: [
          %Node{
            tag: "media_conn",
            attrs: %{"auth" => "AUTHTOKEN"},
            content: [%Node{tag: "host", attrs: %{"hostname" => "mmg.example.net"}, content: nil}]
          }
        ]
      }

      # Without the req_options merge on the upload path this would hit the real
      # network (and fail with :all_hosts_failed) instead of the stub.
      Req.Test.stub(Media, fn conn ->
        Req.Test.json(conn, %{"direct_path" => "/mms/image/abc", "url" => "https://cdn/abc"})
      end)

      assert {:ok, %{direct_path: "/mms/image/abc", url: "https://cdn/abc"}} =
               Media.upload(stub_conn(reply), <<1, 2, 3>>, :crypto.strong_rand_bytes(32), :image)
    end
  end

  describe "media retry (server-error receipt / mediaretry notification)" do
    test "build_retry_receipt encrypts a ServerErrorReceipt that decrypts back (round-trip)" do
      media_key = :crypto.strong_rand_bytes(32)
      msg_id = "ABCD1234"

      node =
        Media.build_retry_receipt(
          msg_id,
          "me@s.whatsapp.net",
          "peer@s.whatsapp.net",
          false,
          nil,
          media_key
        )

      assert node.tag == "receipt"
      assert Map.new(node.attrs)["type"] == "server-error"
      assert Map.new(node.attrs)["to"] == "me@s.whatsapp.net"

      encrypt = NodeUtils.get_binary_node_child(node, "encrypt")
      enc_p = NodeUtils.get_binary_node_child(encrypt, "enc_p").content
      iv = NodeUtils.get_binary_node_child(encrypt, "enc_iv").content

      # The phone decrypts it with the same retry key + msg_id AAD → ServerErrorReceipt.
      {:ok, plain} = Crypto.aes_decrypt_gcm(enc_p, Media.retry_key(media_key), iv, msg_id)
      assert %Proto.ServerErrorReceipt{stanzaId: ^msg_id} = Proto.ServerErrorReceipt.decode(plain)
    end

    test "build_retry_receipt sets participant on <rmr> for a group" do
      node =
        Media.build_retry_receipt(
          "m",
          "me@s.whatsapp.net",
          "g@g.us",
          false,
          "sender@s.whatsapp.net",
          :crypto.strong_rand_bytes(32)
        )

      rmr = NodeUtils.get_binary_node_child(node, "rmr")
      assert Map.new(rmr.attrs)["jid"] == "g@g.us"
      assert Map.new(rmr.attrs)["participant"] == "sender@s.whatsapp.net"
    end

    test "decode_retry_notification decrypts a SUCCESS reply to the new directPath" do
      media_key = :crypto.strong_rand_bytes(32)
      msg_id = "XYZ"
      iv = :crypto.strong_rand_bytes(12)

      payload =
        Proto.MediaRetryNotification.encode(%Proto.MediaRetryNotification{
          stanzaId: msg_id,
          result: :SUCCESS,
          directPath: "/v/new/path"
        })

      {:ok, enc_p} = Crypto.aes_encrypt_gcm(payload, Media.retry_key(media_key), iv, msg_id)

      # Inbound (decoded) nodes carry MAP attrs, unlike the ordered-list attrs we
      # build for outbound stanzas.
      node = %Node{
        tag: "notification",
        attrs: %{"id" => msg_id, "type" => "mediaretry"},
        content: [
          %Node{
            tag: "encrypt",
            attrs: %{},
            content: [
              %Node{tag: "enc_p", attrs: %{}, content: enc_p},
              %Node{tag: "enc_iv", attrs: %{}, content: iv}
            ]
          }
        ]
      }

      assert {:ok, "/v/new/path"} = Media.decode_retry_notification(node, media_key)
    end

    test "decode_retry_notification returns :not_on_phone on <error code=2>" do
      node = %Node{
        tag: "notification",
        attrs: %{"id" => "m", "type" => "mediaretry"},
        content: [%Node{tag: "error", attrs: %{"code" => "2"}, content: nil}]
      }

      assert {:error, :not_on_phone} =
               Media.decode_retry_notification(node, :crypto.strong_rand_bytes(32))
    end
  end
end
