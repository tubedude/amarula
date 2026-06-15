defmodule Amarula.Protocol.AppState.SyncActionTest do
  use ExUnit.Case, async: true

  alias Amarula.{Address, Chat, Contact}
  alias Amarula.Protocol.AppState.SyncAction
  alias Amarula.Protocol.Proto.SyncActionValue, as: V

  defp mut(value, index), do: %{operation: :set, action: %{value: value}, index: index}
  @jid "5511999999999@s.whatsapp.net"

  test "mute action → %Chat{mute_end}" do
    v = %V{muteAction: %V.MuteAction{muted: true, muteEndTimestamp: 123}}

    assert {:chat, %Chat{address: %Address{kind: :pn}, mute_end: 123}} =
             SyncAction.decode(mut(v, ["mute", @jid]))
  end

  test "unmute → mute_end nil" do
    v = %V{muteAction: %V.MuteAction{muted: false}}
    assert {:chat, %Chat{mute_end: nil}} = SyncAction.decode(mut(v, ["mute", @jid]))
  end

  test "archive action → %Chat{archived}" do
    v = %V{archiveChatAction: %V.ArchiveChatAction{archived: true}}
    assert {:chat, %Chat{archived: true}} = SyncAction.decode(mut(v, ["archive", @jid]))
  end

  test "pin action → %Chat{pinned}" do
    v = %V{pinAction: %V.PinAction{pinned: true}}
    assert {:chat, %Chat{pinned: true}} = SyncAction.decode(mut(v, ["pin_v1", @jid]))
  end

  test "mark read → unread 0; unread → -1" do
    read = %V{markChatAsReadAction: %V.MarkChatAsReadAction{read: true}}
    assert {:chat, %Chat{unread: 0}} = SyncAction.decode(mut(read, ["markChatAsRead", @jid]))
    unread = %V{markChatAsReadAction: %V.MarkChatAsReadAction{read: false}}
    assert {:chat, %Chat{unread: -1}} = SyncAction.decode(mut(unread, ["markChatAsRead", @jid]))
  end

  test "contact action → %Contact{}" do
    v = %V{contactAction: %V.ContactAction{fullName: "Bob B", firstName: "Bob"}}

    assert {:contact, %Contact{address: %Address{}, full_name: "Bob B", first_name: "Bob"}} =
             SyncAction.decode(mut(v, ["contact", @jid]))
  end

  test "push name setting → {:push_name, name}" do
    v = %V{pushNameSetting: %V.PushNameSetting{name: "Me"}}
    assert {:push_name, "Me"} = SyncAction.decode(mut(v, ["setting_pushName"]))
  end

  test "unmapped action → {:other, _}" do
    v = %V{timeFormatAction: %V.TimeFormatAction{isTwentyFourHourFormatEnabled: true}}
    assert {:other, _} = SyncAction.decode(mut(v, ["time_format"]))
  end
end
