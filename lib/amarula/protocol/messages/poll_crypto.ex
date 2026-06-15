defmodule Amarula.Protocol.Messages.PollCrypto do
  @moduledoc """
  Decrypt poll votes, ported from Baileys `decryptPollVote`
  (`src/Utils/process-message.ts`).

  A vote's `encPayload`/`encIv` are AES-256-GCM encrypted under a key derived from
  the poll's `message_secret` and the ids of the poll, its creator, and the voter:

      sign   = poll_msg_id ++ poll_creator_jid ++ voter_jid ++ "Poll Vote" ++ <<1>>
      key0   = HMAC-SHA256(key=message_secret, data=<<0::256>>)   # 32 zero bytes
      dec_key= HMAC-SHA256(key=key0, data=sign)
      aad    = "<poll_msg_id>\\0<voter_jid>"
      plain  = AES-256-GCM-decrypt(encPayload, key=dec_key, iv=encIv, aad)
             → Proto.Message.PollVoteMessage (selectedOptions = SHA-256 option hashes)

  GCM tag is the trailing 16 bytes of `encPayload`.
  """

  alias Amarula.Protocol.Proto

  @gcm_tag_len 16

  @type context :: %{
          message_secret: binary(),
          poll_msg_id: String.t(),
          poll_creator_jid: String.t(),
          voter_jid: String.t()
        }

  @doc """
  Decrypt a poll vote (`enc` = `%Proto.Message.PollEncValue{}` or a map with
  `:encPayload`/`:encIv`). Returns `{:ok, %PollVoteMessage{}}` (its
  `selectedOptions` are SHA-256 hashes of the chosen option names — match against
  `Poll.tally/3`), or `{:error, reason}`.
  """
  @spec decrypt_vote(map(), context()) :: {:ok, struct()} | {:error, term()}
  def decrypt_vote(%{encPayload: payload, encIv: iv}, ctx)
      when is_binary(payload) and is_binary(iv) do
    dec_key = vote_key(ctx)
    aad = "#{ctx.poll_msg_id}\0#{ctx.voter_jid}"

    ct_len = byte_size(payload) - @gcm_tag_len
    <<ciphertext::binary-size(ct_len), tag::binary-size(@gcm_tag_len)>> = payload

    case :crypto.crypto_one_time_aead(:aes_256_gcm, dec_key, iv, ciphertext, aad, tag, false) do
      plaintext when is_binary(plaintext) ->
        {:ok, Proto.Message.PollVoteMessage.decode(plaintext)}

      :error ->
        {:error, :decrypt_failed}
    end
  rescue
    e -> {:error, e}
  end

  def decrypt_vote(_enc, _ctx), do: {:error, :no_payload}

  # HMAC chain. Baileys `hmacSign(buffer, key)` = HMAC(key, buffer), so:
  #   key0   = HMAC(key=<32 zero bytes>, data=message_secret)
  #   decKey = HMAC(key=key0, data=sign)
  defp vote_key(ctx) do
    sign = ctx.poll_msg_id <> ctx.poll_creator_jid <> ctx.voter_jid <> "Poll Vote" <> <<1>>
    key0 = :crypto.mac(:hmac, :sha256, <<0::256>>, ctx.message_secret)
    :crypto.mac(:hmac, :sha256, key0, sign)
  end
end
