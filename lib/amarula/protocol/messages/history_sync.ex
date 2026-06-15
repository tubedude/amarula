defmodule Amarula.Protocol.Messages.HistorySync do
  @moduledoc """
  Download + decode the history-sync blob a `HISTORY_SYNC_NOTIFICATION` points to,
  ported from Baileys `downloadHistory`/`processHistoryMessage` (`Utils/history.ts`).

  On first link (and incrementally), the primary device pushes the chat history as
  an external, encrypted, zlib-deflated blob referenced by the notification. We
  download it (media crypto, `:history` keys), inflate, and decode a
  `Proto.HistorySync` — yielding the conversations (chats), contacts, and their
  messages. This is what populates the chat list, and acking/consuming it is what
  moves the phone from "Paused" to "active".
  """

  alias Amarula.{Address, Chat, Contact}
  alias Amarula.Protocol.Messages.Media
  alias Amarula.Protocol.Proto

  @type result :: %{
          sync_type: atom(),
          chats: [Chat.t()],
          contacts: [Contact.t()]
        }

  @doc """
  Download + decode the blob for a `%HistorySyncNotification{}`. Returns
  `{:ok, %{sync_type, chats, contacts}}` or `{:error, reason}`.
  """
  @spec fetch(struct()) :: {:ok, result()} | {:error, term()}
  def fetch(notification) do
    with {:ok, deflated} <- raw_blob(notification),
         {:ok, raw} <- inflate(deflated) do
      sync = Proto.HistorySync.decode(raw)
      {:ok, to_result(sync)}
    end
  end

  # A HISTORY_SYNC_NOTIFICATION is delivered one of two ways:
  #   * inline — `initialHistBootstrapInlinePayload` carries the (still-deflated)
  #     bytes directly (e.g. PUSH_NAME / small chunks); no download.
  #   * external — `directPath`+`mediaKey` reference an encrypted blob to download.
  defp raw_blob(%{initialHistBootstrapInlinePayload: inline}) when is_binary(inline),
    do: {:ok, inline}

  defp raw_blob(%{directPath: dp, mediaKey: mk} = n) when is_binary(dp) and is_binary(mk) do
    Media.download(%{directPath: dp, url: Map.get(n, :url), mediaKey: mk}, :history)
  end

  defp raw_blob(_notification), do: {:error, :no_history_payload}

  # The blob is raw zlib (deflate); inflate to the HistorySync protobuf bytes.
  defp inflate(deflated) do
    z = :zlib.open()

    try do
      :zlib.inflateInit(z)
      raw = :zlib.inflate(z, deflated) |> IO.iodata_to_binary()
      :zlib.inflateEnd(z)
      {:ok, raw}
    rescue
      e -> {:error, {:inflate_failed, e}}
    after
      :zlib.close(z)
    end
  end

  defp to_result(sync) do
    convos = sync.conversations || []

    %{
      sync_type: sync.syncType,
      chats: Enum.map(convos, &chat/1),
      contacts: Enum.flat_map(convos, &contact/1),
      # push names keyed by jid (incl. our own — used to learn me.name)
      push_names: for(p <- sync.pushnames || [], p.pushname, do: {p.id, p.pushname})
    }
  end

  defp chat(convo) do
    %Chat{
      address: Address.parse(convo.id),
      archived: convo.archived,
      pinned: pinned?(convo),
      mute_end: convo.muteEndTime,
      unread: convo.unreadCount
    }
  end

  defp contact(convo) do
    name = convo.displayName || convo.name

    if is_binary(name) and name != "" do
      [%Contact{address: Address.parse(convo.id), full_name: name}]
    else
      []
    end
  end

  defp pinned?(%{pinned: p}) when is_integer(p), do: p > 0
  defp pinned?(_), do: nil
end
