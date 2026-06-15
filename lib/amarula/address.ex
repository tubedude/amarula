defmodule Amarula.Address do
  @moduledoc """
  A WhatsApp address — the consumer-facing way to name *who/what* a message is
  for or from. The boundary abstraction over the wire JID string.

  Three kinds, distinguished by `:kind`:

    * `:pn`    — a phone-number identity (`<number>@s.whatsapp.net`).
    * `:lid`   — a privacy "Linked ID" (`<id>@lid`). WhatsApp's wire-preferred
      identity; the same person has both a PN and a LID.
    * `:group` — a group chat (`<id>@g.us`). A *container* of participants, not a
      person; its members are fetched separately (group metadata), not stored here.

  `:device` is the device number (`nil` = account-level / primary). An address
  with `device: nil` names the whole account; with a device it names one client.

  ## Parsed-only

  An `Address` is a **pure value** — only what's deterministic from the string.
  It does NOT carry resolved data (a PN's LID, a group's participants, device
  lists): those need connection state, are lazy, and can change, so they stay
  internal. Don't expect `Address.pn(...)` to "know" its LID.

  ## Boundary

  `parse/1` (wire string → `Address`) and `to_jid/1` (`Address` → wire string)
  are the border crossing, delegating to `Amarula.Protocol.Binary.JID`. Above the
  border (public API, events) everything speaks `Address`; the wire/protocol layer
  speaks JID strings. The public API also accepts a raw string and parses it, so
  `Amarula.send_text(conn, "5511...@s.whatsapp.net", ...)` and
  `Amarula.send_text(conn, Address.pn("5511..."), ...)` both work.
  """

  alias Amarula.Protocol.Binary.JID

  @enforce_keys [:user, :kind]
  defstruct [:user, :kind, :device]

  @type kind :: :pn | :lid | :group
  @type t :: %__MODULE__{user: String.t(), kind: kind(), device: non_neg_integer() | nil}

  @server %{pn: "s.whatsapp.net", lid: "lid", group: "g.us"}

  @doc "A PN address from a bare number or full jid string."
  @spec pn(String.t()) :: t()
  def pn(user), do: %__MODULE__{user: user_of(user), kind: :pn, device: nil}

  @doc "A LID address from a bare id or full jid string."
  @spec lid(String.t()) :: t()
  def lid(user), do: %__MODULE__{user: user_of(user), kind: :lid, device: nil}

  @doc "A group address from a bare id or full `@g.us` jid string."
  @spec group(String.t()) :: t()
  def group(id), do: %__MODULE__{user: user_of(id), kind: :group, device: nil}

  @doc """
  Parse a wire jid string into an `Address` (via `JID.decode/1`). Returns `nil`
  for an unparseable/unknown-server string.
  """
  @spec parse(String.t() | t()) :: t() | nil
  def parse(%__MODULE__{} = address), do: address

  def parse(jid) when is_binary(jid) do
    with %{user: user, server: server} <- JID.decode(jid),
         k when not is_nil(k) <- kind_of(server) do
      %__MODULE__{user: user, kind: k, device: device_of(jid)}
    else
      _ -> nil
    end
  end

  @doc "Coerce a string-or-`Address` to an `Address` (used at the API boundary)."
  @spec coerce(String.t() | t()) :: t()
  def coerce(%__MODULE__{} = a), do: a
  def coerce(jid) when is_binary(jid), do: parse(jid) || raise(ArgumentError, "bad jid: #{jid}")

  @doc "Render an `Address` back to its wire jid string (via `JID.encode/1`)."
  @spec to_jid(t()) :: String.t()
  def to_jid(%__MODULE__{user: user, kind: kind, device: device}) do
    JID.encode(%{user: user, server: Map.fetch!(@server, kind), device: device})
  end

  @doc "Coerce a string-or-`Address` to a wire jid string (boundary → wire)."
  @spec to_wire(String.t() | t()) :: String.t()
  def to_wire(%__MODULE__{} = a), do: to_jid(a)
  def to_wire(jid) when is_binary(jid), do: jid

  @doc "The account-level address (device stripped)."
  @spec normalize(t()) :: t()
  def normalize(%__MODULE__{} = a), do: %{a | device: nil}

  @doc "Whether two addresses name the same account (same user+kind, ignoring device)."
  @spec same_account?(t(), t()) :: boolean()
  def same_account?(%__MODULE__{user: u, kind: k}, %__MODULE__{user: u, kind: k}), do: true
  def same_account?(_a, _b), do: false

  @spec is_pn?(t()) :: boolean()
  def is_pn?(%__MODULE__{kind: :pn}), do: true
  def is_pn?(_), do: false

  @spec is_lid?(t()) :: boolean()
  def is_lid?(%__MODULE__{kind: :lid}), do: true
  def is_lid?(_), do: false

  @spec is_group?(t()) :: boolean()
  def is_group?(%__MODULE__{kind: :group}), do: true
  def is_group?(_), do: false

  # --- internals ---

  defp kind_of("s.whatsapp.net"), do: :pn
  defp kind_of("c.us"), do: :pn
  defp kind_of("lid"), do: :lid
  defp kind_of("g.us"), do: :group
  defp kind_of(_), do: nil

  # The user part of a bare id or full jid (strip @server and any device).
  defp user_of(value) do
    value
    |> String.split("@", parts: 2)
    |> hd()
    |> String.split(":", parts: 2)
    |> hd()
  end

  defp device_of(jid) do
    case JID.decode(jid) do
      %{device: d} -> d
      _ -> nil
    end
  end
end
