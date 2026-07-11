defmodule AmarulaTest do
  use ExUnit.Case, async: true
  doctest Amarula

  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Proto

  # A stand-in for a connection: it answers GenServer.call by recording the
  # request and replying, so we can assert the facade forwards the right message.
  # For {:group_op, iq, transform} it runs the transform against a canned reply
  # (set per-test via set_group_reply/2) so we can test the facade's reply transforms.
  defmodule StubConn do
    use GenServer

    def start_link(test_pid), do: GenServer.start_link(__MODULE__, %{test: test_pid, reply: nil})
    def set_group_reply(pid, reply), do: GenServer.call(pid, {:__set_group_reply, reply})

    def init(state), do: {:ok, state}

    def handle_call({:__set_group_reply, reply}, _from, state),
      do: {:reply, :ok, %{state | reply: reply}}

    def handle_call({:group_op, iq, transform}, _from, state) do
      send(state.test, {:got, {:group_op, iq}})
      {:reply, transform.(state.reply), state}
    end

    def handle_call(request, _from, state) do
      send(state.test, {:got, request})
      {:reply, reply_for(request), state}
    end

    defp reply_for(:get_connection_state), do: :connected
    defp reply_for(:disconnect), do: :ok
    # own_address/1 reads creds.me.id; a linked device carries a :29 suffix.
    defp reply_for(:get_auth_creds), do: %{me: %{id: "5511999999999:29@s.whatsapp.net"}}
    defp reply_for(_), do: {:ok, "MSGID"}
  end

  setup do
    {:ok, conn} = StubConn.start_link(self())
    {:ok, conn: conn}
  end

  test "send_text forwards {:send_text, jid, text, opts}", %{conn: conn} do
    assert {:ok, "MSGID"} = Amarula.send_text(conn, "x@s.whatsapp.net", "hi")
    assert_received {:got, {:send_text, "x@s.whatsapp.net", "hi", []}}
  end

  test "send_reaction (via {jid, msg_id}) sends to the target's remoteJid", %{conn: conn} do
    ref = {"x@s.whatsapp.net", "ABC"}
    assert {:ok, "MSGID"} = Amarula.send_reaction(conn, ref, "👍")
    assert_received {:got, {:send_message, "x@s.whatsapp.net", msg}}
    assert msg.reactionMessage.text == "👍"
    assert msg.reactionMessage.key.id == "ABC"
  end

  test "send_reaction also accepts a %Amarula.Msg{} (derives chat + key)", %{conn: conn} do
    msg =
      Amarula.Msg.from_proto(%Proto.Message{conversation: "hi"}, %{
        id: "ABC",
        channel: Amarula.Address.parse("x@s.whatsapp.net"),
        from: Amarula.Address.parse("x@s.whatsapp.net")
      })

    assert {:ok, "MSGID"} = Amarula.send_reaction(conn, msg, "🔥")
    assert_received {:got, {:send_message, "x@s.whatsapp.net", out}}
    assert out.reactionMessage.text == "🔥"
    assert out.reactionMessage.key.id == "ABC"
  end

  test "send_edit / send_revoke build the right protocol message", %{conn: conn} do
    ref = {"x@s.whatsapp.net", "ABC"}

    Amarula.send_edit(conn, ref, "v2")
    assert_received {:got, {:send_message, "x@s.whatsapp.net", edit}}
    assert edit.protocolMessage.type == :MESSAGE_EDIT

    Amarula.send_revoke(conn, ref)
    assert_received {:got, {:send_message, "x@s.whatsapp.net", rev}}
    assert rev.protocolMessage.type == :REVOKE
  end

  test "send_album sends the parent then each item referencing it", %{conn: conn} do
    items = [{:image, <<1>>, [caption: "a"]}, {:video, <<2>>, []}]
    assert {:ok, "MSGID"} = Amarula.send_album(conn, "g@g.us", items)

    # Parent first: album with the right counts.
    assert_received {:got, {:send_message, "g@g.us", parent}}
    assert parent.albumMessage.expectedImageCount == 1
    assert parent.albumMessage.expectedVideoCount == 1

    # Then each item as a media send carrying :album_parent pointing at the parent.
    assert_received {:got, {:send_media, "g@g.us", :image, <<1>>, img_opts}}
    assert %Proto.MessageKey{id: "MSGID"} = img_opts[:album_parent]
    assert img_opts[:caption] == "a"

    assert_received {:got, {:send_media, "g@g.us", :video, <<2>>, vid_opts}}
    assert %Proto.MessageKey{id: "MSGID"} = vid_opts[:album_parent]
  end

  test "send_event builds an eventMessage to the target jid", %{conn: conn} do
    Amarula.send_event(conn, "g@g.us", "Launch", description: "v1")
    assert_received {:got, {:send_message, "g@g.us", msg}}
    assert msg.eventMessage.name == "Launch"
    assert msg.eventMessage.description == "v1"
  end

  test "send_group_invite builds a groupInviteMessage to the target jid", %{conn: conn} do
    Amarula.send_group_invite(conn, "x@s.whatsapp.net", "123@g.us", "CODE", group_name: "T")
    assert_received {:got, {:send_message, "x@s.whatsapp.net", msg}}
    assert msg.groupInviteMessage.groupJid == "123@g.us"
    assert msg.groupInviteMessage.inviteCode == "CODE"
    assert msg.groupInviteMessage.groupName == "T"
  end

  test "update_member_tag relays a member-label change to the group", %{conn: conn} do
    assert {:ok, "MSGID"} = Amarula.update_member_tag(conn, "g@g.us", "VIP")
    assert_received {:got, {:send_message, "g@g.us", msg}}
    assert msg.protocolMessage.type == :GROUP_MEMBER_LABEL_CHANGE
    assert msg.protocolMessage.memberLabel.label == "VIP"
  end

  test "update_member_tag rejects a label over 30 chars (no silent truncation)", %{conn: conn} do
    assert {:error, :member_tag_too_long} =
             Amarula.update_member_tag(conn, "g@g.us", String.duplicate("x", 31))

    # exactly 30 is allowed
    assert {:ok, _} = Amarula.update_member_tag(conn, "g@g.us", String.duplicate("x", 30))
  end

  test "pin/unpin and keep/unkeep build the right protocol message", %{conn: conn} do
    ref = {"g@g.us", "ABC"}

    Amarula.pin_message(conn, ref)
    assert_received {:got, {:send_message, "g@g.us", pin}}
    assert pin.pinInChatMessage.type == :PIN_FOR_ALL

    Amarula.unpin_message(conn, ref)
    assert_received {:got, {:send_message, "g@g.us", unpin}}
    assert unpin.pinInChatMessage.type == :UNPIN_FOR_ALL

    Amarula.keep_message(conn, ref)
    assert_received {:got, {:send_message, "g@g.us", keep}}
    assert keep.keepInChatMessage.keepType == :KEEP_FOR_ALL

    Amarula.unkeep_message(conn, ref)
    assert_received {:got, {:send_message, "g@g.us", unkeep}}
    assert unkeep.keepInChatMessage.keepType == :UNDO_KEEP_FOR_ALL
  end

  test "send_media forwards {:send_media, jid, type, data, opts}", %{conn: conn} do
    Amarula.send_media(conn, "x@s.whatsapp.net", :document, <<1, 2, 3>>, title: "t")

    assert_received {:got,
                     {:send_media, "x@s.whatsapp.net", :document, <<1, 2, 3>>, [title: "t"]}}
  end

  test "connection_state and disconnect delegate", %{conn: conn} do
    assert Amarula.connection_state(conn) == :connected
    assert_received {:got, :get_connection_state}

    assert Amarula.disconnect(conn) == :ok
    assert_received {:got, :disconnect}
  end

  # --- group op reply transforms (the consumer error contract) ---

  defp error_iq(code, text) do
    {:error,
     %Node{
       tag: "iq",
       attrs: %{"type" => "error"},
       content: [%Node{tag: "error", attrs: %{"code" => code, "text" => text}, content: nil}]
     }}
  end

  test "a failed group op surfaces {:group_op_failed, code, text}", %{conn: conn} do
    StubConn.set_group_reply(conn, error_iq("403", "forbidden"))
    assert {:error, {:group_op_failed, "403", "forbidden"}} = Amarula.Group.leave(conn, "g@g.us")
    assert_received {:got, {:group_op, _iq}}
  end

  test "group_invite_code returns the parsed code on success", %{conn: conn} do
    reply =
      {:ok,
       %Node{
         tag: "iq",
         attrs: %{"type" => "result"},
         content: [%Node{tag: "invite", attrs: %{"code" => "ABC123"}, content: nil}]
       }}

    StubConn.set_group_reply(conn, reply)
    assert {:ok, "ABC123"} = Amarula.Group.invite_code(conn, "g@g.us")
  end

  test "group_create maps a result to an %Amarula.Group{}", %{conn: conn} do
    reply =
      {:ok,
       %Node{
         tag: "iq",
         attrs: %{"type" => "result"},
         content: [
           %Node{
             tag: "group",
             attrs: %{"id" => "120363000000000000@g.us", "subject" => "My Group"},
             content: []
           }
         ]
       }}

    StubConn.set_group_reply(conn, reply)
    assert {:ok, %Amarula.Group{subject: "My Group"}} = Amarula.Group.create(conn, "My Group", [])
  end

  test "a successful set-style group op returns :ok", %{conn: conn} do
    StubConn.set_group_reply(
      conn,
      {:ok, %Node{tag: "iq", attrs: %{"type" => "result"}, content: []}}
    )

    assert :ok = Amarula.Group.update_subject(conn, "g@g.us", "New Name")
  end

  # --- download_media dispatch ---

  test "download_media on a non-media Msg returns {:error, :not_media}" do
    msg = %Amarula.Msg{
      channel: Amarula.Address.parse("x@s.whatsapp.net"),
      type: :text,
      content: "hi",
      raw: %Proto.Message{conversation: "hi"}
    }

    assert {:error, :not_media} = Amarula.download_media(msg)
  end

  # --- own_address/1 (identity / device) ---

  test "own_address/1 returns our PN Address with the companion device", %{conn: conn} do
    addr = Amarula.own_address(conn)
    assert %Amarula.Address{user: "5511999999999", kind: :pn, device: 29} = addr
    assert_received {:got, :get_auth_creds}
  end

  test "own_address/1 always returns an Address: empty Address when no creds / no suffix" do
    # A stub whose creds vary, to exercise the no-suffix and pre-login branches.
    defmodule CredStub do
      use GenServer
      def start_link(me), do: GenServer.start_link(__MODULE__, me)
      def init(me), do: {:ok, me}
      def handle_call(:get_auth_creds, _from, me), do: {:reply, %{me: me}, me}
    end

    {:ok, primary} = CredStub.start_link(%{id: "5511999999999@s.whatsapp.net"})
    assert %Amarula.Address{device: nil, kind: :pn} = Amarula.own_address(primary)

    {:ok, pre_login} = CredStub.start_link(%{})
    assert Amarula.Address.empty?(Amarula.own_address(pre_login))
  end

  # --- convenience delegations forward the right tuple ---

  test "convenience sends forward the expected Socket message", %{conn: conn} do
    Amarula.set_presence(conn, :available)
    assert_received {:got, {:set_presence, :available}}

    Amarula.send_chatstate(conn, "x@s.whatsapp.net", :composing)
    assert_received {:got, {:send_chatstate, "x@s.whatsapp.net", :composing}}

    Amarula.subscribe_presence(conn, "x@s.whatsapp.net")
    assert_received {:got, {:presence_subscribe, "x@s.whatsapp.net"}}

    Amarula.mark_read(conn, "x@s.whatsapp.net", ["ID1"])
    assert_received {:got, {:mark_read, "x@s.whatsapp.net", ["ID1"], nil}}
  end

  describe "send_options_reply/4" do
    defp options_prompt(kind, options, id \\ "PROMPT1") do
      Amarula.Msg.from_proto(%Proto.Message{conversation: "irrelevant"}, %{
        id: id,
        channel: Amarula.Address.parse("x@s.whatsapp.net"),
        from: Amarula.Address.parse("x@s.whatsapp.net")
      })
      |> Map.put(:content, %Amarula.Content.Options{kind: kind, options: options})
    end

    test "auto-derives kind/text for a :buttons prompt (normalized to :button)", %{conn: conn} do
      prompt = options_prompt(:buttons, [%{id: "yes", text: "Yes", description: nil}])

      assert {:ok, "MSGID"} = Amarula.send_options_reply(conn, prompt, "yes")
      assert_received {:got, {:send_message, "x@s.whatsapp.net", msg}}

      assert msg.buttonsResponseMessage.selectedButtonId == "yes"
      assert msg.buttonsResponseMessage.response == {:selectedDisplayText, "Yes"}
      assert msg.buttonsResponseMessage.type == :DISPLAY_TEXT
      assert msg.buttonsResponseMessage.contextInfo.stanzaId == "PROMPT1"
    end

    test "auto-derives text + 0-indexed position for a :template prompt", %{conn: conn} do
      prompt =
        options_prompt(:template, [
          %{id: "a", text: "First", description: nil},
          %{id: "b", text: "Second", description: nil}
        ])

      assert {:ok, "MSGID"} = Amarula.send_options_reply(conn, prompt, "b")
      assert_received {:got, {:send_message, _jid, msg}}

      assert msg.templateButtonReplyMessage.selectedId == "b"
      assert msg.templateButtonReplyMessage.selectedDisplayText == "Second"
      assert msg.templateButtonReplyMessage.selectedIndex == 1
    end

    test "auto-derives title (the option's text) for a :list prompt", %{conn: conn} do
      prompt = options_prompt(:list, [%{id: "row1", text: "Pizza", description: "cheesy"}])

      assert {:ok, "MSGID"} = Amarula.send_options_reply(conn, prompt, "row1")
      assert_received {:got, {:send_message, _jid, msg}}

      assert msg.listResponseMessage.title == "Pizza"
      assert msg.listResponseMessage.singleSelectReply.selectedRowId == "row1"
    end

    test "accepts a lightweight {jid, msg_id} ref with explicit :kind/:text/:index", %{
      conn: conn
    } do
      ref = {"x@s.whatsapp.net", "PROMPT2"}

      assert {:ok, "MSGID"} =
               Amarula.send_options_reply(conn, ref, "b", kind: :template, text: "Second", index: 1)

      assert_received {:got, {:send_message, "x@s.whatsapp.net", msg}}
      assert msg.templateButtonReplyMessage.selectedId == "b"
      assert msg.templateButtonReplyMessage.selectedDisplayText == "Second"
      assert msg.templateButtonReplyMessage.selectedIndex == 1
      assert msg.templateButtonReplyMessage.contextInfo.stanzaId == "PROMPT2"
    end

    test "raises when :kind can't be determined (tuple ref, no override)", %{conn: conn} do
      ref = {"x@s.whatsapp.net", "PROMPT3"}

      assert_raise ArgumentError, ~r/can't determine :kind/, fn ->
        Amarula.send_options_reply(conn, ref, "yes", text: "Yes")
      end
    end

    test "raises when the option id isn't found and no :text override is given", %{conn: conn} do
      prompt = options_prompt(:buttons, [%{id: "yes", text: "Yes", description: nil}])

      assert_raise ArgumentError, ~r/can't determine the display text/, fn ->
        Amarula.send_options_reply(conn, prompt, "no")
      end
    end

    test "raises a specific error for :interactive prompts (not supported yet)", %{conn: conn} do
      prompt = options_prompt(:interactive, [%{id: "x", text: "X", description: nil}])

      assert_raise ArgumentError, ~r/doesn't support :interactive/, fn ->
        Amarula.send_options_reply(conn, prompt, "x")
      end
    end
  end
end
