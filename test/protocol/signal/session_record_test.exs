defmodule Amarula.Protocol.Signal.SessionRecordTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Signal.SessionRecord, as: SR

  defp entry(base_key, opts \\ []) do
    %{
      registration_id: Keyword.get(opts, :reg_id, 1),
      current_ratchet: %{},
      index_info: %{
        created: 0,
        used: Keyword.get(opts, :used, 0),
        remote_identity_key: <<9>>,
        base_key: base_key,
        base_key_type: Keyword.get(opts, :type, SR.base_key_theirs()),
        closed: Keyword.get(opts, :closed, -1)
      },
      chains: %{}
    }
  end

  test "set_session / get_session round-trip by base key" do
    bk = <<1, 2, 3>>
    record = SR.new() |> SR.set_session(entry(bk))

    assert SR.get_session(record, bk).index_info.base_key == bk
    assert SR.get_session(record, <<9, 9>>) == nil
  end

  test "get_session raises when resolving one of our own base keys" do
    bk = <<5>>
    record = SR.new() |> SR.set_session(entry(bk, type: SR.base_key_ours()))

    assert_raise RuntimeError, "Tried to lookup a session using our basekey", fn ->
      SR.get_session(record, bk)
    end
  end

  test "open/closed sessions" do
    open = entry(<<1>>, closed: -1)
    closed = entry(<<2>>, closed: 123)
    record = SR.new() |> SR.set_session(closed) |> SR.set_session(open)

    assert SR.get_open_session(record).index_info.base_key == <<1>>
    assert SR.have_open_session?(record)

    record2 = SR.close_session(record, open)
    assert SR.get_open_session(record2) == nil
    refute SR.have_open_session?(record2)
  end

  test "get_sessions orders most-recently-used first" do
    record =
      SR.new()
      |> SR.set_session(entry(<<1>>, used: 100))
      |> SR.set_session(entry(<<2>>, used: 300))
      |> SR.set_session(entry(<<3>>, used: 200))

    used = SR.get_sessions(record) |> Enum.map(& &1.index_info.used)
    assert used == [300, 200, 100]
  end

  test "chain add/get/delete on an entry" do
    e = SR.create_entry()
    key = <<7, 7, 7>>
    chain = %{counter: 0}

    e = SR.add_chain(e, key, chain)
    assert SR.get_chain(e, key) == chain

    assert_raise RuntimeError, "Overwrite attempt", fn -> SR.add_chain(e, key, chain) end

    e = SR.delete_chain(e, key)
    assert SR.get_chain(e, key) == nil
    assert_raise RuntimeError, "Not Found", fn -> SR.delete_chain(e, key) end
  end

  test "remove_old_sessions trims closed sessions beyond the cap" do
    # 42 closed sessions, distinct close timestamps; cap is 40
    record =
      Enum.reduce(1..42, SR.new(), fn i, acc ->
        SR.set_session(acc, entry(<<i::16>>, closed: i))
      end)

    trimmed = SR.remove_old_sessions(record)
    assert map_size(trimmed.sessions) == 40
    # The two oldest (closed: 1, 2) are gone
    refute Map.has_key?(trimmed.sessions, Base.encode64(<<1::16>>))
    refute Map.has_key?(trimmed.sessions, Base.encode64(<<2::16>>))
  end
end
