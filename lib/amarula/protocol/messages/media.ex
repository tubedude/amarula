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

  require Logger

  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Crypto.{Constants, Crypto}
  alias Amarula.Protocol.Proto
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
  Download an encrypted media blob from a message's `:direct_path` (or `:url`) and
  decrypt it for `type`. `ref` is a map/struct with `:direct_path` (preferred) or
  `:url`, plus `:media_key` — the canonical snake_case shape of an inbound
  `%Amarula.Content.Media{}` (camelCase keys are no longer accepted). Returns
  `{:ok, plaintext}` (still possibly compressed — history blobs are zlib-deflated;
  the caller inflates).
  """
  @spec download(map(), media_type()) :: {:ok, binary()} | {:error, term()}
  def download(%{} = ref, type) do
    # The descriptor is a canonical snake_case shape (`%Amarula.Content.Media{}` for inbound
    # messages; `HistorySync` and tests build the same keys). Surface its required
    # shape in the head: a valid one yields a URL and a media key; an invalid one
    # falls through to `{:error, :invalid_media}` — honouring the {:ok | :error}
    # contract instead of letting Req raise up through a typed caller.
    with url when is_binary(url) <- download_url(ref),
         media_key when is_binary(media_key) <- Map.get(ref, :media_key) do
      case Req.get(url, [decode_body: false] ++ req_options()) do
        {:ok, %{status: 200, body: enc}} when is_binary(enc) ->
          verify_and_decrypt(ref, enc, media_key, type)

        {:ok, %{status: status}} ->
          {:error, {:http, status}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      _ -> {:error, :invalid_media}
    end
  end

  def download(_ref, _type), do: {:error, :invalid_media}

  # The MAC (checked in `decrypt/3`) already authenticates the ciphertext against the
  # media key, so ciphertext integrity is covered. After decrypting, verify the
  # plaintext against the sender's declared `file_sha256` — end-to-end content
  # integrity that also catches a decrypt/unpad bug. (The `file_enc_sha256` hash the
  # descriptor also carries would be redundant with the MAC, so we don't check it.)
  # Skipped if the descriptor doesn't carry `file_sha256`.
  defp verify_and_decrypt(ref, enc, media_key, type) do
    with {:ok, plaintext} <- decrypt(enc, media_key, type),
         :ok <- verify_hash(plaintext, Map.get(ref, :file_sha256), :bad_file_hash) do
      {:ok, plaintext}
    end
  end

  defp verify_hash(_data, nil, _err), do: :ok

  defp verify_hash(data, expected, err) when is_binary(expected) do
    if :crypto.hash(:sha256, data) == expected, do: :ok, else: {:error, err}
  end

  # Extra Req options merged into every request. Empty in prod; tests set
  #   config :amarula, :req_options, plug: {Req.Test, Amarula.Protocol.Messages.Media}
  # to route HTTP through a Req.Test stub instead of the network.
  defp req_options, do: Application.get_env(:amarula, :req_options, [])

  # The full CDN URL from the descriptor's `:direct_path` (preferred) or `:url`.
  defp download_url(%{direct_path: path}) when is_binary(path),
    do: "https://#{@default_media_host}#{path}"

  defp download_url(%{url: url}) when is_binary(url), do: url
  defp download_url(_), do: nil

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

  # --- media retry (ask the phone to re-upload after a CDN 404/410) ---
  #
  # WhatsApp drops media from its CDN after a while; a later download then 404/410s.
  # The recovery is to send a <receipt type="server-error"> asking the *sender's
  # phone* to re-upload; the phone replies with a <notification type="mediaretry">
  # carrying a fresh directPath. Both payloads are AES-256-GCM under a key HKDF'd
  # from the message's media_key, with the message id as the GCM AAD. Ported from
  # whatsmeow's mediaretry.go.

  @retry_hkdf_info "WhatsApp Media Retry Notification"

  @doc """
  HKDF-derived key that wraps the media-retry receipt/notification, keyed by the
  message's `media_key`. (RFC 5869 empty salt = 32 zero bytes, matching whatsmeow's
  nil salt.)
  """
  @spec retry_key(binary()) :: binary()
  def retry_key(media_key), do: Crypto.hkdf(media_key, 32, <<0::256>>, @retry_hkdf_info)

  @doc """
  Build the `<receipt type="server-error">` node that asks the sender's phone to
  re-upload media whose CDN copy is gone. `own_jid` is our account jid in non-AD
  form (no device), `chat_jid` the conversation, `participant_jid` the group sender
  (nil for a 1:1).
  """
  @spec build_retry_receipt(
          String.t(),
          String.t(),
          String.t(),
          boolean(),
          String.t() | nil,
          binary()
        ) :: Node.t()
  def build_retry_receipt(msg_id, own_jid, chat_jid, from_me, participant_jid, media_key) do
    iv = :crypto.strong_rand_bytes(12)
    plaintext = Proto.ServerErrorReceipt.encode(%Proto.ServerErrorReceipt{stanzaId: msg_id})
    {:ok, enc_p} = Crypto.aes_encrypt_gcm(plaintext, retry_key(media_key), iv, msg_id)

    rmr_attrs =
      [{"jid", chat_jid}, {"from_me", to_string(from_me)}] ++
        if(participant_jid, do: [{"participant", participant_jid}], else: [])

    %Node{
      tag: "receipt",
      attrs: [{"id", msg_id}, {"to", own_jid}, {"type", "server-error"}],
      content: [
        %Node{
          tag: "encrypt",
          attrs: %{},
          content: [
            %Node{tag: "enc_p", attrs: %{}, content: enc_p},
            %Node{tag: "enc_iv", attrs: %{}, content: iv}
          ]
        },
        %Node{tag: "rmr", attrs: rmr_attrs, content: nil}
      ]
    }
  end

  @doc """
  Decode a `<notification type="mediaretry">` reply, decrypting it with the same
  `media_key`. Returns `{:ok, new_direct_path}` on success (update the descriptor
  and re-download), or `{:error, reason}`: `:not_on_phone` when the phone no longer
  holds the media (`<error code="2">`), `:malformed_notification`, a GCM decrypt
  error, or `{:result, result}` for a non-SUCCESS `MediaRetryNotification`.
  """
  @spec decode_retry_notification(Node.t(), binary()) :: {:ok, String.t()} | {:error, term()}
  def decode_retry_notification(node, media_key) do
    case NodeUtils.get_binary_node_child(node, "error") do
      %Node{} = err ->
        if NodeUtils.get_attr(err, "code") == "2",
          do: {:error, :not_on_phone},
          else: {:error, {:server_error, NodeUtils.get_attr(err, "code")}}

      nil ->
        decrypt_retry_notification(node, media_key)
    end
  end

  defp decrypt_retry_notification(node, media_key) do
    msg_id = NodeUtils.get_attr(node, "id")
    encrypt = NodeUtils.get_binary_node_child(node, "encrypt")
    enc_p = enc_child(encrypt, "enc_p")
    iv = enc_child(encrypt, "enc_iv")

    with true <- is_binary(enc_p) and is_binary(iv),
         {:ok, plain} <- Crypto.aes_decrypt_gcm(enc_p, retry_key(media_key), iv, msg_id) do
      case Proto.MediaRetryNotification.decode(plain) do
        %Proto.MediaRetryNotification{result: :SUCCESS, directPath: dp} when is_binary(dp) ->
          {:ok, dp}

        %Proto.MediaRetryNotification{result: result} ->
          {:error, {:result, result}}
      end
    else
      false -> {:error, :malformed_notification}
      {:error, _} = err -> err
    end
  end

  defp enc_child(%Node{} = encrypt, tag) do
    case NodeUtils.get_binary_node_child(encrypt, tag) do
      %Node{content: content} when is_binary(content) -> content
      _ -> nil
    end
  end

  defp enc_child(_, _), do: nil

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

    post_opts = [body: enc, headers: [{"content-type", "application/octet-stream"}]]

    case Req.post(url, post_opts ++ req_options()) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, %{direct_path: body["direct_path"], url: body["url"] || ""}}

      other ->
        # Status/reason only — the URL carries the auth token, keep it out of logs.
        Logger.warning("Media upload to #{host} failed: #{inspect(upload_failure(other))}")
        put_to_hosts(rest, type, token, auth, enc)
    end
  end

  defp upload_failure({:ok, %{status: status}}), do: {:status, status}
  defp upload_failure({:error, reason}), do: reason
end
