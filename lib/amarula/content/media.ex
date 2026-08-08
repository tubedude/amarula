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

  ## Rebuilding a descriptor

  A descriptor that came off the socket is trusted; one you persisted, sent over a
  transport, or rebuilt from normalized metadata is not. Rehydrate it with `new/1`
  rather than `struct/2` — it enforces the field rules `from_proto/2` gets for free
  from the protobuf, and keeps only a locator `download_media/1` may safely fetch.
  """

  @type kind :: :image | :video | :audio | :document | :sticker

  @kinds ~w(image video audio document sticker)a
  @kind_names Map.new(@kinds, &{Atom.to_string(&1), &1})

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

  @doc """
  Build a validated `%Amarula.Content.Media{}` from a plain map — the constructor for
  a descriptor you did **not** get off the socket (rehydrated from storage, rebuilt
  from normalized metadata, received over a transport).

  `from_proto/2` trusts its input because the protobuf already guarantees the shape;
  `new/1` enforces the same rules explicitly, so a bad or hostile descriptor fails
  here instead of deep inside `Amarula.download_media/1`. Keys may be atoms or
  strings (`%{"media_key" => ..}`, as a JSON round-trip leaves them); unknown keys
  are ignored, and a blank string reads as absent.

  Required:

    * `:kind` — `:image`, `:video`, `:audio`, `:document` or `:sticker`, as an atom
      or the same word as a string.
    * `:media_key` — the raw 32-byte key. **Not** Base64: decode it yourself if you
      stored it encoded.
    * a locator — `:direct_path`, or a `:url` that is `https://` on a WhatsApp host.
      `:direct_path` wins and the `:url` is dropped, so an untrusted URL cannot
      survive in the struct (`download_media/1` would ignore it anyway).

  Optional, validated when present: `:file_sha256` / `:file_enc_sha256` (32 bytes),
  `:file_length` / `:width` / `:height` / `:seconds` (non-negative integers),
  `:mimetype` / `:caption` / `:file_name` (strings).

  Returns `{:ok, media}` or `{:error, {:invalid, field}}` naming the first field that
  failed — `:locator` when neither locator is present.

      iex> {:ok, media} = Amarula.Content.Media.new(%{
      ...>   "kind" => "image",
      ...>   "direct_path" => "/v/t62.7118-24/abc",
      ...>   "url" => "https://evil.example.com/x",
      ...>   "media_key" => <<0::256>>
      ...> })
      iex> {media.kind, media.url}
      {:image, nil}
  """
  @spec new(map()) :: {:ok, t()} | {:error, {:invalid, atom()}}
  def new(%{} = attrs) do
    with {:ok, kind} <- kind(get(attrs, :kind)),
         {:ok, media_key} <- media_key(get(attrs, :media_key)),
         {:ok, file_sha256} <- hash(get(attrs, :file_sha256), :file_sha256),
         {:ok, file_enc_sha256} <- hash(get(attrs, :file_enc_sha256), :file_enc_sha256),
         {:ok, file_length} <- size(get(attrs, :file_length), :file_length),
         {:ok, width} <- size(get(attrs, :width), :width),
         {:ok, height} <- size(get(attrs, :height), :height),
         {:ok, seconds} <- size(get(attrs, :seconds), :seconds),
         {:ok, mimetype} <- text(get(attrs, :mimetype), :mimetype),
         {:ok, caption} <- text(get(attrs, :caption), :caption),
         {:ok, file_name} <- text(get(attrs, :file_name), :file_name),
         {:ok, locator} <- locator_field(attrs) do
      media = %__MODULE__{
        kind: kind,
        mimetype: mimetype,
        caption: caption,
        file_length: file_length,
        width: width,
        height: height,
        seconds: seconds,
        file_name: file_name,
        media_key: media_key,
        file_sha256: file_sha256,
        file_enc_sha256: file_enc_sha256
      }

      {:ok, put_locator(media, locator)}
    end
  end

  def new(_attrs), do: {:error, {:invalid, :media}}

  @doc false
  # The one locator a descriptor may be fetched from — the shared policy behind both
  # `new/1` and the download path, which is why it takes a plain map (history-sync
  # descriptors are not `%Media{}`).
  #
  # `:direct_path` wins: it is joined onto WhatsApp's own media host, so it names a
  # file rather than a server. A bare `:url` chooses the host, and a descriptor that
  # came back from storage or across a transport can carry any host — trust it only
  # when it is HTTPS on WhatsApp's own domain. A present-but-malformed locator is an
  # error, not a reason to try the other one.
  @spec locator(map()) ::
          {:ok, {:direct_path, String.t()} | {:url, String.t()}}
          | {:error, :invalid_media | :unsafe_direct_path | :untrusted_media_url}
  def locator(%{} = ref) do
    case {get(ref, :direct_path), get(ref, :url)} do
      {path, _url} when is_binary(path) ->
        if safe_path?(path), do: {:ok, {:direct_path, path}}, else: {:error, :unsafe_direct_path}

      {nil, url} when is_binary(url) ->
        if trusted_url?(url), do: {:ok, {:url, url}}, else: {:error, :untrusted_media_url}

      _absent ->
        {:error, :invalid_media}
    end
  end

  def locator(_ref), do: {:error, :invalid_media}

  @doc false
  # HTTPS on WhatsApp's own media domain, with no userinfo — `URI.new/1` rather than
  # `URI.parse/1` so control characters are rejected outright, and because
  # "https://mmg.whatsapp.net@evil.com/x" must read as the host it really has.
  @spec trusted_url?(term()) :: boolean()
  def trusted_url?(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: "https", userinfo: nil, host: host}} when is_binary(host) ->
        whatsapp_host?(String.downcase(host))

      _other ->
        false
    end
  end

  def trusted_url?(_url), do: false

  defp whatsapp_host?("whatsapp.net"), do: true
  defp whatsapp_host?(host), do: String.ends_with?(host, ".whatsapp.net")

  # The path is appended to "https://<media host>", so it must start at the root and
  # carry no whitespace or control bytes: "@evil.com/x" would otherwise read as
  # userinfo and hand the request to evil.com.
  defp safe_path?(path) do
    String.starts_with?(path, "/") and
      path |> :binary.bin_to_list() |> Enum.all?(&(&1 > 0x20 and &1 != 0x7F))
  end

  defp put_locator(media, {:direct_path, path}), do: %{media | direct_path: path, url: nil}
  defp put_locator(media, {:url, url}), do: %{media | url: url, direct_path: nil}

  # `new/1` reports the field that failed; `locator/1`'s reasons are the ones the
  # download path surfaces.
  defp locator_field(attrs) do
    case locator(attrs) do
      {:ok, locator} -> {:ok, locator}
      {:error, :unsafe_direct_path} -> {:error, {:invalid, :direct_path}}
      {:error, :untrusted_media_url} -> {:error, {:invalid, :url}}
      {:error, :invalid_media} -> {:error, {:invalid, :locator}}
    end
  end

  defp kind(kind) when kind in @kinds, do: {:ok, kind}

  defp kind(kind) when is_binary(kind) do
    case Map.fetch(@kind_names, kind) do
      {:ok, kind} -> {:ok, kind}
      :error -> {:error, {:invalid, :kind}}
    end
  end

  defp kind(_kind), do: {:error, {:invalid, :kind}}

  defp media_key(<<key::binary-32>>), do: {:ok, key}
  defp media_key(_key), do: {:error, {:invalid, :media_key}}

  defp hash(nil, _field), do: {:ok, nil}
  defp hash(<<hash::binary-32>>, _field), do: {:ok, hash}
  defp hash(_value, field), do: {:error, {:invalid, field}}

  defp size(nil, _field), do: {:ok, nil}
  defp size(size, _field) when is_integer(size) and size >= 0, do: {:ok, size}
  defp size(_value, field), do: {:error, {:invalid, field}}

  defp text(nil, _field), do: {:ok, nil}
  defp text(text, _field) when is_binary(text), do: {:ok, text}
  defp text(_value, field), do: {:error, {:invalid, field}}

  # Read one declared field from a map that may be atom-keyed (built here) or
  # string-keyed (rehydrated from JSON). The conversion goes atom→string, over our
  # own field names — so an unfamiliar key in the input can neither reach the atom
  # table nor raise, it is simply not read.
  defp get(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} -> blank_to_nil(value)
      :error -> attrs |> Map.get(Atom.to_string(field)) |> blank_to_nil()
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
