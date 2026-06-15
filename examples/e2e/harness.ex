defmodule Amarula.Examples.E2E.Harness do
  @moduledoc """
  Boot two `Amarula.Examples.Connection`s (two accounts we control) on one VM and
  wire them to auto-respond to each other via the e2e plugins. Hands-off: once
  both are `:open`, send one ping from primary and watch the round trip.

  Both accounts must already be paired (run `examples/pair.exs <profile>` first).
  """

  require Logger

  alias Amarula.Address
  alias Amarula.Examples.Connection
  alias Amarula.Examples.E2E.Plugins.{ReactRead, Reply}

  @doc """
  Start both connections. `opts`:

    * `:primary_profile` (default `:primary`), `:guest_profile` (default `:guest`)
    * `:primary_addr`, `:guest_addr` — each peer's `Amarula.Address` (the number
      the *other* side matches incoming messages against).

  Returns `%{primary: pid, guest: pid}`.
  """
  def start(opts) do
    primary_addr = Keyword.fetch!(opts, :primary_addr)
    guest_addr = Keyword.fetch!(opts, :guest_addr)

    # primary reacts+reads guest's texts (terminal); guest replies to primary's.
    {:ok, primary} =
      Connection.start_link(
        profile: Keyword.get(opts, :primary_profile, :primary),
        plugins: [{ReactRead, from: guest_addr}]
      )

    {:ok, guest} =
      Connection.start_link(
        profile: Keyword.get(opts, :guest_profile, :guest),
        plugins: [{Reply, from: primary_addr}]
      )

    %{primary: primary, guest: guest}
  end

  @doc "Wait until both connections are `:open` (or timeout ms). Returns :ok | :timeout."
  def await_open(%{primary: p, guest: g}, timeout \\ 60_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    loop_open(p, g, deadline)
  end

  @doc "Kick the exchange: primary sends one text to `guest_addr`."
  def ping(%{primary: p}, guest_addr, text \\ "e2e ping") do
    Logger.info("primary → guest: #{inspect(text)}")
    Connection.send_text(p, guest_addr, text)
  end

  defp loop_open(p, g, deadline) do
    cond do
      Connection.state(p) == :open and Connection.state(g) == :open -> :ok
      System.monotonic_time(:millisecond) > deadline -> :timeout
      true -> Process.sleep(500) && loop_open(p, g, deadline)
    end
  end

  @doc "Convenience: an Address from a bare PN."
  def pn(number), do: Address.pn(number)
end
