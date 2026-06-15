defmodule Amarula.Protocol.Receipt do
  @moduledoc """
  Build read receipts, ported from Baileys `sendReceipt` (`type: "read"`,
  `src/Socket/messages-send.ts`).

  A read receipt acks one or more message ids in a chat:

      <receipt id="<first id>" type="read" t="<unix s>" to="<jid>" [participant=]>
        <list><item id="<id2>"/>…</list>   # only if >1 id
      </receipt>

  The ids must belong to the same chat (`to`) / sender (`participant`). Pure
  construction; the `Connection` writes the node.
  """

  alias Amarula.Protocol.Binary.Node

  @doc """
  A read receipt for `message_ids` in chat `jid` (optionally from `participant`
  in a group). `now` is the unix-seconds timestamp (injectable for tests).
  """
  @spec read([String.t(), ...], String.t(), String.t() | nil, integer()) :: Node.t()
  def read([first | rest], jid, participant \\ nil, now \\ System.os_time(:second)) do
    attrs =
      %{"id" => first, "type" => "read", "t" => Integer.to_string(now), "to" => jid}
      |> maybe_put("participant", participant)

    %Node{tag: "receipt", attrs: attrs, content: list_content(rest)}
  end

  # Extra ids ride in a <list><item id=.../></list>; a single id has no content.
  defp list_content([]), do: nil

  defp list_content(ids) do
    items = Enum.map(ids, fn id -> %Node{tag: "item", attrs: %{"id" => id}, content: nil} end)
    [%Node{tag: "list", attrs: %{}, content: items}]
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
end
