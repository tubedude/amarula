defmodule Amarula.Protocol.Messages.MediaTest do
  use ExUnit.Case, async: false

  alias Amarula.Protocol.Messages.Media

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

    test "a corrupt blob fails the MAC check" do
      data = :crypto.strong_rand_bytes(200)
      {:ok, e} = Media.encrypt(data, :image)
      corrupt = :binary.part(e.enc, 0, byte_size(e.enc) - 1) <> <<:binary.last(e.enc) + 1>>

      Req.Test.stub(Media, fn conn -> Plug.Conn.send_resp(conn, 200, corrupt) end)

      ref = %{direct_path: "/v/t62/enc", media_key: e.media_key}
      assert {:error, :bad_mac} = Media.download(ref, :image)
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
end
