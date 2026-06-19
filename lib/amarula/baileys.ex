defmodule Amarula.Baileys do
  @moduledoc """
  Which upstream Baileys revision Amarula's port currently tracks.

  Amarula is a port of [Baileys](https://github.com/WhiskeySockets/Baileys); its
  protocol logic is meant to stay faithful to a *specific* upstream revision. This
  module is the single source of truth for which one — so you can `git diff` that
  revision against newer Baileys and find changes worth porting.

  This is **source parity**, distinct from the **WhatsApp Web protocol version**
  (`Amarula.Config`'s `:version`, e.g. `[2, 3000, ...]`) which is the on-the-wire
  version WhatsApp must accept. Baileys can refactor logic we'd want to mirror
  without the WA version changing, and vice versa — keep the two separate.

  See `docs/PARITY.md` for the bump runbook (how to sync to a newer Baileys).
  """

  @typedoc "The pinned upstream Baileys revision Amarula tracks."
  @type parity :: %{
          version: String.t(),
          commit: String.t(),
          date: String.t(),
          repo: String.t()
        }

  # Bump these together whenever you re-sync the port to a newer Baileys.
  # `commit` is the exact upstream SHA reviewed; `date` is that commit's date.
  @parity %{
    version: "7.0.0-rc13",
    commit: "eb595a5a8f0fd6b753ee97e3b2d77612fafa501d",
    date: "2026-06-10",
    repo: "https://github.com/WhiskeySockets/Baileys"
  }

  @doc """
  The pinned upstream Baileys revision this build of Amarula tracks.

      iex> Amarula.Baileys.parity().version
      "7.0.0-rc13"
  """
  @spec parity() :: parity()
  def parity, do: @parity
end
