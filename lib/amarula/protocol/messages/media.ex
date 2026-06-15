defmodule Amarula.Protocol.Messages.Media do
  @moduledoc """
  WhatsApp media encryption + upload, ported from Baileys
  `src/Utils/messages-media.ts`.

  Flow for an outgoing media message:

    1. `media_key` = 32 random bytes.
    2. HKDF-SHA256 expand `media_key` to 112 bytes with info "WhatsApp <Type> Keys"
       → iv(16) ++ cipher_key(32) ++ mac_key(32) ++ ref_key(rest).
    3. `ciphertext = AES-256-CBC(cipher_key, iv, plaintext)`,
       `mac = HMAC-SHA256(mac_key, iv ++ ciphertext)` truncated to 10 bytes.
       The uploaded blob is `ciphertext ++ mac`.
    4. `file_sha256 = sha256(plaintext)`, `file_enc_sha256 = sha256(ciphertext ++ mac)`.
    5. Fetch a media connection (`<iq xmlns="w:m"><media_conn/>`), PUT the blob to
       `https://<host>/mms/<type>/<encSha256B64>?auth=..&token=..`, get `direct_path`/url.
    6. Build the per-type message (e.g. `%Proto.Message{imageMessage: ...}`).

  `decrypt/2` reverses 2–3 for a downloaded blob.
  """

  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Crypto.{Constants, Crypto}
  alias Amarula.Connection

  @hkdf_info %{
    image: "WhatsApp Image Keys",
    video: "WhatsApp Video Keys",
    audio: "WhatsApp Audio Keys",
    document: "WhatsApp Document Keys",
    sticker: "WhatsApp Image Keys",
    history: "WhatsApp History Keys"
  }

  @default_media_host "mmg.whatsapp.net"

  @path %{
    image: "/mms/image",
    video: "/mms/video",
    audio: "/mms/audio",
    document: "/mms/document",
    sticker: "/mms/image"
  }

  @type media_type :: :image | :video | :audio | :document | :sticker | :history

  @doc """
  Download an encrypted media blob from a message's `:directPath` (or `:url`) and
  decrypt it for `type`. `ref` is a map/struct with `direct_path`/`directPath` or
  `url`, plus `media_key`/`mediaKey`. Returns `{:ok, plaintext}` (still possibly
  compressed — history blobs are zlib-deflated; the caller inflates).
  """
  @spec download(map(), media_type()) :: {:ok, binary()} | {:error, term()}
  def download(ref, type) do
    media_key = media_key(ref)
    url = download_url(ref)

    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: enc}} when is_binary(enc) -> decrypt(enc, media_key, type)
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp media_key(ref), do: Map.get(ref, :media_key) || Map.get(ref, :mediaKey)

  defp download_url(ref) do
    case Map.get(ref, :direct_path) || Map.get(ref, :directPath) do
      nil -> Map.get(ref, :url)
      path -> "https://#{@default_media_host}#{path}"
    end
  end

  @doc """
  Encrypt `plaintext` for media `type`. Returns the uploadable blob plus the
  hashes/key the message stanza needs.
  """
  @spec encrypt(binary(), media_type()) ::
          {:ok,
           %{
             enc: binary(),
             media_key: binary(),
             file_sha256: binary(),
             file_enc_sha256: binary(),
             file_length: non_neg_integer()
           }}
  def encrypt(plaintext, type) when is_binary(plaintext) do
    media_key = :crypto.strong_rand_bytes(32)
    %{iv: iv, cipher_key: cipher_key, mac_key: mac_key} = media_keys(media_key, type)

    padded = pkcs7_pad(plaintext)
    ciphertext = :crypto.crypto_one_time(:aes_256_cbc, cipher_key, iv, padded, true)
    mac = :crypto.macN(:hmac, :sha256, mac_key, iv <> ciphertext, 10)
    enc = ciphertext <> mac

    {:ok,
     %{
       enc: enc,
       media_key: media_key,
       file_sha256: :crypto.hash(:sha256, plaintext),
       file_enc_sha256: :crypto.hash(:sha256, enc),
       file_length: byte_size(plaintext)
     }}
  end

  @doc """
  Decrypt a downloaded media blob (`ciphertext ++ mac`) with its `media_key`.
  Verifies the MAC before decrypting. Returns the plaintext.
  """
  @spec decrypt(binary(), binary(), media_type()) :: {:ok, binary()} | {:error, term()}
  def decrypt(enc, media_key, type) when is_binary(enc) and is_binary(media_key) do
    %{iv: iv, cipher_key: cipher_key, mac_key: mac_key} = media_keys(media_key, type)

    ciphertext = binary_part(enc, 0, byte_size(enc) - 10)
    mac = binary_part(enc, byte_size(enc) - 10, 10)
    expected = :crypto.macN(:hmac, :sha256, mac_key, iv <> ciphertext, 10)

    if byte_size(mac) == byte_size(expected) and :crypto.hash_equals(mac, expected) do
      padded = :crypto.crypto_one_time(:aes_256_cbc, cipher_key, iv, ciphertext, false)
      {:ok, pkcs7_unpad(padded)}
    else
      {:error, :bad_mac}
    end
  end

  # PKCS#7 pad/unpad to the 16-byte AES block (crypto_one_time needs aligned input).
  defp pkcs7_pad(data) do
    pad = 16 - rem(byte_size(data), 16)
    data <> :binary.copy(<<pad>>, pad)
  end

  defp pkcs7_unpad(data) do
    pad = :binary.last(data)
    binary_part(data, 0, byte_size(data) - pad)
  end

  @doc """
  Upload an encrypted blob to the media servers. `conn` is the Connection;
  returns `{:ok, %{direct_path: .., url: ..}}`.
  """
  @spec upload(GenServer.server(), binary(), binary(), media_type()) ::
          {:ok, %{direct_path: String.t() | nil, url: String.t()}} | {:error, term()}
  def upload(conn, enc, file_enc_sha256, type) do
    with {:ok, %{hosts: hosts, auth: auth}} <- media_conn(conn) do
      token = Base.url_encode64(file_enc_sha256, padding: false)
      put_to_hosts(hosts, type, token, auth, enc)
    end
  end

  # --- key derivation ---

  defp media_keys(media_key, type) do
    info = Map.fetch!(@hkdf_info, type)
    # RFC 5869: empty salt is HashLen (32) zero bytes.
    expanded = Crypto.hkdf(media_key, 112, <<0::256>>, info)
    <<iv::binary-16, cipher_key::binary-32, mac_key::binary-32, _ref::binary>> = expanded
    %{iv: iv, cipher_key: cipher_key, mac_key: mac_key}
  end

  # --- media connection + upload ---

  defp media_conn(conn) do
    iq = %Node{
      tag: "iq",
      attrs: [{"to", Constants.s_whatsapp_net()}, {"type", "set"}, {"xmlns", "w:m"}],
      content: [%Node{tag: "media_conn", attrs: %{}, content: nil}]
    }

    with {:ok, reply} <- Connection.query_iq(conn, iq),
         %Node{} = mc <- NodeUtils.get_binary_node_child(reply, "media_conn") do
      hosts =
        mc
        |> NodeUtils.get_binary_node_children("host")
        |> Enum.map(&NodeUtils.get_attr(&1, "hostname"))
        |> Enum.reject(&is_nil/1)

      {:ok, %{hosts: hosts, auth: NodeUtils.get_attr(mc, "auth")}}
    else
      nil -> {:error, :no_media_conn}
      error -> error
    end
  end

  defp put_to_hosts([], _type, _token, _auth, _enc), do: {:error, :all_hosts_failed}

  defp put_to_hosts([host | rest], type, token, auth, enc) do
    url = "https://#{host}#{Map.fetch!(@path, type)}/#{token}?auth=#{auth}&token=#{token}"

    case Req.post(url, body: enc, headers: [{"content-type", "application/octet-stream"}]) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, %{direct_path: body["direct_path"], url: body["url"] || ""}}

      _ ->
        put_to_hosts(rest, type, token, auth, enc)
    end
  end
end
