defmodule Amarula.MsgNoProtoLeakTest do
  @moduledoc """
  The invariant: a `%Amarula.Msg{}`'s `content` must contain **no** `%Proto.*{}`
  value. The raw proto is available on `msg.raw`; `content` is the clean,
  consumer-facing view. This guards every classify branch against regressing to
  leak a protobuf.
  """
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Proto

  @meta %{
    id: "M",
    channel: Amarula.Address.parse("g@g.us"),
    from: Amarula.Address.parse("1@s.whatsapp.net")
  }

  defp build(proto), do: Amarula.Msg.from_proto(proto, @meta)

  # Recursively assert no value reachable from `content` is a struct under the
  # Amarula.Protocol.Proto.* namespace.
  defp refute_proto(%_{} = struct, path) do
    mod = struct.__struct__ |> Atom.to_string()

    refute String.starts_with?(mod, "Elixir.Amarula.Protocol.Proto."),
           "#{path} leaks a protobuf struct: #{mod}"

    # Recurse into non-proto structs too (e.g. nested %Content.Location{} in an event).
    struct |> Map.from_struct() |> Enum.each(fn {k, v} -> refute_proto(v, "#{path}.#{k}") end)
  end

  defp refute_proto(%{} = map, path),
    do: Enum.each(map, fn {k, v} -> refute_proto(v, "#{path}[#{inspect(k)}]") end)

  defp refute_proto(list, path) when is_list(list),
    do: Enum.with_index(list) |> Enum.each(fn {v, i} -> refute_proto(v, "#{path}[#{i}]") end)

  defp refute_proto(tuple, path) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> refute_proto(path)

  defp refute_proto(_scalar, _path), do: :ok

  # One representative proto per classify branch. If a branch is added to
  # MessageContent without a proto-free content mapping, add it here and it must pass.
  @samples [
    %Proto.Message{conversation: "hi"},
    %Proto.Message{imageMessage: %Proto.Message.ImageMessage{directPath: "/x"}},
    %Proto.Message{videoMessage: %Proto.Message.VideoMessage{seconds: 3}},
    %Proto.Message{audioMessage: %Proto.Message.AudioMessage{seconds: 3}},
    %Proto.Message{documentMessage: %Proto.Message.DocumentMessage{fileName: "f.pdf"}},
    %Proto.Message{stickerMessage: %Proto.Message.StickerMessage{mimetype: "image/webp"}},
    %Proto.Message{
      reactionMessage: %Proto.Message.ReactionMessage{
        key: %Proto.MessageKey{remoteJid: "x@s", id: "A"},
        text: "👍"
      }
    },
    %Proto.Message{
      protocolMessage: %Proto.Message.ProtocolMessage{
        type: :MESSAGE_EDIT,
        key: %Proto.MessageKey{remoteJid: "x@s", id: "A"},
        editedMessage: %Proto.Message{conversation: "fixed"}
      }
    },
    %Proto.Message{
      protocolMessage: %Proto.Message.ProtocolMessage{
        type: :REVOKE,
        key: %Proto.MessageKey{remoteJid: "x@s", id: "A"}
      }
    },
    %Proto.Message{
      protocolMessage: %Proto.Message.ProtocolMessage{type: :APP_STATE_SYNC_KEY_SHARE}
    },
    %Proto.Message{
      pinInChatMessage: %Proto.Message.PinInChatMessage{
        key: %Proto.MessageKey{remoteJid: "x@s", id: "A"},
        type: :PIN_FOR_ALL
      }
    },
    %Proto.Message{
      keepInChatMessage: %Proto.Message.KeepInChatMessage{
        key: %Proto.MessageKey{remoteJid: "x@s", id: "A"},
        keepType: :KEEP_FOR_ALL
      }
    },
    %Proto.Message{contactMessage: %Proto.Message.ContactMessage{displayName: "Bob"}},
    %Proto.Message{
      contactsArrayMessage: %Proto.Message.ContactsArrayMessage{
        displayName: "Team",
        contacts: [%Proto.Message.ContactMessage{displayName: "Bob"}]
      }
    },
    %Proto.Message{locationMessage: %Proto.Message.LocationMessage{degreesLatitude: 1.0}},
    %Proto.Message{
      pollCreationMessage: %Proto.Message.PollCreationMessage{
        name: "Q",
        options: [%Proto.Message.PollCreationMessage.Option{optionName: "A"}]
      }
    },
    %Proto.Message{
      pollUpdateMessage: %Proto.Message.PollUpdateMessage{
        pollCreationMessageKey: %Proto.MessageKey{remoteJid: "x@s", id: "A"}
      }
    },
    %Proto.Message{eventMessage: %Proto.Message.EventMessage{name: "Launch"}},
    %Proto.Message{
      eventMessage: %Proto.Message.EventMessage{
        name: "Picnic",
        location: %Proto.Message.LocationMessage{degreesLatitude: 1.0}
      }
    },
    %Proto.Message{groupInviteMessage: %Proto.Message.GroupInviteMessage{inviteCode: "C"}},
    %Proto.Message{productMessage: %Proto.Message.ProductMessage{businessOwnerJid: "biz@s"}},
    %Proto.Message{orderMessage: %Proto.Message.OrderMessage{orderId: "O"}},
    %Proto.Message{
      buttonsResponseMessage: %Proto.Message.ButtonsResponseMessage{selectedButtonId: "b1"}
    },
    %Proto.Message{listResponseMessage: %Proto.Message.ListResponseMessage{title: "pick"}},
    %Proto.Message{
      templateButtonReplyMessage: %Proto.Message.TemplateButtonReplyMessage{selectedId: "t1"}
    },
    %Proto.Message{
      interactiveResponseMessage: %Proto.Message.InteractiveResponseMessage{}
    },
    %Proto.Message{
      listMessage: %Proto.Message.ListMessage{
        title: "Menu",
        sections: [
          %Proto.Message.ListMessage.Section{
            title: "Drinks",
            rows: [%Proto.Message.ListMessage.Row{title: "Coffee", rowId: "r1"}]
          }
        ]
      }
    },
    %Proto.Message{
      buttonsMessage: %Proto.Message.ButtonsMessage{
        contentText: "Pick",
        buttons: [
          %Proto.Message.ButtonsMessage.Button{
            buttonId: "b1",
            buttonText: %Proto.Message.ButtonsMessage.Button.ButtonText{displayText: "Yes"}
          }
        ]
      }
    },
    %Proto.Message{
      templateMessage: %Proto.Message.TemplateMessage{
        hydratedTemplate: %Proto.Message.TemplateMessage.HydratedFourRowTemplate{
          hydratedContentText: "Choose",
          hydratedButtons: [
            %Proto.HydratedTemplateButton{
              hydratedButton:
                {:quickReplyButton,
                 %Proto.HydratedTemplateButton.HydratedQuickReplyButton{
                   displayText: "Go",
                   id: "q1"
                 }}
            }
          ]
        }
      }
    },
    %Proto.Message{
      interactiveMessage: %Proto.Message.InteractiveMessage{
        body: %Proto.Message.InteractiveMessage.Body{text: "Hello"},
        interactiveMessage:
          {:nativeFlowMessage,
           %Proto.Message.InteractiveMessage.NativeFlowMessage{
             buttons: [
               %Proto.Message.InteractiveMessage.NativeFlowMessage.NativeFlowButton{
                 name: "cta_url",
                 buttonParamsJson: "{}"
               }
             ]
           }}
      }
    },
    # :other catch-all
    %Proto.Message{}
  ]

  test "no classify branch leaks a protobuf into content" do
    for proto <- @samples do
      msg = build(proto)
      refute_proto(msg.content, "#{msg.type}.content")
      # sanity: the raw proto IS still available (the escape hatch).
      assert %Proto.Message{} = msg.raw
    end
  end
end
