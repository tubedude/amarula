defmodule Amarula.ProfileRegistryTest do
  use ExUnit.Case, async: true

  alias Amarula.ProfileRegistry

  describe "whereis/2" do
    test "raises a message naming Amarula.Supervisor when the registry isn't started" do
      # A distinct, never-started registry name — isolates the "forgot to add
      # Amarula.Supervisor" scenario without touching the global registry the rest
      # of the suite depends on (started once in test_helper.exs).
      conn = %{
        registry: :"ProfileRegistryTest.NeverStarted.#{System.unique_integer([:positive])}"
      }

      assert_raise RuntimeError, ~r/Amarula\.Supervisor is not running/, fn ->
        ProfileRegistry.whereis(conn, :some_profile)
      end
    end

    test "returns nil for an unregistered profile once the registry is started" do
      name = :"ProfileRegistryTest.Started.#{System.unique_integer([:positive])}"
      start_supervised!({Registry, keys: :unique, name: name})

      assert ProfileRegistry.whereis(%{registry: name}, :some_profile) == nil
    end
  end
end
