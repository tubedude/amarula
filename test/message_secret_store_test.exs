defmodule Amarula.MessageSecretStoreTest do
  use ExUnit.Case, async: true

  alias Amarula.MessageSecretStore
  alias Amarula.MessageSecretStore.{ETS, ReadOnly, Scope}

  @sender "10000000001@s.whatsapp.net"

  describe "scope/1 resolves the adapter spec" do
    test "defaults to the ETS adapter with no config" do
      assert %Scope{adapter: ETS} = MessageSecretStore.scope(%{})
    end

    test "accepts a {adapter, opts} spec, a bare module, and a prebuilt scope" do
      assert %Scope{adapter: ETS, state: %{ttl_ms: 1000}} =
               MessageSecretStore.scope(%{message_secret_store: {ETS, ttl_ms: 1000}})

      assert %Scope{adapter: ETS} = MessageSecretStore.scope(%{message_secret_store: ETS})

      built = %Scope{adapter: ETS, state: %{ttl_ms: 5}}
      assert MessageSecretStore.scope(%{message_secret_store: built}) == built
    end
  end

  describe "ETS adapter" do
    setup do
      profile = :"msg_secret_test_#{System.unique_integer([:positive])}"
      scope = MessageSecretStore.scope(%{})
      :ok = MessageSecretStore.ensure_local(scope, profile)
      {:ok, scope: scope, profile: profile}
    end

    test "ensure_local is idempotent", %{scope: scope, profile: profile} do
      assert MessageSecretStore.ensure_local(scope, profile) == :ok
    end

    test "put/get round-trips secret + sender", %{scope: scope, profile: profile} do
      secret = :crypto.strong_rand_bytes(32)
      entry = %{secret: secret, sender: @sender}

      assert MessageSecretStore.put(scope, profile, "MSG1", entry) == :ok
      assert MessageSecretStore.get(scope, profile, "MSG1") == {:ok, entry}
      assert MessageSecretStore.count(scope, profile) == 1
    end

    test "miss is :error", %{scope: scope, profile: profile} do
      assert MessageSecretStore.get(scope, profile, "NOPE") == :error
    end

    test "an entry past the edit window is expired on read", %{profile: profile} do
      state = ETS.new(ttl_ms: 1000)
      :ok = ETS.ensure_local(state, profile)
      now = 1_000_000_000

      :ok = ETS.put(state, profile, "OLD", %{secret: <<1>>, sender: @sender}, now)
      assert {:ok, _} = ETS.get(state, profile, "OLD", now + 999)
      assert ETS.get(state, profile, "OLD", now + 1001) == :error
    end

    test "writes sweep expired rows, bounding the table", %{profile: profile} do
      state = ETS.new(ttl_ms: 1000)
      :ok = ETS.ensure_local(state, profile)
      now = 1_000_000_000

      for i <- 1..10,
          do: ETS.put(state, profile, "OLD#{i}", %{secret: <<i>>, sender: @sender}, now)

      assert ETS.count(state, profile) == 10

      :ok = ETS.put(state, profile, "NEW", %{secret: <<0>>, sender: @sender}, now + 1001)
      assert ETS.count(state, profile) == 1
    end

    test "an unknown profile is a silent miss and mints no atom", %{scope: scope} do
      assert MessageSecretStore.get(scope, "never_ensured_xyz", "M") == :error

      assert MessageSecretStore.put(scope, "never_ensured_xyz", "M", %{
               secret: <<1>>,
               sender: @sender
             }) == :ok

      assert_raise ArgumentError, fn ->
        String.to_existing_atom("amarula_msg_secret_never_ensured_xyz")
      end
    end
  end

  describe "ReadOnly adapter (consumer-backed store)" do
    test "get delegates to the consumer closure; writes are no-ops" do
      secret = :crypto.strong_rand_bytes(32)

      scope =
        MessageSecretStore.scope(%{
          message_secret_store:
            {ReadOnly,
             get: fn _profile, msg_id ->
               case msg_id do
                 "KNOWN" -> {:ok, %{secret: secret, sender: @sender}}
                 _ -> :error
               end
             end}
        })

      assert %Scope{adapter: ReadOnly} = scope
      # No ETS table is ever created for this adapter.
      assert MessageSecretStore.ensure_local(scope, :p) == :ok
      # put is a no-op (the behaviour's optional callback is absent).
      assert MessageSecretStore.put(scope, :p, "KNOWN", %{secret: <<9>>, sender: "x"}) == :ok

      assert MessageSecretStore.get(scope, :p, "KNOWN") ==
               {:ok, %{secret: secret, sender: @sender}}

      assert MessageSecretStore.get(scope, :p, "OTHER") == :error
    end

    test "new/1 rejects a non-arity-2 :get" do
      assert_raise ArgumentError, fn -> ReadOnly.new(get: fn -> :nope end) end
    end
  end
end
