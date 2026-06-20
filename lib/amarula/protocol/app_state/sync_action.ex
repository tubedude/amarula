defmodule Amarula.Protocol.AppState.SyncAction do
  @moduledoc """
  Turn a decoded app-state mutation (`Amarula.Protocol.AppState.Patch` output)
  into a consumer-facing change, ported from Baileys `processSyncAction`
  (`chat-utils.ts`).

  A mutation's `index` is `[type, id, msg_id, from_me]` and the `SyncActionValue`
  carries the change. We map the chat/contact-relevant ones to `%Amarula.Chat{}`
  / `%Amarula.Contact{}` tagged tuples; everything else is `{:other, action}` so
  nothing is silently lost.

  Pure: `decode/1` takes a mutation map, returns a tagged result.
  """

  alias Amarula.{Address, Chat, Contact}

  @type result ::
          {:chat, Chat.t()}
          | {:contact, Contact.t()}
          | {:push_name, String.t()}
          | {:other, term()}

  @doc "Decode one mutation into a tagged consumer change."
  @spec decode(%{operation: :set | :remove, action: struct(), index: [String.t()]}) :: result()
  def decode(%{action: %{value: value}, index: index, operation: operation}) do
    classify(value, index, operation)
  end

  # --- chat actions (index = [type, id | _]) ---

  defp classify(%{muteAction: %{} = m}, [_type, id | _], _op) do
    {:chat, %Chat{address: addr(id), mute_end: if(m.muted, do: m.muteEndTimestamp)}}
  end

  defp classify(%{archiveChatAction: %{} = a}, [_type, id | _], _op) do
    {:chat, %Chat{address: addr(id), archived: a.archived}}
  end

  defp classify(%{pinAction: %{} = p}, [_type, id | _], _op) do
    # `PinAction.pinned` is proto3-optional: the server omits it for some
    # conversations, leaving it nil (Baileys #2328: "pinned undefined for some").
    # Coerce to a definite boolean — only an explicit `pinned: true` is pinned;
    # absent / nil / false all mean unpinned — so consumers never see nil.
    {:chat, %Chat{address: addr(id), pinned: p.pinned == true}}
  end

  defp classify(%{markChatAsReadAction: %{} = r}, [_type, id | _], _op) do
    {:chat, %Chat{address: addr(id), unread: if(r.read, do: 0, else: -1)}}
  end

  defp classify(%{deleteChatAction: %{}}, [_type, id | _], _op) do
    {:chat, %Chat{address: addr(id), deleted: true}}
  end

  defp classify(%{clearChatAction: %{}}, [_type, id | _], _op) do
    {:chat, %Chat{address: addr(id), deleted: false}}
  end

  # --- contact / push name ---

  defp classify(%{contactAction: %{} = c}, [_type, id | _], _op) do
    {:contact, %Contact{address: addr(id), full_name: c.fullName, first_name: c.firstName}}
  end

  defp classify(%{pushNameSetting: %{name: name}}, _index, _op) when is_binary(name) do
    {:push_name, name}
  end

  defp classify(value, _index, _op), do: {:other, value}

  defp addr(id), do: Address.parse(id)
end
