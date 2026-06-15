defmodule Amarula.Protocol.Socket.IQTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Socket.IQ

  defp reply(id, type), do: %Node{tag: "iq", attrs: %{"id" => id, "type" => type}, content: nil}
  defp timer, do: make_ref()

  test "resolve a tracked result → {:tracked, kind, {:ok, node}, timer}" do
    p = IQ.track(%{}, "i1", :digest, t = timer())
    {pending, effect} = IQ.resolve(p, reply("i1", "result"))
    assert pending == %{}
    assert {:tracked, :digest, {:ok, %Node{}}, ^t} = effect
  end

  test "resolve a tracked error result → {:tracked, kind, {:error, node}, timer}" do
    p = IQ.track(%{}, "i1", :prekey_count, timer())

    {_pending, {:tracked, :prekey_count, {:error, %Node{}}, _}} =
      IQ.resolve(p, reply("i1", "error"))
  end

  test "resolve a plain waiter → {:reply, from, {:ok, node}, timer}" do
    from = {self(), make_ref()}
    p = IQ.wait(%{}, "i1", from, t = timer(), nil)
    {pending, effect} = IQ.resolve(p, reply("i1", "result"))
    assert pending == %{}
    assert {:reply, ^from, {:ok, %Node{}}, ^t} = effect
  end

  test "resolve a transform waiter applies the transform to the result" do
    from = {self(), make_ref()}
    transform = fn {:ok, _node} -> {:ok, :mapped} end
    p = IQ.wait(%{}, "i1", from, timer(), transform)
    {_pending, {:reply, ^from, {:ok, :mapped}, _}} = IQ.resolve(p, reply("i1", "result"))
  end

  test "resolve an unknown id → :none, pending unchanged" do
    p = IQ.track(%{}, "other", :digest, timer())
    {pending, :none} = IQ.resolve(p, reply("missing", "result"))
    assert Map.has_key?(pending, "other")
  end

  test "timeout a waiter → {:reply, from, {:error, :timeout}, timer}" do
    from = {self(), make_ref()}
    p = IQ.wait(%{}, "i1", from, t = timer(), nil)
    {%{}, {:reply, ^from, {:error, :timeout}, ^t}} = IQ.timeout(p, "i1")
  end

  test "timeout a tracked → {:tracked, kind, {:error, :timeout}, timer}" do
    p = IQ.track(%{}, "i1", :app_state_sync, timer())
    {%{}, {:tracked, :app_state_sync, {:error, :timeout}, _}} = IQ.timeout(p, "i1")
  end

  test "timeout an unknown id → :none" do
    {%{}, :none} = IQ.timeout(%{}, "missing")
  end
end
