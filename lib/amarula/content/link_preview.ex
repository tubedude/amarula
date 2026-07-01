defmodule Amarula.Content.LinkPreview do
  @moduledoc """
  The link-preview metadata a text message carries for a URL it contains — the
  title/description/thumbnail card WhatsApp shows under a link. Rides on an
  `extendedTextMessage`; a plain text message (or a reply/mention with no link)
  has none.

  Surfaced on `%Amarula.Msg{}.preview` (not `msg.content` — `:text` content stays
  the bare body string), and `nil` when the message carries no preview.

    * `:url`         — the matched URL the preview is for (`matchedText`).
    * `:title`       — the link's title (OpenGraph `og:title`).
    * `:description` — the link's description.
    * `:thumbnail`   — raw JPEG thumbnail bytes, or `nil`.
    * `:type`        — `:none | :video | :placeholder | :image | :payment_links |
      :profile`, the kind of preview WhatsApp rendered (`nil` if absent). A plain
      link card is usually `:none`; `:video`/`:image` mark rich media links.
  """

  @type preview_type ::
          :none | :video | :placeholder | :image | :payment_links | :profile

  @type t :: %__MODULE__{
          url: String.t() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          thumbnail: binary() | nil,
          type: preview_type() | nil
        }

  defstruct [:url, :title, :description, :thumbnail, :type]

  @doc """
  Build a `%LinkPreview{}` from an `ExtendedTextMessage` proto (or `nil`), or `nil`
  when the message carries no preview. A preview is considered present when the
  message has a matched URL, a title, or a description — so a plain reply/mention
  `extendedTextMessage` (text + contextInfo only) yields `nil`.
  """
  @spec from_proto(struct() | nil) :: t() | nil
  def from_proto(nil), do: nil

  def from_proto(%{} = ext) do
    url = presence(Map.get(ext, :matchedText))
    title = presence(Map.get(ext, :title))
    description = presence(Map.get(ext, :description))

    if url || title || description do
      %__MODULE__{
        url: url,
        title: title,
        description: description,
        thumbnail: Map.get(ext, :jpegThumbnail),
        type: preview_type(Map.get(ext, :previewType))
      }
    end
  end

  defp presence(s) when is_binary(s) and s != "", do: s
  defp presence(_), do: nil

  defp preview_type(:NONE), do: :none
  defp preview_type(:VIDEO), do: :video
  defp preview_type(:PLACEHOLDER), do: :placeholder
  defp preview_type(:IMAGE), do: :image
  defp preview_type(:PAYMENT_LINKS), do: :payment_links
  defp preview_type(:PROFILE), do: :profile
  defp preview_type(_), do: nil
end
