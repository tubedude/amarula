defmodule Amarula.Protocol.Signal.PreKeys do
  @moduledoc """
  One-time prekey generation and the `encrypt` IQ that uploads them, ported
  from the prekey helpers in `src/Utils/signal.ts` (`generateOrGetPreKeys`,
  `getNextPreKeysNode`, `xmppPreKey`, `xmppSignedPreKey`).

  Prekeys live in the creds map under `:pre_keys` (integer id => %{public,
  private}, raw 32-byte X25519), alongside the upload watermarks
  `:next_pre_key_id` and `:first_unuploaded_pre_key_id` (both start at 1).
  `SessionStore.build/1` reads `:pre_keys` to serve the responder X3DH when a
  PreKeySignalMessage references one of our ids.
  """

  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Crypto.{Constants, Crypto}

  # Baileys src/Defaults: MIN_PREKEY_COUNT / INITIAL_PREKEY_COUNT / KEY_BUNDLE_TYPE
  @min_pre_key_count 5
  @initial_pre_key_count 812
  @key_bundle_type <<5>>

  def min_pre_key_count, do: @min_pre_key_count
  def initial_pre_key_count, do: @initial_pre_key_count

  @doc """
  Ensure `range` prekeys exist past the uploaded watermark, generating only the
  missing ones. Returns `{new_pre_keys, last_pre_key_id, upload_range}` where
  `upload_range` is `{first_id, count}` of the keys to put in the upload IQ.
  Mirrors `generateOrGetPreKeys`.
  """
  @spec generate_or_get_pre_keys(map(), pos_integer()) ::
          {map(), integer(), {integer(), integer()}}
  def generate_or_get_pre_keys(creds, range) do
    next_id = Map.get(creds, :next_pre_key_id, 1)
    first_unuploaded = Map.get(creds, :first_unuploaded_pre_key_id, 1)

    available = next_id - first_unuploaded
    remaining = range - available
    last_pre_key_id = next_id + remaining - 1

    new_pre_keys =
      if remaining > 0 do
        Map.new(next_id..last_pre_key_id, fn id -> {id, Crypto.generate_key_pair()} end)
      else
        %{}
      end

    {new_pre_keys, last_pre_key_id, {first_unuploaded, range}}
  end

  @doc """
  Build the `encrypt` upload IQ for the next `count` prekeys and the updated
  creds (new prekeys merged in, watermarks advanced). Mirrors
  `getNextPreKeysNode`; the caller assigns the IQ `id` attribute.

  Returns `{updated_creds, node}`.
  """
  @spec get_next_pre_keys_node(map(), pos_integer()) :: {map(), Node.t()}
  def get_next_pre_keys_node(creds, count) do
    {updated_creds, upload_keys} = get_next_pre_keys(creds, count)
    pre_keys_node(updated_creds, upload_keys)
  end

  @doc """
  Reserve the next `count` one-time prekeys: generate any missing ones, advance
  the watermarks, and return `{updated_creds, [{id, pair}]}`. Used by both the
  bulk upload IQ and the retry-receipt key bundle (Baileys getNextPreKeys).
  """
  @spec get_next_pre_keys(map(), pos_integer()) :: {map(), [{integer(), map()}]}
  def get_next_pre_keys(creds, count) do
    {new_pre_keys, last_pre_key_id, {first_id, range}} = generate_or_get_pre_keys(creds, count)

    pre_keys = Map.merge(Map.get(creds, :pre_keys, %{}), new_pre_keys)

    updated_creds =
      creds
      |> Map.put(:pre_keys, pre_keys)
      |> Map.put(:next_pre_key_id, max(last_pre_key_id + 1, Map.get(creds, :next_pre_key_id, 1)))
      |> Map.put(
        :first_unuploaded_pre_key_id,
        max(Map.get(creds, :first_unuploaded_pre_key_id, 1), last_pre_key_id + 1)
      )

    keys =
      first_id..(first_id + range - 1)
      |> Enum.map(fn id -> {id, Map.get(pre_keys, id)} end)
      |> Enum.reject(fn {_id, pair} -> is_nil(pair) end)

    {updated_creds, keys}
  end

  @doc "The KEY_BUNDLE_TYPE byte used in <type> nodes."
  @spec key_bundle_type() :: binary()
  def key_bundle_type, do: @key_bundle_type

  defp pre_keys_node(creds, upload_keys) do
    node = %Node{
      tag: "iq",
      attrs: [
        {"xmlns", "encrypt"},
        {"type", "set"},
        {"to", Constants.s_whatsapp_net()}
      ],
      content: [
        %Node{
          tag: "registration",
          attrs: %{},
          content: encode_big_endian(creds.registration_id, 4)
        },
        %Node{tag: "type", attrs: %{}, content: @key_bundle_type},
        %Node{tag: "identity", attrs: %{}, content: creds.signed_identity_key.public},
        %Node{
          tag: "list",
          attrs: %{},
          content: Enum.map(upload_keys, fn {id, pair} -> xmpp_pre_key(pair, id) end)
        },
        xmpp_signed_pre_key(creds.signed_pre_key)
      ]
    }

    {creds, node}
  end

  @doc "The <skey> node for the signed prekey (id is 3-byte big-endian)."
  @spec xmpp_signed_pre_key(map()) :: Node.t()
  def xmpp_signed_pre_key(signed) do
    %Node{
      tag: "skey",
      attrs: %{},
      content: [
        %Node{tag: "id", attrs: %{}, content: encode_big_endian(signed.key_id, 3)},
        %Node{tag: "value", attrs: %{}, content: signed.key_pair.public},
        %Node{tag: "signature", attrs: %{}, content: signed.signature}
      ]
    }
  end

  @doc "The <key> node for a one-time prekey (id is 3-byte big-endian)."
  @spec xmpp_pre_key(map(), integer()) :: Node.t()
  def xmpp_pre_key(pair, id) do
    %Node{
      tag: "key",
      attrs: %{},
      content: [
        %Node{tag: "id", attrs: %{}, content: encode_big_endian(id, 3)},
        %Node{tag: "value", attrs: %{}, content: pair.public}
      ]
    }
  end

  defp encode_big_endian(value, bytes) do
    <<value::big-unsigned-integer-size(bytes * 8)>>
  end
end
