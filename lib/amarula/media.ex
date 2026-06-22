defmodule Amarula.Media do
  @moduledoc """
  A received media attachment — the normalized, consumer-facing view of an inbound
  image / video / audio / document / sticker.

  This is what `%Amarula.Msg{type: :media}` carries in `content.media`. It is a
  plain snake_case struct (not the raw protobuf), so consumers read one consistent
  shape — including the **`:mimetype`**, which is what you need to pick the right
  file extension or `<img>` vs `<video>`. Pass it (or the whole `%Amarula.Msg{}`)
  to `Amarula.download_media/1` to fetch and decrypt the bytes — no live connection
  required; the keys ride in this struct.

  ## Fields

    * `:kind` — `:image | :video | :audio | :document | :sticker`.
    * `:mimetype` — the content type (e.g. `"image/jpeg"`, `"video/mp4"`,
      `"image/webp"` for a sticker). **Use this for the extension / element type**,
      not `:kind` — WhatsApp sends webp stickers, mp4 "gifs", etc.
    * `:caption` — text shown with the media (`nil` if none).
    * `:file_length` — size in bytes (`nil` if absent).
    * `:width` / `:height` — pixel dimensions for image/video/sticker (`nil` otherwise).
    * `:seconds` — duration for audio/video (`nil` otherwise).
    * `:file_name` — original file name for documents (`nil` otherwise).

  The remaining fields (`:url`, `:direct_path`, `:media_key`, `:file_sha256`,
  `:file_enc_sha256`) are the CDN locator + decryption material used by
  `download_media`; you rarely read them directly.
  """

  @type kind :: :image | :video | :audio | :document | :sticker

  @type t :: %__MODULE__{
          kind: kind(),
          mimetype: String.t() | nil,
          caption: String.t() | nil,
          file_length: non_neg_integer() | nil,
          width: non_neg_integer() | nil,
          height: non_neg_integer() | nil,
          seconds: non_neg_integer() | nil,
          file_name: String.t() | nil,
          url: String.t() | nil,
          direct_path: String.t() | nil,
          media_key: binary() | nil,
          file_sha256: binary() | nil,
          file_enc_sha256: binary() | nil
        }

  @enforce_keys [:kind]
  defstruct [
    :kind,
    :mimetype,
    :caption,
    :file_length,
    :width,
    :height,
    :seconds,
    :file_name,
    :url,
    :direct_path,
    :media_key,
    :file_sha256,
    :file_enc_sha256
  ]

  @doc """
  Normalize a raw media proto (`%Proto.Message.ImageMessage{}` etc.) into a
  `%Amarula.Media{}` of the given `kind`. Snake-cases the camelCase proto fields
  and surfaces the type-relevant metadata; missing fields are `nil`.
  """
  @spec from_proto(kind(), struct()) :: t()
  def from_proto(kind, %{} = m) do
    %__MODULE__{
      kind: kind,
      mimetype: get(m, :mimetype),
      caption: get(m, :caption),
      file_length: get(m, :fileLength),
      width: get(m, :width),
      height: get(m, :height),
      seconds: get(m, :seconds),
      file_name: get(m, :fileName),
      url: get(m, :url),
      direct_path: get(m, :directPath),
      media_key: get(m, :mediaKey),
      file_sha256: get(m, :fileSha256),
      file_enc_sha256: get(m, :fileEncSha256)
    }
  end

  # Read a field that a given media proto may or may not declare (e.g. only
  # audio/video carry :seconds), tolerating its absence.
  defp get(m, key), do: Map.get(m, key)
end
