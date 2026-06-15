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

ExUnit.start()
