defmodule Amarula.Connection.Pairing do
  @moduledoc """
  Pure pairing builders for `Amarula.Connection` — the node-building and
  creds-transform parts of the QR/multi-device handshake.

  The orchestrating handlers (`handle_pair_device`, `handle_pair_success`,
  `emit_next_qr`) stay on `Connection`: they send frames, run timers, persist
  creds, and emit events. What lives here is pure and testable directly — the
  two reply IQ nodes, the QR-ref extraction, and the post-pairing creds merge.
  """

  alias Amarula.Protocol.Auth.{CompanionReg, DeviceIdentity}
  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Crypto.{Constants, Crypto}
  alias Amarula.Protocol.Proto

  @doc "The `<iq type=result>` ack for a received pair-device IQ."
  @spec pair_device_ack_node(String.t()) :: Node.t()
  def pair_device_ack_node(msg_id) do
    %Node{
      tag: "iq",
      attrs: [
        {"to", "@s.whatsapp.net"},
        {"type", "result"},
        {"id", msg_id}
      ],
      content: nil
    }
  end

  @doc """
  Extract the QR `ref` payloads from a pair-device IQ node, in order. Returns
  `[]` when the `<pair-device>` wrapper or its `<ref>` children are absent.
  """
  @spec qr_refs(Node.t()) :: [binary()]
  def qr_refs(node) do
    with pair_device_node when not is_nil(pair_device_node) <-
           NodeUtils.get_binary_node_child(node, "pair-device"),
         [_ | _] = ref_nodes <-
           NodeUtils.get_binary_node_children(pair_device_node, "ref") do
      Enum.map(ref_nodes, & &1.content)
    else
      _ -> []
    end
  end

  @doc "The `<iq><pair-device-sign>` reply counter-signing the device identity."
  @spec pair_device_sign_reply(String.t(), integer(), binary()) :: Node.t()
  def pair_device_sign_reply(msg_id, key_index, account_enc) do
    %Node{
      tag: "iq",
      attrs: %{
        "to" => Constants.s_whatsapp_net(),
        "type" => "result",
        "id" => msg_id
      },
      content: [
        %Node{
          tag: "pair-device-sign",
          attrs: %{},
          content: [
            %Node{
              tag: "device-identity",
              attrs: %{"key-index" => to_string(key_index)},
              content: account_enc
            }
          ]
        }
      ]
    }
  end

  @doc """
  Merge the paired-device fields into creds. `me.name` defaults to "~" (Baileys)
  when there's no business name — presence-available requires a non-nil me.name.
  """
  @spec update_credentials_after_pairing(
          map(),
          term(),
          String.t(),
          String.t(),
          term(),
          term(),
          term()
        ) ::
          map()
  def update_credentials_after_pairing(
        creds,
        account,
        jid,
        lid,
        biz_name,
        platform,
        signal_identity
      ) do
    creds
    |> Map.put(:account, account)
    |> Map.put(:me, %{id: jid, name: biz_name || "~", lid: lid})
    |> Map.put(:platform, platform)
    |> Map.update(:signal_identities, [signal_identity], fn identities ->
      [signal_identity | identities || []]
    end)
  end

  @doc """
  Verify a `pair-success` IQ node against `auth_creds` and build the signed reply
  node and updated credentials.
  """
  @spec verify_pair_success(Node.t(), map()) ::
          {:ok,
           %{
             msg_id: String.t(),
             key_index: integer(),
             jid: String.t(),
             lid: String.t(),
             platform: String.t() | nil,
             reply_node: Node.t(),
             updated_creds: map()
           }}
          | {:error, :missing_field | term()}
  def verify_pair_success(node, auth_creds) do
    with msg_id when not is_nil(msg_id) <- NodeUtils.get_attr(node, "id"),
         pair_success_node when not is_nil(pair_success_node) <-
           NodeUtils.get_binary_node_child(node, "pair-success"),
         device_identity_node when not is_nil(device_identity_node) <-
           NodeUtils.get_binary_node_child(pair_success_node, "device-identity"),
         device_node when not is_nil(device_node) <-
           NodeUtils.get_binary_node_child(pair_success_node, "device"),
         jid when not is_nil(jid) <- NodeUtils.get_attr(device_node, "jid"),
         lid when not is_nil(lid) <- NodeUtils.get_attr(device_node, "lid"),
         identity_hmac <-
           Proto.ADVSignedDeviceIdentityHMAC.decode(device_identity_node.content),
         {:ok, verified_account} <-
           DeviceIdentity.verify_and_sign(identity_hmac, auth_creds),
         device_identity <- Proto.ADVDeviceIdentity.decode(verified_account.details) do
      platform_node = NodeUtils.get_binary_node_child(pair_success_node, "platform")
      business_node = NodeUtils.get_binary_node_child(pair_success_node, "biz")
      platform = if platform_node, do: NodeUtils.get_attr(platform_node, "name"), else: nil
      biz_name = if business_node, do: NodeUtils.get_attr(business_node, "name"), else: nil

      signal_identity = DeviceIdentity.signal_identity(lid, verified_account.accountSignatureKey)
      # Encode without the account signature key
      account_enc = DeviceIdentity.encode(verified_account, false)
      reply_node = pair_device_sign_reply(msg_id, device_identity.keyIndex, account_enc)

      updated_creds =
        update_credentials_after_pairing(
          auth_creds,
          verified_account,
          jid,
          lid,
          biz_name,
          platform,
          signal_identity
        )

      {:ok,
       %{
         msg_id: msg_id,
         key_index: device_identity.keyIndex,
         jid: jid,
         lid: lid,
         platform: platform,
         reply_node: reply_node,
         updated_creds: updated_creds
       }}
    else
      nil -> {:error, :missing_field}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Build the QR pairing string for `ref` (matches Baileys `buildPairingQRData`).
  """
  @spec generate_qr_code(String.t(), map(), map()) :: String.t()
  def generate_qr_code(ref, auth_creds, config) do
    # Matches Baileys buildPairingQRData (rc13):
    # "https://wa.me/settings/linked_devices#" +
    #   [ref, noiseKey, identityKey, advSecretKey, companionPlatformId].join(",")
    noise_key_b64 = Base.encode64(auth_creds.noise_key.public)
    identity_key_b64 = Base.encode64(auth_creds.signed_identity_key.public)
    adv_b64 = auth_creds.adv_secret_key
    platform_id = companion_platform_id(config.browser)

    "https://wa.me/settings/linked_devices#" <>
      Enum.join([ref, noise_key_b64, identity_key_b64, adv_b64, platform_id], ",")
  end

  @doc "QR rotation delay in ms: initial ref uses `config[:qr_timeout]` (default 60s), subsequent refs use 20s."
  @spec qr_refresh_delay(map(), term()) :: pos_integer()
  def qr_refresh_delay(config, qr_timer) do
    base = Map.get(config, :qr_timeout) || 60_000
    if qr_timer == nil, do: base, else: 20_000
  end

  @doc "True when a `companion_reg_refresh` notification asks us to rotate the QR `adv_secret_key`."
  @spec rotate_qr_adv_secret?(Node.t()) :: boolean()
  def rotate_qr_adv_secret?(node) do
    Enum.any?(["companion_reg_refresh", "pair-device-rotate-qr"], fn tag ->
      not is_nil(NodeUtils.get_binary_node_child(node, tag))
    end)
  end

  @browser_platform_ids %{
    "Chrome" => "1",
    "Edge" => "2",
    "Firefox" => "3",
    "IE" => "4",
    "Opera" => "5",
    "Safari" => "6"
  }

  @doc """
  Mirrors Baileys `getCompanionWebClientType`: browser tuple/list → `CompanionWebClientType` string id.
  """
  @spec companion_platform_id(term()) :: String.t()
  def companion_platform_id(["Windows", "Desktop" | _]), do: "8"
  def companion_platform_id([_os, "Desktop" | _]), do: "7"

  def companion_platform_id([_os, browser_name | _]),
    do: Map.get(@browser_platform_ids, browser_name, "9")

  def companion_platform_id(_), do: "9"

  @doc "Validate or generate an 8-character Crockford link-code pairing code."
  @spec build_pairing_code(String.t() | nil) ::
          {:ok, String.t()} | {:error, :custom_pairing_code_must_be_8_chars}
  # nil → random 8-char Crockford code; a custom code must be exactly 8 chars.
  def build_pairing_code(nil), do: {:ok, CompanionReg.crockford_encode(Crypto.random_bytes(5))}
  def build_pairing_code(code) when is_binary(code) and byte_size(code) == 8, do: {:ok, code}
  def build_pairing_code(_), do: {:error, :custom_pairing_code_must_be_8_chars}

  @doc "Build the `companion_hello` IQ node for phone-number link-code pairing."
  @spec companion_hello_iq(String.t(), map(), term()) :: Node.t()
  def companion_hello_iq(me_id, creds, browser) do
    %Node{
      tag: "iq",
      attrs: [
        {"to", Constants.s_whatsapp_net()},
        {"type", "set"},
        {"xmlns", "md"}
      ],
      content: [
        %Node{
          tag: "link_code_companion_reg",
          attrs: [
            {"jid", me_id},
            {"stage", "companion_hello"},
            {"should_show_push_notification", "true"}
          ],
          content: [
            child(
              "link_code_pairing_wrapped_companion_ephemeral_pub",
              generate_pairing_key(creds)
            ),
            child("companion_server_auth_key_pub", creds.noise_key.public),
            child("companion_platform_id", companion_platform_id(browser)),
            child("companion_platform_display", platform_display(browser)),
            child("link_code_pairing_nonce", <<0>>)
          ]
        }
      ]
    }
  end

  @doc """
  Parse a `link_code_companion_reg` notification into
  `{:ok, ref, primary_identity_pub, wrapped}` or `:ignore`.
  """
  @spec parse_link_code_notification(Node.t()) ::
          {:ok, binary(), binary(), binary()} | :ignore
  def parse_link_code_notification(node) do
    inner = NodeUtils.get_binary_node_child(node, "link_code_companion_reg")

    # The same tag also arrives as a fieldless notification (Baileys #2600). Guard
    # buffer extraction with `with` so a missing field logs-and-skips rather than
    # crashing the connection.
    with reg when not is_nil(reg) <- inner,
         stage when stage in [nil, "primary_hello"] <- NodeUtils.get_attr(reg, "stage"),
         ref when not is_nil(ref) <- child_buffer(reg, "link_code_pairing_ref"),
         primary_identity_pub when not is_nil(primary_identity_pub) <-
           child_buffer(reg, "primary_identity_pub"),
         wrapped when not is_nil(wrapped) <-
           child_buffer(reg, "link_code_pairing_wrapped_primary_ephemeral_pub") do
      {:ok, ref, primary_identity_pub, wrapped}
    else
      _ -> :ignore
    end
  end

  @doc """
  Complete the crypto and build `{updated_creds, companion_finish_iq}` for
  link-code pairing once the primary device confirms with `primary_hello`.
  """
  @spec finish_link_code(map(), String.t(), String.t(), binary(), binary(), binary()) ::
          {map(), Node.t()}
  def finish_link_code(creds, me_id, iq_id, ref, primary_identity_pub, wrapped) do
    code_pairing_pub = decipher_link_public_key(creds, wrapped)

    companion_shared =
      Crypto.shared_key(creds.pairing_ephemeral_key_pair.private, code_pairing_pub)

    random = Crypto.random_bytes(32)
    link_code_salt = Crypto.random_bytes(32)

    expanded =
      Crypto.hkdf(
        companion_shared,
        32,
        link_code_salt,
        "link_code_pairing_key_bundle_encryption_key"
      )

    payload = creds.signed_identity_key.public <> primary_identity_pub <> random
    iv = Crypto.random_bytes(12)
    {:ok, encrypted} = Crypto.aes_encrypt_gcm(payload, expanded, iv, <<>>)
    encrypted_payload = link_code_salt <> iv <> encrypted

    identity_shared = Crypto.shared_key(creds.signed_identity_key.private, primary_identity_pub)

    adv_secret =
      Crypto.hkdf(companion_shared <> identity_shared <> random, 32, <<>>, "adv_secret")
      |> Base.encode64()

    updated_creds = %{creds | adv_secret_key: adv_secret, registered: true}

    iq = %Node{
      tag: "iq",
      attrs: [
        {"to", Constants.s_whatsapp_net()},
        {"type", "set"},
        {"id", iq_id},
        {"xmlns", "md"}
      ],
      content: [
        %Node{
          tag: "link_code_companion_reg",
          attrs: [{"jid", me_id}, {"stage", "companion_finish"}],
          content: [
            child("link_code_pairing_wrapped_key_bundle", encrypted_payload),
            child("companion_identity_public", creds.signed_identity_key.public),
            child("link_code_pairing_ref", ref)
          ]
        }
      ]
    }

    {updated_creds, iq}
  end

  # salt(32) <> iv(16) <> AES-CTR(pairing ephemeral pub, derivePairingCodeKey(code, salt), iv)
  defp generate_pairing_key(creds) do
    salt = Crypto.random_bytes(32)
    iv = Crypto.random_bytes(16)
    key = Crypto.derive_pairing_code_key(creds.pairing_code, salt)
    ciphered = Crypto.aes_encrypt_ctr(creds.pairing_ephemeral_key_pair.public, key, iv)
    salt <> iv <> ciphered
  end

  # salt(0..32) <> iv(32..48) <> payload(48..80); AES-CTR-decrypt the wrapped pub.
  defp decipher_link_public_key(creds, buffer) do
    <<salt::binary-size(32), iv::binary-size(16), payload::binary-size(32), _rest::binary>> =
      buffer

    key = Crypto.derive_pairing_code_key(creds.pairing_code, salt)
    Crypto.aes_decrypt_ctr(payload, key, iv)
  end

  # Baileys `${browser[1]} (${browser[0]})` → "Chrome (Mac OS)".
  defp platform_display([os, browser_name | _]), do: "#{browser_name} (#{os})"
  defp platform_display(_), do: "Chrome"

  defp child(tag, content), do: %Node{tag: tag, attrs: [], content: content}

  # Fetch a named child's content, but only if it's a binary buffer (the #2600
  # guard — a fieldless notification yields nil, not a crash).
  defp child_buffer(node, tag) do
    case NodeUtils.get_binary_node_child(node, tag) do
      %Node{content: content} when is_binary(content) -> content
      _ -> nil
    end
  end
end
