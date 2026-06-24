defmodule Amarula.Content.Media do
  @moduledoc """
  A received media attachment (`content` of a `%Amarula.Msg{type: :media}`) — an
  inbound image / video / audio / document / sticker. A plain snake_case struct,
  not the raw protobuf. Pass it (or the whole `%Amarula.Msg{}`) to
  `Amarula.download_media/1` to fetch and decrypt the bytes — no live connection
  needed; the keys ride in this struct.

  ## Fields

    * `:kind` — `:image | :video | :audio | :document | :sticker`.
    * `:mimetype` — the content type (e.g. `"image/jpeg"`, `"video/mp4"`,
      `"image/webp"` for a sticker). **Use this** for the file extension / `<img>`
      vs `<video>`, not `:kind` — WhatsApp sends webp stickers, mp4 "gifs", etc.
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
  `%Amarula.Content.Media{}`. `kind` says which proto it is — several distinct media
  protos map to this one struct, so the kind can't be recovered from the proto
  alone. Snake-cases the camelCase fields and surfaces the type-relevant metadata;
  missing fields are `nil`.
  """
  @spec from_proto(kind(), struct()) :: t()
  def from_proto(kind, %{} = m) do
    # `Map.get` per field — a given media proto only declares some of these (only
    # audio/video carry :seconds, etc.); the rest are absent and read as nil.
    %__MODULE__{
      kind: kind,
      mimetype: Map.get(m, :mimetype),
      caption: Map.get(m, :caption),
      file_length: Map.get(m, :fileLength),
      width: Map.get(m, :width),
      height: Map.get(m, :height),
      seconds: Map.get(m, :seconds),
      file_name: Map.get(m, :fileName),
      url: Map.get(m, :url),
      direct_path: Map.get(m, :directPath),
      media_key: Map.get(m, :mediaKey),
      file_sha256: Map.get(m, :fileSha256),
      file_enc_sha256: Map.get(m, :fileEncSha256)
    }
  end
end
