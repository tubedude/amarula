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
    * `:none`  — the **empty** address (`empty/0`): "no identity". A total value for
      "we don't have one yet" (e.g. `Amarula.own_address/1` before login), so callers
      never have to nil-guard. It names nothing: every `is_*?` is false, it is never
      `same_account?` with anything, and rendering it to a wire jid is only allowed
      via the bang (`to_jid!/1` raises; `to_jid/1` returns `{:error, :no_jid}`).

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

  @type kind :: :pn | :lid | :group | :none
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

  @doc "The empty address — \"no identity\". A total stand-in (see the `:none` kind)."
  @spec empty() :: t()
  def empty, do: %__MODULE__{user: "", kind: :none, device: nil}

  @doc """
  Parse a wire jid into an `Address` (via `JID.decode/1`). Accepts a string or an
  already-parsed `Address` (passed through), so it's safe to call at the API boundary
  on either. Returns `nil` for an unparseable/unknown-server string. Use `parse!/1`
  when a bad jid should raise instead.
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

  @doc "Like `parse/1` but raises `ArgumentError` on an unparseable jid (never `nil`)."
  @spec parse!(String.t() | t()) :: t()
  def parse!(jid), do: parse(jid) || raise(ArgumentError, "bad jid: #{inspect(jid)}")

  @doc """
  Render an `Address` to its wire jid string (via `JID.encode/1`). Total: the empty
  address (`:none`) has no wire form and returns `{:error, :no_jid}`. Use `to_jid!/1`
  when you have a real address and want the bare string.
  """
  @spec to_jid(t()) :: {:ok, String.t()} | {:error, :no_jid}
  def to_jid(%__MODULE__{kind: :none}), do: {:error, :no_jid}

  def to_jid(%__MODULE__{user: user, kind: kind, device: device}) do
    {:ok, JID.encode(%{user: user, server: Map.fetch!(@server, kind), device: device})}
  end

  @doc "Like `to_jid/1` but returns the bare string, raising on the empty address."
  @spec to_jid!(t()) :: String.t()
  def to_jid!(%__MODULE__{} = addr) do
    case to_jid(addr) do
      {:ok, jid} -> jid
      {:error, :no_jid} -> raise ArgumentError, "address has no wire jid: #{inspect(addr)}"
    end
  end

  @doc """
  Coerce a string-or-`Address` to a wire jid string (boundary → wire). Total; mirrors
  `to_jid/1` (a binary passes through as `{:ok, binary}`). Use `to_wire!/1` for the
  bare string.
  """
  @spec to_wire(String.t() | t()) :: {:ok, String.t()} | {:error, :no_jid}
  def to_wire(%__MODULE__{} = a), do: to_jid(a)
  def to_wire(jid) when is_binary(jid), do: {:ok, jid}

  @doc "Like `to_wire/1` but returns the bare string, raising on the empty address."
  @spec to_wire!(String.t() | t()) :: String.t()
  def to_wire!(%__MODULE__{} = a), do: to_jid!(a)
  def to_wire!(jid) when is_binary(jid), do: jid

  @doc "The account-level address (device stripped)."
  @spec normalize(t()) :: t()
  def normalize(%__MODULE__{} = a), do: %{a | device: nil}

  @doc """
  Whether two addresses name the same account (same user+kind, ignoring device). The
  empty address (`:none`) names nothing, so it is never the same account as anything —
  including another empty.
  """
  @spec same_account?(t(), t()) :: boolean()
  def same_account?(%__MODULE__{kind: :none}, _b), do: false
  def same_account?(_a, %__MODULE__{kind: :none}), do: false
  def same_account?(%__MODULE__{user: u, kind: k}, %__MODULE__{user: u, kind: k}), do: true
  def same_account?(_a, _b), do: false

  @spec pn?(t()) :: boolean()
  def pn?(%__MODULE__{kind: :pn}), do: true
  def pn?(_), do: false

  @spec lid?(t()) :: boolean()
  def lid?(%__MODULE__{kind: :lid}), do: true
  def lid?(_), do: false

  @spec group?(t()) :: boolean()
  def group?(%__MODULE__{kind: :group}), do: true
  def group?(_), do: false

  @doc "Whether this is the empty address (`empty/0`, kind `:none`)."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{kind: :none}), do: true
  def empty?(_), do: false

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
