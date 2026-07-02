defmodule Amarula.ConfigTest do
  use ExUnit.Case, async: false

  alias Amarula.Config

  @env "AMARULA_WA_VERSION"

  describe "wa_version/0 env override" do
    setup do
      on_exit(fn -> System.delete_env(@env) end)
      :ok
    end

    test "returns the pinned default when the env var is unset" do
      System.delete_env(@env)
      assert [2, 3000, rev] = Config.wa_version()
      assert is_integer(rev)
      # defaults/0 and merge/1 reflect the same value
      assert Config.defaults().version == Config.wa_version()
      assert Config.merge(%{}).version == Config.wa_version()
    end

    test "a valid dotted triple overrides the default" do
      System.put_env(@env, "2.3000.9999")
      assert Config.wa_version() == [2, 3000, 9999]
      assert Config.defaults().version == [2, 3000, 9999]
      # explicit caller :version still wins over the env default
      assert Config.merge(%{version: [2, 3000, 1]}).version == [2, 3000, 1]
    end

    test "a malformed value is ignored and falls back to the pinned default" do
      System.delete_env(@env)
      pinned = Config.wa_version()

      for bad <- ["garbage", "2.3000", "2.3000.x", "2.3000.-1", "1.2.3.4"] do
        System.put_env(@env, bad)
        assert Config.wa_version() == pinned, "expected #{bad} to fall back"
      end
    end

    test "surrounding whitespace is tolerated" do
      System.put_env(@env, "  2.3000.12345  ")
      assert Config.wa_version() == [2, 3000, 12345]
    end
  end
end
