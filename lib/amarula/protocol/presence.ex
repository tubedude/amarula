defmodule Amarula.Protocol.Presence do
  @moduledoc """
  Build presence / chat-state stanzas, ported from Baileys `sendPresenceUpdate`
  and `presenceSubscribe` (`src/Socket/chats.ts`).

  Pure stanza construction; the `Connection` supplies `me` and writes the
  node. Two kinds:

    * **global presence** — `available` / `unavailable`: `<presence name= type=>`.
    * **chat state** — `composing` / `recording` / `paused` toward a jid:
      `<chatstate from= to=><composing|paused/></chatstate>`. `recording` is a
      `composing` tag with `media: "audio"`.
  """

  alias Amarula.Protocol.Binary.{JID, Node}

  @type presence :: :available | :unavailable
  @type chatstate :: :composing | :recording | :paused

  @doc """
  Global online/offline presence. `me` is the auth creds `me` map (needs `:name`;
  Baileys skips the update without one). Returns `{:ok, node}` or
  `{:error, :no_name}`.
  """
  @spec presence(presence(), map()) :: {:ok, Node.t()} | {:error, :no_name}
  def presence(type, %{name: name})
      when type in [:available, :unavailable] and is_binary(name) and name != "" do
    # Baileys strips '@' from the name.
    attrs = %{"name" => String.replace(name, "@", ""), "type" => Atom.to_string(type)}
    {:ok, %Node{tag: "presence", attrs: attrs, content: nil}}
  end

  def presence(type, _me) when type in [:available, :unavailable], do: {:error, :no_name}

  @doc """
  A chat-state (typing) stanza toward `to_jid`. `from` is `me.lid` when `to_jid`
  is a lid jid, else `me.id`.
  """
  @spec chatstate(chatstate(), String.t(), map()) :: Node.t()
  def chatstate(type, to_jid, me) when type in [:composing, :recording, :paused] do
    from = if JID.is_lid_user?(to_jid), do: me.lid, else: me.id
    {tag, child_attrs} = child(type)

    %Node{
      tag: "chatstate",
      attrs: %{"from" => from, "to" => to_jid},
      content: [%Node{tag: tag, attrs: child_attrs, content: nil}]
    }
  end

  @typedoc """
  A parsed inbound presence/chat-state update (Baileys `presence.update`):

    * `:jid`         — the chat the update is for (`attrs.from`)
    * `:participant` — who within the chat (group member, or the contact itself)
    * `:presence`    — `:available` / `:unavailable` (a `<presence>`) or
      `:composing` / `:recording` / `:paused`→`:available` (a `<chatstate>`)
    * `:last_seen`   — unix seconds from a `<presence last=>` (nil otherwise)
  """
  @type update :: %{
          jid: String.t(),
          participant: String.t(),
          presence: presence() | :composing | :recording,
          last_seen: integer() | nil
        }

  @doc """
  Parse an inbound `<presence>` or `<chatstate>` node into an `update/0`
  (Baileys `handlePresenceUpdate`). Returns `{:error, :invalid}` for a malformed
  node. `from`/`participant` are returned as wire jid strings.
  """
  @spec parse_update(Node.t()) :: {:ok, update()} | {:error, :invalid}
  def parse_update(%Node{tag: "presence", attrs: attrs}) do
    presence = if attrs["type"] == "unavailable", do: :unavailable, else: :available
    {:ok, attrs |> base_update(presence) |> Map.put(:last_seen, last_seen(attrs))}
  end

  def parse_update(%Node{tag: "chatstate", attrs: attrs, content: [%Node{} = child | _]}) do
    {:ok, base_update(attrs, chatstate_presence(child))}
  end

  def parse_update(%Node{}), do: {:error, :invalid}

  # paused → available (Baileys); composing+media:audio → recording.
  defp chatstate_presence(%Node{tag: "paused"}), do: :available
  defp chatstate_presence(%Node{tag: "composing", attrs: %{"media" => "audio"}}), do: :recording
  defp chatstate_presence(%Node{tag: tag}), do: String.to_atom(tag)

  defp base_update(attrs, presence) do
    jid = attrs["from"]
    %{jid: jid, participant: attrs["participant"] || jid, presence: presence}
  end

  defp last_seen(%{"last" => last}) when last != "deny" do
    case Integer.parse(last) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp last_seen(_attrs), do: nil

  @doc "A `<presence type=subscribe>` stanza for `to_jid` (tcToken omitted)."
  @spec subscribe(String.t(), String.t()) :: Node.t()
  def subscribe(to_jid, id) do
    %Node{
      tag: "presence",
      attrs: %{"to" => to_jid, "id" => id, "type" => "subscribe"},
      content: nil
    }
  end

  # recording = a composing tag flagged as audio media.
  defp child(:recording), do: {"composing", %{"media" => "audio"}}
  defp child(:composing), do: {"composing", %{}}
  defp child(:paused), do: {"paused", %{}}
end
