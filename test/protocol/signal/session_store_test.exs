defmodule Amarula.Protocol.Signal.SessionStoreTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Signal.{SessionStore, SessionRecord}
  alias Amarula.Protocol.Auth.AuthUtils

  setup do
    dir = Path.join(System.tmp_dir!(), "amarula_sess_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir, conn: Amarula.TestConn.new(dir)}
  end

  test "build/1 exposes our identity and signed prekey from creds" do
    creds = AuthUtils.init_auth_creds()
    store = SessionStore.build(creds)

    assert store.our_identity.public == creds.signed_identity_key.public
    assert store.our_identity.private == creds.signed_identity_key.private

    spk = store.load_signed_pre_key.(creds.signed_pre_key.key_id)
    assert spk.public == creds.signed_pre_key.key_pair.public
    assert spk.private == creds.signed_pre_key.key_pair.private

    # No one-time prekeys yet
    assert store.load_pre_key.(1234) == nil
  end

  test "session record round-trips to disk", %{conn: conn} do
    addr = "15550001234.0"
    assert SessionStore.load_session(conn, addr) == nil

    record =
      SessionRecord.new()
      |> SessionRecord.set_session(%{
        registration_id: 7,
        current_ratchet: %{root_key: <<1, 2, 3>>},
        index_info: %{
          created: 0,
          used: 0,
          remote_identity_key: <<9>>,
          base_key: <<4, 5, 6>>,
          base_key_type: SessionRecord.base_key_theirs(),
          closed: -1
        },
        chains: %{}
      })

    assert :ok = SessionStore.store_session(conn, addr, record)
    loaded = SessionStore.load_session(conn, addr)
    assert loaded == record
  end

  test "different addresses use different files", %{conn: conn} do
    :ok = SessionStore.store_session(conn, "a.0", %{sessions: %{x: 1}})
    :ok = SessionStore.store_session(conn, "b.1", %{sessions: %{y: 2}})

    assert SessionStore.load_session(conn, "a.0") == %{sessions: %{x: 1}}
    assert SessionStore.load_session(conn, "b.1") == %{sessions: %{y: 2}}
  end

  test "store_session prunes oldest closed sessions past the cap", %{conn: conn} do
    addr = "15550001234.0"

    # 42 closed sessions (cap is 40) plus one open — mirrors a record that kept
    # accumulating ratchets across re-pairings.
    record =
      Enum.reduce(1..42, SessionRecord.new(), fn i, acc ->
        SessionRecord.set_session(acc, entry(<<i::16>>, closed: i))
      end)
      |> SessionRecord.set_session(entry(<<0::16>>, closed: -1))

    assert :ok = SessionStore.store_session(conn, addr, record)
    loaded = SessionStore.load_session(conn, addr)

    assert map_size(loaded.sessions) == 40
    # The oldest closed sessions were dropped, newest closed + the open one kept.
    refute Map.has_key?(loaded.sessions, Base.encode64(<<1::16>>))
    refute Map.has_key?(loaded.sessions, Base.encode64(<<2::16>>))
    refute Map.has_key?(loaded.sessions, Base.encode64(<<3::16>>))
    assert Map.has_key?(loaded.sessions, Base.encode64(<<42::16>>))
    assert Map.has_key?(loaded.sessions, Base.encode64(<<0::16>>))
  end

  describe "migrate_pn_to_lid/4" do
    # List the session keys and migrate in one shot, as the callers do.
    defp migrate(conn, pn_user, lid_user) do
      {:ok, keys} = SessionStore.list_session_keys(conn)
      SessionStore.migrate_pn_to_lid(conn, pn_user, lid_user, keys)
    end

    test "moves a PN session onto the LID address and deletes the PN entry", %{conn: conn} do
      :ok = SessionStore.store_session(conn, "199999.0", %{sessions: %{r: 1}})

      assert 1 == migrate(conn, "199999", "188888")

      assert SessionStore.load_session(conn, "188888_1.0") == %{sessions: %{r: 1}}
      assert SessionStore.load_session(conn, "199999.0") == nil
    end

    test "migrates every device the PN user has", %{conn: conn} do
      :ok = SessionStore.store_session(conn, "199999.0", %{sessions: %{d: 0}})
      :ok = SessionStore.store_session(conn, "199999.3", %{sessions: %{d: 3}})

      assert 2 == migrate(conn, "199999", "188888")

      assert SessionStore.load_session(conn, "188888_1.0") == %{sessions: %{d: 0}}
      assert SessionStore.load_session(conn, "188888_1.3") == %{sessions: %{d: 3}}
      assert SessionStore.load_session(conn, "199999.0") == nil
      assert SessionStore.load_session(conn, "199999.3") == nil
    end

    test "the live PN ratchet wins over a pre-existing LID session", %{conn: conn} do
      :ok = SessionStore.store_session(conn, "188888_1.0", %{sessions: %{stale: true}})
      :ok = SessionStore.store_session(conn, "199999.0", %{sessions: %{live: true}})

      assert 1 == migrate(conn, "199999", "188888")
      assert SessionStore.load_session(conn, "188888_1.0") == %{sessions: %{live: true}}
    end

    test "returns 0 and changes nothing when the PN user has no session", %{conn: conn} do
      assert 0 == migrate(conn, "199999", "188888")
      assert SessionStore.load_session(conn, "188888_1.0") == nil
    end

    test "leaves a different user whose id merely shares a prefix untouched", %{conn: conn} do
      :ok = SessionStore.store_session(conn, "199999.0", %{sessions: %{target: true}})
      :ok = SessionStore.store_session(conn, "1999990.0", %{sessions: %{bystander: true}})

      assert 1 == migrate(conn, "199999", "188888")

      # The "." boundary in the prefix prevents matching the longer id.
      assert SessionStore.load_session(conn, "1999990.0") == %{sessions: %{bystander: true}}
    end

    test "is idempotent — a second run (e.g. after restart) is a no-op", %{conn: conn} do
      :ok = SessionStore.store_session(conn, "199999.0", %{sessions: %{live: true}})

      assert 1 == migrate(conn, "199999", "188888")
      # The PN entry is gone, so a re-run (the connection's MapSet guard is empty
      # again after a restart) finds nothing to move and leaves the LID session be.
      assert 0 == migrate(conn, "199999", "188888")
      assert SessionStore.load_session(conn, "188888_1.0") == %{sessions: %{live: true}}
    end
  end

  describe "delete_user_sessions/3" do
    defp delete_user(conn, signal_user) do
      {:ok, keys} = SessionStore.list_session_keys(conn)
      SessionStore.delete_user_sessions(conn, signal_user, keys)
    end

    test "deletes every device session for the user and returns the count", %{conn: conn} do
      :ok = SessionStore.store_session(conn, "199999.0", %{sessions: %{d: 0}})
      :ok = SessionStore.store_session(conn, "199999.2", %{sessions: %{d: 2}})
      :ok = SessionStore.store_session(conn, "188888.0", %{sessions: %{other: true}})

      assert 2 == delete_user(conn, "199999")

      assert SessionStore.load_session(conn, "199999.0") == nil
      assert SessionStore.load_session(conn, "199999.2") == nil
      # a different user is untouched
      assert SessionStore.load_session(conn, "188888.0") == %{sessions: %{other: true}}
    end

    test "returns 0 when the user has no session", %{conn: conn} do
      assert 0 == delete_user(conn, "199999")
    end

    test "the '.' boundary spares a longer id sharing the prefix", %{conn: conn} do
      :ok = SessionStore.store_session(conn, "199999.0", %{sessions: %{d: 0}})
      :ok = SessionStore.store_session(conn, "1999990.0", %{sessions: %{bystander: true}})

      assert 1 == delete_user(conn, "199999")
      assert SessionStore.load_session(conn, "1999990.0") == %{sessions: %{bystander: true}}
    end
  end

  describe "list_session_keys/1" do
    test "returns every stored session address", %{conn: conn} do
      :ok = SessionStore.store_session(conn, "199999.0", %{sessions: %{a: 1}})
      :ok = SessionStore.store_session(conn, "188888_1.2", %{sessions: %{b: 2}})

      assert {:ok, keys} = SessionStore.list_session_keys(conn)
      assert Enum.sort(keys) == ["188888_1.2", "199999.0"]
    end

    test "is empty when nothing is stored", %{conn: conn} do
      assert {:ok, []} = SessionStore.list_session_keys(conn)
    end
  end

  defp entry(base_key, opts) do
    %{
      registration_id: 1,
      current_ratchet: %{},
      index_info: %{
        created: 0,
        used: 0,
        remote_identity_key: <<9>>,
        base_key: base_key,
        base_key_type: SessionRecord.base_key_theirs(),
        closed: Keyword.fetch!(opts, :closed)
      },
      chains: %{}
    }
  end
end
