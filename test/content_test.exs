defmodule Amarula.ContentTest do
  @moduledoc "Value-correctness of the normalized `%Amarula.Content.*` structs."
  use ExUnit.Case, async: true

  alias Amarula.Content
  alias Amarula.Protocol.Proto

  @meta %{id: "M", channel: Amarula.Address.parse("g@g.us"), from: Amarula.Address.parse("1@s")}
  defp content(proto), do: Amarula.Msg.from_proto(proto, @meta).content

  test "location normalizes coordinates + flags" do
    c =
      content(%Proto.Message{
        locationMessage: %Proto.Message.LocationMessage{
          degreesLatitude: 1.5,
          degreesLongitude: 2.5,
          name: "Park",
          isLive: true
        }
      })

    assert %Content.Location{latitude: 1.5, longitude: 2.5, name: "Park", live?: true} = c
  end

  test "poll normalizes name + option names + selectable count" do
    c =
      content(%Proto.Message{
        pollCreationMessage: %Proto.Message.PollCreationMessage{
          name: "Lunch?",
          selectableOptionsCount: 1,
          options: [
            %Proto.Message.PollCreationMessage.Option{optionName: "Pizza"},
            %Proto.Message.PollCreationMessage.Option{optionName: "Sushi"}
          ]
        }
      })

    assert %Content.Poll{name: "Lunch?", options: ["Pizza", "Sushi"], selectable_count: 1} = c
  end

  test "event nests a normalized %Content.Location{} (not the proto)" do
    c =
      content(%Proto.Message{
        eventMessage: %Proto.Message.EventMessage{
          name: "Picnic",
          startTime: 1_700_000_000,
          location: %Proto.Message.LocationMessage{degreesLatitude: 1.0, name: "Field"}
        }
      })

    assert %Content.Event{name: "Picnic", start_time: 1_700_000_000} = c
    assert %Content.Location{latitude: 1.0, name: "Field"} = c.location
  end

  test "group invite surfaces code + group + caption" do
    c =
      content(%Proto.Message{
        groupInviteMessage: %Proto.Message.GroupInviteMessage{
          groupJid: "123@g.us",
          inviteCode: "ABCD",
          groupName: "Team",
          caption: "join"
        }
      })

    assert %Content.GroupInvite{
             group_jid: "123@g.us",
             code: "ABCD",
             group_name: "Team",
             caption: "join"
           } =
             c
  end

  test "contacts array reuses %Content.Contact{} per element" do
    c =
      content(%Proto.Message{
        contactsArrayMessage: %Proto.Message.ContactsArrayMessage{
          displayName: "Team",
          contacts: [
            %Proto.Message.ContactMessage{displayName: "Bob", vcard: "BEGIN:VCARD"},
            %Proto.Message.ContactMessage{displayName: "Ann"}
          ]
        }
      })

    assert %{
             display_name: "Team",
             contacts: [
               %Content.Contact{display_name: "Bob"},
               %Content.Contact{display_name: "Ann"}
             ]
           } =
             c
  end

  test "pin/keep carry the target as a {jid, msg_id} ref" do
    key = %Proto.MessageKey{remoteJid: "x@s", id: "A"}

    pin =
      content(%Proto.Message{
        pinInChatMessage: %Proto.Message.PinInChatMessage{key: key, type: :PIN_FOR_ALL}
      })

    assert pin == %{key: {"x@s", "A"}, pinned?: true}

    keep =
      content(%Proto.Message{
        keepInChatMessage: %Proto.Message.KeepInChatMessage{key: key, keepType: :KEEP_FOR_ALL}
      })

    assert keep == %{key: {"x@s", "A"}, kept?: true}
  end

  test "interactive responses unify into %Content.Response{kind, id, text}" do
    btn =
      content(%Proto.Message{
        buttonsResponseMessage: %Proto.Message.ButtonsResponseMessage{
          selectedButtonId: "b1",
          response: {:selectedDisplayText, "Yes"}
        }
      })

    assert %Content.Response{kind: :button, id: "b1", text: "Yes"} = btn

    tmpl =
      content(%Proto.Message{
        templateButtonReplyMessage: %Proto.Message.TemplateButtonReplyMessage{
          selectedId: "t1",
          selectedDisplayText: "OK"
        }
      })

    assert %Content.Response{kind: :template, id: "t1", text: "OK"} = tmpl
  end
end
