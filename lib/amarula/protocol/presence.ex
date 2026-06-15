defmodule Amarula.Protocol.Presence do
  @moduledoc """
  Build presence / chat-state stanzas, ported from Baileys `sendPresenceUpdate`
  and `presenceSubscribe` (`src/Socket/chats.ts`).

  Pure stanza construction; the `ConnectionManager` supplies `me` and writes the
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
