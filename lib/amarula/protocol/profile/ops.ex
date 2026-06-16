defmodule Amarula.Protocol.Profile.Ops do
  @moduledoc """
  Profile operations: build the IQs that read/change your (or a target's) profile
  picture and status, and parse their replies. Port of the profile-picture/status
  builders in Baileys `chats.ts` (`profilePictureUrl`, `updateProfilePicture`,
  `removeProfilePicture`, `updateProfileStatus`).

  Pure: builders return a `%Node{}`, parsers turn the reply node into a value. The
  IQ round-trip lives in `Amarula.Connection` (via `query_iq/3`). `target` is the
  jid being acted on, or `nil` for your own profile — Baileys omits the `target`
  attr entirely for self (sending it for your own jid makes the server never reply).
  """

  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Crypto.Constants

  @xmlns_picture "w:profile:picture"

  @type pic_type :: :preview | :image

  # --- IQ builders ---

  @doc """
  Fetch a profile picture URL. `target` is the jid to look up (a user or group jid);
  `type` is `:preview` (small) or `:image` (full). Reply parsed by `parse_url/1`.
  """
  @spec picture_url_query(String.t(), pic_type()) :: Node.t()
  def picture_url_query(target, type \\ :preview) when type in [:preview, :image] do
    picture = %Node{
      tag: "picture",
      attrs: %{"type" => Atom.to_string(type), "query" => "url"},
      content: nil
    }

    iq("get", @xmlns_picture, maybe_target(target), [picture])
  end

  @doc """
  Set a profile picture from already-encoded JPEG bytes. `target` is the jid being
  updated, or `nil` for your own profile. WhatsApp expects a small square JPEG; the
  caller is responsible for sizing it (Baileys resizes to 640px q50 before upload —
  Amarula does not resize, to avoid a native image dependency).
  """
  @spec set_picture(String.t() | nil, binary()) :: Node.t()
  def set_picture(target, jpeg_bytes) when is_binary(jpeg_bytes) do
    picture = %Node{tag: "picture", attrs: %{"type" => "image"}, content: jpeg_bytes}
    iq("set", @xmlns_picture, maybe_target(target), [picture])
  end

  @doc "Remove a profile picture. `target` is the jid, or `nil` for your own profile."
  @spec remove_picture(String.t() | nil) :: Node.t()
  def remove_picture(target) do
    iq("set", @xmlns_picture, maybe_target(target), nil)
  end

  @doc "Set your own profile status/bio text."
  @spec set_status(String.t()) :: Node.t()
  def set_status(status) when is_binary(status) do
    body = %Node{tag: "status", attrs: %{}, content: status}
    iq("set", "status", %{}, [body])
  end

  # --- reply parsing ---

  @doc "Pull the URL from a `w:profile:picture` reply (`<picture url=\"...\">`), or nil."
  @spec parse_url(Node.t()) :: String.t() | nil
  def parse_url(%Node{} = reply) do
    case NodeUtils.get_binary_node_child(reply, "picture") do
      %Node{} = picture -> NodeUtils.get_attr(picture, "url")
      _ -> nil
    end
  end

  # --- internals ---

  defp iq(type, xmlns, extra_attrs, content) do
    attrs =
      Map.merge(
        %{"to" => Constants.s_whatsapp_net(), "type" => type, "xmlns" => xmlns},
        extra_attrs
      )

    %Node{tag: "iq", attrs: attrs, content: content}
  end

  # Self ⇒ no `target` attr; a specific jid ⇒ target=jid.
  defp maybe_target(nil), do: %{}
  defp maybe_target(jid) when is_binary(jid), do: %{"target" => jid}
end
