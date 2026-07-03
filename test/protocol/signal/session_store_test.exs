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
