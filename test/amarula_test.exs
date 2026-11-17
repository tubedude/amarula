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

  test "send_reaction (via {jid, msg_id, from_me}) sends to the target's remoteJid", %{conn: conn} do
    ref = {"x@s.whatsapp.net", "ABC", false}
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

  describe "outbound MessageKey jids are account-level (#46)" do
    # A message key is an ADDRESS — (chat, fromMe, id) plus `participant` in a group.
    # Every client normalizes those on decode, so a device suffix names a participant
    # nobody else agrees on and the key matches no message. `msg.from` carries the
    # sending device by design, so the library was handing consumers a device-bearing
    # address and then putting it straight into `participant`.
    @group "120363000000000000@g.us"
    @author "5511888888888@s.whatsapp.net"
    @author_dev "5511888888888:29@s.whatsapp.net"

    defp group_msg(from_jid, opts \\ []) do
      Amarula.Msg.from_proto(%Proto.Message{conversation: "hi"}, %{
        id: "ABC",
        channel: Amarula.Address.parse(@group),
        from: Amarula.Address.parse(from_jid),
        from_me: Keyword.get(opts, :from_me, false)
      })
    end

    test "a group author's device is stripped from participant", %{conn: conn} do
      # THE REGRESSION: reacting to a group message written from WhatsApp Web.
      Amarula.send_reaction(conn, group_msg(@author_dev), "👍")

      assert_received {:got, {:send_message, @group, out}}
      key = out.reactionMessage.key
      assert key.participant == @author
      refute key.participant =~ ":"
      assert key.remoteJid == @group
    end

    test "an already account-level participant is unchanged", %{conn: conn} do
      Amarula.send_reaction(conn, group_msg(@author), "👍")

      assert_received {:got, {:send_message, @group, out}}
      assert out.reactionMessage.key.participant == @author
    end

    test "an agent segment is stripped from participant too", %{conn: conn} do
      Amarula.send_reaction(conn, group_msg("5511888888888_1@s.whatsapp.net"), "👍")

      assert_received {:got, {:send_message, @group, out}}
      assert out.reactionMessage.key.participant == @author
    end

    test "fromMe still rides through untouched", %{conn: conn} do
      # Normalization must not disturb the one field the %Msg{} path already got
      # right (the `{jid, msg_id}` form's hardcoded false is the open half of #46).
      Amarula.send_reaction(conn, group_msg(@author_dev, from_me: true), "👍")

      assert_received {:got, {:send_message, @group, out}}
      assert out.reactionMessage.key.fromMe == true
      assert out.reactionMessage.key.participant == @author
    end

    test "send_edit and send_revoke normalize participant as well", %{conn: conn} do
      msg = group_msg(@author_dev)

      Amarula.send_edit(conn, msg, "v2")
      assert_received {:got, {:send_message, @group, edit}}
      assert edit.protocolMessage.key.participant == @author

      Amarula.send_revoke(conn, msg)
      assert_received {:got, {:send_message, @group, rev}}
      assert rev.protocolMessage.key.participant == @author
    end

    test "a device-bearing chat jid in the {jid, id, from_me} form is normalized", %{conn: conn} do
      # A caller who passes `msg.from` as the chat would otherwise reintroduce it.
      Amarula.send_reaction(conn, {@author_dev, "ABC", false}, "👍")

      assert_received {:got, {:send_message, target, out}}
      assert target == @author
      assert out.reactionMessage.key.remoteJid == @author
    end

    test "a group jid passes through unchanged (normalization is idempotent)", %{conn: conn} do
      Amarula.send_reaction(conn, {@group, "ABC", false}, "👍")

      assert_received {:got, {:send_message, @group, out}}
      assert out.reactionMessage.key.remoteJid == @group
    end

    test "resolve_quoted's resend key normalizes the quoted author", %{conn: conn} do
      # A quote whose inline copy is absent → the server-resend path, which builds
      # its own key from `quoted.from`.
      ctx = %Proto.ContextInfo{stanzaId: "QID", participant: @author_dev}

      msg =
        Amarula.Msg.from_proto(
          %Proto.Message{
            extendedTextMessage: %Proto.Message.ExtendedTextMessage{text: "re", contextInfo: ctx}
          },
          %{id: "REPLY", channel: Amarula.Address.parse(@group)}
        )

      assert {:requested, _} = Amarula.resolve_quoted(conn, msg)
      assert_received {:got, {:request_resend, key}}
      assert key.participant == @author
      assert key.remoteJid == @group
    end
  end

  describe "outbound MessageKey carries from_me (#46)" do
    @pn "5511888888888@s.whatsapp.net"
    @pn_dev "5511888888888:29@s.whatsapp.net"

    test "the {jid, id, from_me} tuple sets fromMe explicitly", %{conn: conn} do
      Amarula.send_reaction(conn, {@pn, "ABC", true}, "👍")
      assert_received {:got, {:send_message, @pn, out}}
      assert out.reactionMessage.key.fromMe == true

      Amarula.send_reaction(conn, {@pn, "ABC", false}, "👍")
      assert_received {:got, {:send_message, @pn, out2}}
      assert out2.reactionMessage.key.fromMe == false
    end

    test "the 4-tuple carries a group participant, account-level", %{conn: conn} do
      Amarula.send_reaction(conn, {"g@g.us", "ABC", false, @pn_dev}, "👍")
      assert_received {:got, {:send_message, "g@g.us", out}}
      assert out.reactionMessage.key.fromMe == false
      # participant is normalized on the way out (device stripped).
      assert out.reactionMessage.key.participant == @pn
    end

    # Removed in 0.6.0. These two previously asserted the guess it made per
    # operation (`true` for self-ops like send_edit, `false` elsewhere) — the guess
    # is the whole reason it went: getting it wrong makes an edit or revoke match
    # nothing, silently, because the payload is E2E-encrypted.
    # Built at runtime so the compiler's type checker can't narrow it: passing a
    # literal 2-tuple now warns at compile time (that is the 0.5.7 type narrowing
    # working), which would be noise in a test that exists to exercise the removed
    # path on purpose.
    defp deprecated_ref, do: List.to_tuple([@pn, "ABC"])

    test "the 2-tuple raises instead of guessing, on every ref-taking helper", %{conn: conn} do
      ref = deprecated_ref()

      for call <- [
            fn -> Amarula.send_edit(conn, ref, "v2") end,
            fn -> Amarula.send_reaction(conn, ref, "👍") end,
            fn -> Amarula.send_revoke(conn, ref) end,
            fn -> Amarula.pin_message(conn, ref) end,
            fn -> Amarula.keep_message(conn, ref) end
          ] do
        assert_raise ArgumentError, call
      end

      # Nothing was relayed — it fails before building a stanza, so no half-formed
      # operation reaches the server.
      refute_received {:got, {:send_message, _, _}}
    end

    test "the raise says what to pass instead, echoing the caller's own values", %{conn: conn} do
      err =
        assert_raise ArgumentError, fn -> Amarula.send_reaction(conn, deprecated_ref(), "x") end

      assert err.message =~ "removed in 0.6.0"
      # The suggested replacement is concrete, not generic advice.
      assert err.message =~ ~s({"#{@pn}", "ABC", from_me})
      assert err.message =~ "content.key"
    end

    test "a %Amarula.Msg{} carries its own from_me through", %{conn: conn} do
      msg =
        Amarula.Msg.from_proto(%Proto.Message{conversation: "hi"}, %{
          id: "ABC",
          channel: Amarula.Address.parse(@pn),
          from: Amarula.Address.parse(@pn),
          from_me: true
        })

      Amarula.send_reaction(conn, msg, "👍")
      assert_received {:got, {:send_message, @pn, out}}
      assert out.reactionMessage.key.fromMe == true
    end
  end

  test "send_edit / send_revoke build the right protocol message", %{conn: conn} do
    ref = {"x@s.whatsapp.net", "ABC", true}

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
    ref = {"g@g.us", "ABC", true}

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

    test "accepts a lightweight {jid, id, from_me} ref with explicit :kind/:text/:index", %{
      conn: conn
    } do
      ref = {"x@s.whatsapp.net", "PROMPT2", false}

      assert {:ok, "MSGID"} =
               Amarula.send_options_reply(conn, ref, "b",
                 kind: :template,
                 text: "Second",
                 index: 1
               )

      assert_received {:got, {:send_message, "x@s.whatsapp.net", msg}}
      assert msg.templateButtonReplyMessage.selectedId == "b"
      assert msg.templateButtonReplyMessage.selectedDisplayText == "Second"
      assert msg.templateButtonReplyMessage.selectedIndex == 1
      assert msg.templateButtonReplyMessage.contextInfo.stanzaId == "PROMPT2"
    end

    test "raises when :kind can't be determined (tuple ref, no override)", %{conn: conn} do
      ref = {"x@s.whatsapp.net", "PROMPT3", false}

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
