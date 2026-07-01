defmodule Amarula.Content.OptionsTest do
  use ExUnit.Case, async: true

  alias Amarula.Content.Options
  alias Amarula.Protocol.Proto

  @meta %{
    id: "M",
    channel: Amarula.Address.parse("biz@s.whatsapp.net"),
    from: Amarula.Address.parse("biz@s.whatsapp.net")
  }

  defp classify(proto), do: Amarula.Msg.from_proto(proto, @meta)

  describe "list message" do
    @list %Proto.Message{
      listMessage: %Proto.Message.ListMessage{
        title: "Main menu",
        description: "Choose an option",
        buttonText: "Open",
        footerText: "Powered by bot",
        sections: [
          %Proto.Message.ListMessage.Section{
            title: "Support",
            rows: [
              %Proto.Message.ListMessage.Row{
                title: "Billing",
                description: "Pay a bill",
                rowId: "opt_billing"
              },
              %Proto.Message.ListMessage.Row{title: "Tech", rowId: "opt_tech"}
            ]
          }
        ]
      }
    }

    test "classifies as :list with a flat option list" do
      msg = classify(@list)
      assert msg.type == :list
      assert %Options{kind: :list} = msg.content
      assert msg.content.title == "Main menu"
      assert msg.content.body == "Choose an option"
      assert msg.content.button_text == "Open"
      assert msg.content.footer == "Powered by bot"

      assert msg.content.options == [
               %{id: "opt_billing", text: "Billing", description: "Pay a bill"},
               %{id: "opt_tech", text: "Tech", description: nil}
             ]
    end
  end

  describe "buttons message" do
    test "classifies as :buttons with id+text per button" do
      proto = %Proto.Message{
        buttonsMessage: %Proto.Message.ButtonsMessage{
          contentText: "Confirm?",
          buttons: [
            %Proto.Message.ButtonsMessage.Button{
              buttonId: "yes",
              buttonText: %Proto.Message.ButtonsMessage.Button.ButtonText{displayText: "Yes"}
            },
            %Proto.Message.ButtonsMessage.Button{
              buttonId: "no",
              buttonText: %Proto.Message.ButtonsMessage.Button.ButtonText{displayText: "No"}
            }
          ]
        }
      }

      msg = classify(proto)
      assert msg.type == :buttons
      assert msg.content.body == "Confirm?"

      assert msg.content.options == [
               %{id: "yes", text: "Yes", description: nil},
               %{id: "no", text: "No", description: nil}
             ]
    end
  end

  describe "template message" do
    test "classifies as :template, mapping the hydrated button oneof" do
      proto = %Proto.Message{
        templateMessage: %Proto.Message.TemplateMessage{
          hydratedTemplate: %Proto.Message.TemplateMessage.HydratedFourRowTemplate{
            title: {:hydratedTitleText, "Order"},
            hydratedContentText: "Track your order",
            hydratedButtons: [
              %Proto.HydratedTemplateButton{
                hydratedButton:
                  {:quickReplyButton,
                   %Proto.HydratedTemplateButton.HydratedQuickReplyButton{
                     displayText: "Track",
                     id: "track_1"
                   }}
              },
              %Proto.HydratedTemplateButton{
                hydratedButton:
                  {:urlButton,
                   %Proto.HydratedTemplateButton.HydratedURLButton{
                     displayText: "Website",
                     url: "https://x.test"
                   }}
              }
            ]
          }
        }
      }

      msg = classify(proto)
      assert msg.type == :template
      assert msg.content.title == "Order"
      assert msg.content.body == "Track your order"

      assert msg.content.options == [
               %{id: "track_1", text: "Track", description: nil},
               %{id: "https://x.test", text: "Website", description: nil}
             ]
    end
  end

  describe "interactive (native flow) message" do
    test "classifies as :interactive, surfacing the native-flow buttons" do
      proto = %Proto.Message{
        interactiveMessage: %Proto.Message.InteractiveMessage{
          header: %Proto.Message.InteractiveMessage.Header{title: "Flow"},
          body: %Proto.Message.InteractiveMessage.Body{text: "Tap a button"},
          footer: %Proto.Message.InteractiveMessage.Footer{text: "footer"},
          interactiveMessage:
            {:nativeFlowMessage,
             %Proto.Message.InteractiveMessage.NativeFlowMessage{
               buttons: [
                 %Proto.Message.InteractiveMessage.NativeFlowMessage.NativeFlowButton{
                   name: "cta_url",
                   buttonParamsJson: ~s({"display_text":"Visit"})
                 }
               ]
             }}
        }
      }

      msg = classify(proto)
      assert msg.type == :interactive
      assert msg.content.title == "Flow"
      assert msg.content.body == "Tap a button"
      assert msg.content.footer == "footer"

      assert msg.content.options == [
               %{id: nil, text: "cta_url", description: ~s({"display_text":"Visit"})}
             ]
    end
  end

  test "a template delivered via the format oneof is still mapped" do
    proto = %Proto.Message{
      templateMessage: %Proto.Message.TemplateMessage{
        format:
          {:hydratedFourRowTemplate,
           %Proto.Message.TemplateMessage.HydratedFourRowTemplate{
             hydratedContentText: "Via oneof",
             hydratedButtons: [
               %Proto.HydratedTemplateButton{
                 hydratedButton:
                   {:quickReplyButton,
                    %Proto.HydratedTemplateButton.HydratedQuickReplyButton{
                      displayText: "Tap",
                      id: "t1"
                    }}
               }
             ]
           }}
      }
    }

    msg = classify(proto)
    assert msg.type == :template
    assert msg.content.body == "Via oneof"
    assert msg.content.options == [%{id: "t1", text: "Tap", description: nil}]
  end

  test "a template with no hydrated form degrades gracefully" do
    proto = %Proto.Message{templateMessage: %Proto.Message.TemplateMessage{}}
    msg = classify(proto)
    assert msg.type == :template
    assert msg.content.options == []
  end
end
