defmodule Amarula.Protocol.Signal.TcTokenStoreTest do
  use ExUnit.Case, async: true

  alias Amarula.Conn
  alias Amarula.Protocol.Signal.{LidMappingFileStore, TcTokenStore}
  alias Amarula.Storage

  @profile :tctoken_test
  @pn "15551234567@s.whatsapp.net"
  @lid "987654321@lid"

  # Mirrors TcTokenStore's own 7-day bucket / 4-bucket window.
  @bucket 604_800

  setup do
    dir = Path.join(System.tmp_dir!(), "amarula_tctoken_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    conn =
      Conn.new(%{
        profile: @profile,
        storage: {Amarula.Storage.File, root: dir}
      })

    :ok =
      LidMappingFileStore.store_mappings(conn, [{@lid, @pn}])
      |> then(fn {_count, _new} -> :ok end)

    {:ok, conn: conn}
  end

  test "finds a token stored under the mapped LID JID for a PN send", %{conn: conn} do
    token = "trusted-contact-token"

    :ok =
      Storage.put(conn.storage, @profile, :tctoken, @lid, %{
        token: token,
        timestamp: System.system_time(:second)
      })

    assert TcTokenStore.valid_token(conn, @pn) == token
  end

  test "a token older than the ~28-day window is not attached", %{conn: conn} do
    put_token(conn, %{token: "stale", timestamp: now() - 4 * @bucket})

    assert TcTokenStore.valid_token(conn, @pn) == nil
  end

  test "a token inside the window is attached", %{conn: conn} do
    put_token(conn, %{token: "fresh", timestamp: now() - 3 * @bucket})

    assert TcTokenStore.valid_token(conn, @pn) == "fresh"
  end

  describe "valid_entry/2" do
    test "returns the token together with its issue timestamp", %{conn: conn} do
      ts = now() - @bucket
      put_token(conn, %{token: "fresh", timestamp: ts})

      assert TcTokenStore.valid_entry(conn, @pn) == {"fresh", ts}
    end

    test "applies the same expiry window as valid_token/2", %{conn: conn} do
      put_token(conn, %{token: "stale", timestamp: now() - 4 * @bucket})

      assert TcTokenStore.valid_entry(conn, @pn) == nil
    end
  end

  describe "token_children/2" do
    test "builds a <tctoken> carrying the timestamp as the `t` attr", %{conn: conn} do
      ts = now()
      put_token(conn, %{token: "fresh", timestamp: ts})

      assert [node] = TcTokenStore.token_children(conn, @pn)
      assert node.tag == "tctoken"
      assert node.attrs == %{"t" => Integer.to_string(ts)}
      assert node.content == "fresh"
    end

    test "is empty when we hold nothing usable", %{conn: conn} do
      assert TcTokenStore.token_children(conn, @pn) == []

      put_token(conn, %{token: "stale", timestamp: now() - 4 * @bucket})
      assert TcTokenStore.token_children(conn, @pn) == []
    end

    # Groups and newsletters have no trusted-contact token; Baileys gates both
    # call sites on the jid being a user before it even looks in the store.
    test "is empty for a group jid even with a token on file", %{conn: conn} do
      put_token(conn, %{token: "fresh", timestamp: now()})

      assert TcTokenStore.token_children(conn, "12345-67890@g.us") == []
    end
  end

  describe "store_message_node/2 — the proactive source" do
    alias Amarula.Protocol.Binary.Node

    defp msg_node(attrs, children),
      do: %Node{tag: "message", attrs: attrs, content: children}

    defp tctoken(token, ts),
      do: %Node{tag: "tctoken", attrs: %{"t" => Integer.to_string(ts)}, content: token}

    test "captures a token riding on an incoming message, keyed by the mapped LID",
         %{conn: conn} do
      ts = now()

      :ok =
        TcTokenStore.store_message_node(conn, msg_node(%{"from" => @pn}, [tctoken("ride", ts)]))

      # Stored under the LID, so a PN-addressed send finds it too.
      assert TcTokenStore.valid_entry(conn, @pn) == {"ride", ts}
      assert TcTokenStore.valid_entry(conn, @lid) == {"ride", ts}
    end

    test "prefers sender_lid over the from attr when it is a real LID", %{conn: conn} do
      ts = now()
      other = "5559999@s.whatsapp.net"

      :ok =
        TcTokenStore.store_message_node(
          conn,
          msg_node(%{"from" => other, "sender_lid" => @lid}, [tctoken("by-lid", ts)])
        )

      assert TcTokenStore.valid_entry(conn, @lid) == {"by-lid", ts}
    end

    test "ignores a token with no `t` — a timestampless token reads as expired anyway",
         %{conn: conn} do
      node = msg_node(%{"from" => @pn}, [%Node{tag: "tctoken", attrs: %{}, content: "no-ts"}])

      assert :ok = TcTokenStore.store_message_node(conn, node)
      assert TcTokenStore.valid_entry(conn, @pn) == nil
    end

    test "never downgrades a token we already hold at the same or newer timestamp",
         %{conn: conn} do
      ts = now()
      put_token(conn, %{token: "current", timestamp: ts})

      :ok =
        TcTokenStore.store_message_node(
          conn,
          msg_node(%{"from" => @pn}, [tctoken("older", ts - 1)])
        )

      assert TcTokenStore.valid_entry(conn, @pn) == {"current", ts}
    end

    test "preserves sender_timestamp, so post-send issuance dedupe survives capture",
         %{conn: conn} do
      put_token(conn, %{token: "old", timestamp: now() - 10, sender_timestamp: now()})

      :ok =
        TcTokenStore.store_message_node(
          conn,
          msg_node(%{"from" => @pn}, [tctoken("fresh", now())])
        )

      refute TcTokenStore.should_issue_new?(conn, @pn)
    end

    test "a message with no tctoken child is a no-op", %{conn: conn} do
      assert :ok = TcTokenStore.store_message_node(conn, msg_node(%{"from" => @pn}, []))
      assert TcTokenStore.valid_entry(conn, @pn) == nil
    end

    # isRegularUser: PSA and bots must not write a token under a nonsense key.
    test "declines the PSA pseudo-contact and bot senders", %{conn: conn} do
      for from <- ["0@s.whatsapp.net", "13135550002@bot"] do
        assert :ok =
                 TcTokenStore.store_message_node(
                   conn,
                   msg_node(%{"from" => from}, [tctoken("nope", now())])
                 )

        assert TcTokenStore.valid_entry(conn, from) == nil
      end
    end
  end

  describe "store_history_sync/2" do
    test "persists a token the blob carried, keyed by the mapped LID", %{conn: conn} do
      ts = now()

      :ok =
        TcTokenStore.store_history_sync(conn, [
          %{jid: @pn, token: "from-history", timestamp: ts, sender_timestamp: nil}
        ])

      assert TcTokenStore.valid_entry(conn, @pn) == {"from-history", ts}
    end

    test "carries sender_timestamp through, so the reissue dedupe survives", %{conn: conn} do
      :ok =
        TcTokenStore.store_history_sync(conn, [
          %{jid: @pn, token: "t", timestamp: now(), sender_timestamp: now()}
        ])

      refute TcTokenStore.should_issue_new?(conn, @pn)
    end

    test "never downgrades a token we already hold at the same or newer timestamp",
         %{conn: conn} do
      ts = now()
      put_token(conn, %{token: "current", timestamp: ts})

      :ok =
        TcTokenStore.store_history_sync(conn, [
          %{jid: @pn, token: "older", timestamp: ts - @bucket, sender_timestamp: nil},
          # Equal timestamps are skipped too — a blob only ever replays what we
          # may already hold, so `>=` here where store_token/3 uses a strict `>`.
          %{jid: @pn, token: "same-second", timestamp: ts, sender_timestamp: nil}
        ])

      assert TcTokenStore.valid_entry(conn, @pn) == {"current", ts}
    end

    test "a strictly newer token from the blob does replace ours", %{conn: conn} do
      put_token(conn, %{token: "current", timestamp: now() - @bucket})
      newer = now()

      :ok =
        TcTokenStore.store_history_sync(conn, [
          %{jid: @pn, token: "newer", timestamp: newer, sender_timestamp: nil}
        ])

      assert TcTokenStore.valid_entry(conn, @pn) == {"newer", newer}
    end

    test "skips malformed entries without touching the rest", %{conn: conn} do
      ts = now()

      :ok =
        TcTokenStore.store_history_sync(conn, [
          %{jid: @pn, token: nil, timestamp: ts, sender_timestamp: nil},
          %{jid: @pn, token: "good", timestamp: ts, sender_timestamp: nil}
        ])

      assert TcTokenStore.valid_entry(conn, @pn) == {"good", ts}
    end
  end

  describe "build_issue_iq/3 — the issuance jid" do
    test "a LID target is issued against its PN", %{conn: conn} do
      # Baileys `resolveIssuanceJid`: with lidTrustedTokenIssueToLid off (the
      # default this module follows) the server wants the PN, so issuing against
      # the LID earns a token it can't match back to the contact.
      iq = TcTokenStore.build_issue_iq(conn, @lid, 1_700_000_000)
      assert token_jid(iq) == @pn
    end

    test "a PN target is unchanged", %{conn: conn} do
      iq = TcTokenStore.build_issue_iq(conn, @pn, 1_700_000_000)
      assert token_jid(iq) == @pn
    end

    test "an unmapped LID falls back to the LID", %{conn: conn} do
      iq = TcTokenStore.build_issue_iq(conn, "111222333@lid", 1_700_000_000)
      assert token_jid(iq) == "111222333@lid"
    end

    test "a device suffix is stripped", %{conn: conn} do
      iq = TcTokenStore.build_issue_iq(conn, "15551234567:3@s.whatsapp.net", 1_700_000_000)
      assert token_jid(iq) == @pn
    end
  end

  describe "corrupt stored entry" do
    test "a non-map entry doesn't crash the write paths", %{conn: conn} do
      # The read path already degrades; the writes used Map.merge, which raises on
      # a truthy non-map — and the privacy_token write runs in the Connection
      # process, so a corrupt record would take the connection down.
      :ok = Storage.put(conn.storage, @profile, :tctoken, @lid, "corrupt")

      assert TcTokenStore.valid_token(conn, @pn) == nil

      entries = [%{jid: @pn, token: "recovered", timestamp: now()}]
      assert :ok = TcTokenStore.store_history_sync(conn, entries)
      assert TcTokenStore.valid_token(conn, @pn) == "recovered"
    end
  end

  describe "should_issue_new?/2" do
    test "true when we have never issued for this contact", %{conn: conn} do
      assert TcTokenStore.should_issue_new?(conn, @pn)
    end

    test "false again inside the same 7-day bucket", %{conn: conn} do
      put_token(conn, %{token: "t", timestamp: now(), sender_timestamp: now()})

      refute TcTokenStore.should_issue_new?(conn, @pn)
    end

    test "true once the last issuance falls in an earlier bucket", %{conn: conn} do
      put_token(conn, %{token: "t", timestamp: now(), sender_timestamp: now() - @bucket})

      assert TcTokenStore.should_issue_new?(conn, @pn)
    end
  end

  defp token_jid(iq) do
    iq
    |> Amarula.Protocol.Binary.NodeUtils.get_binary_node_child("tokens")
    |> Amarula.Protocol.Binary.NodeUtils.get_binary_node_child("token")
    |> Amarula.Protocol.Binary.NodeUtils.get_attr("jid")
  end

  defp put_token(conn, entry),
    do: :ok = Storage.put(conn.storage, @profile, :tctoken, @lid, entry)

  defp now, do: System.system_time(:second)
end
