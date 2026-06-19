defmodule Amarula.Plugins.MessageStoreTest do
  use ExUnit.Case, async: true

  alias Amarula.Plugins.MessageStore
  alias Amarula.Protocol.Proto

  setup do
    dir = Path.join(System.tmp_dir!(), "msgstore_#{System.unique_integer([:positive])}")
    {:ok, store} = MessageStore.start_link(dir: dir)
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, store: store}
  end

  test "put/get round-trips an outgoing message", %{store: store} do
    msg = %Proto.Message{conversation: "out"}
    MessageStore.put(store, %{remote_jid: "x@s.whatsapp.net", id: "OUT1"}, msg)
    assert MessageStore.get_message(store, "OUT1") == {"x@s.whatsapp.net", msg}
  end

  test "get_message returns nil for unknown id", %{store: store} do
    assert MessageStore.get_message(store, "NOPE") == nil
  end

  test "persists incoming messages from socket events", %{store: store} do
    msg = %Proto.Message{conversation: "in"}

    send(
      store,
      {:amarula, :messages_upsert, %{from: "y@s.whatsapp.net", id: "IN1", messages: [msg]}}
    )

    # cast/info are async; wait for processing via a sync call
    _ = MessageStore.get_message(store, "_flush")
    assert MessageStore.get_message(store, "IN1") == {"y@s.whatsapp.net", msg}
  end

  test "get_message_fun closure is usable as the :get_message config callback", %{store: store} do
    msg = %Proto.Message{conversation: "cb"}
    MessageStore.put(store, %{remote_jid: "z@s.whatsapp.net", id: "CB1"}, msg)
    fun = MessageStore.get_message_fun(store)

    assert fun.("CB1") == {"z@s.whatsapp.net", msg}
    assert fun.("missing") == nil
  end
end
