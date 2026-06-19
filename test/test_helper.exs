defmodule Amarula.TestConn do
  @moduledoc """
  Test helper: build an `%Amarula.Conn{}` backed by the filesystem adapter at a
  throwaway directory, for store/persistence tests.
  """

  @doc """
  A Conn whose File adapter is rooted at `dir` (so state lands under
  `<dir>/<profile>/`). `profile` defaults to `:test`.
  """
  def new(dir, profile \\ :test) do
    Amarula.Conn.new(%{profile: profile, storage: {Amarula.Storage.File, root: dir}})
  end
end

# Several suites assert on async message delivery (the offline sandbox pushing a
# synthetic inbound to parent_pid). The 100ms default assert_receive timeout can
# starve under a loaded/contended CI runner and flake. 2s is still effectively
# instant for a passing test (the delivery is sub-ms when not starved) but gives
# a loaded runner ample slack.
ExUnit.start(assert_receive_timeout: 2000)
