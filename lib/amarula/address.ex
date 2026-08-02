defmodule Amarula.Address do
  @moduledoc """
  A WhatsApp address — the consumer-facing way to name *who/what* a message is
  for or from. A friendly value you can build, inspect, and pass to sends, instead
  of juggling raw `"user@server"` jid strings.

  Four kinds, distinguished by `:kind`:

    * `:pn`    — a phone-number identity (`<number>@s.whatsapp.net`).
    * `:lid`   — a privacy "Linked ID" (`<id>@lid`). WhatsApp's wire-preferred
      identity; the same person has both a PN and a LID.
    * `:group` — a group chat (`<id>@g.us`). A *container* of participants, not a
      person; its members are fetched separately (group metadata), not stored here.
    * `:none`  — the **empty** address (`empty/0`): "no identity". A stand-in for
      "we don't have one yet" (e.g. `Amarula.own_address/1` before login) — returned
      instead of `nil`, so you never have to nil-check. It names nothing: every
      `is_*?` is false, it is never
      `same_account?` with anything, and it has no jid string (`to_jid!/1` raises;
      `to_jid/1` returns `{:error, :no_jid}`).

  `:device` is the device number (`nil` = account-level / primary). An address
  with `device: nil` names the whole account; with a device it names one client.

  ## Parsed-only

  An `Address` is a **pure value** — only what's deterministic from the string.
  It does NOT carry resolved data (a PN's LID, a group's participants, device
  lists): those need connection state, are lazy, and can change, so they stay
  internal. Don't expect `Address.pn(...)` to "know" its LID.

  ## Strings in, strings out

  `parse/1` turns a jid string into an `Address`; `to_jid/1` turns an `Address`
  back into its jid string (both via `Amarula.Protocol.Binary.JID`). The public
  API and events speak `Address`; under the hood the protocol speaks jid strings.
  The public API also accepts a raw string and parses it for you, so
  `Amarula.send_text(conn, "5511...@s.whatsapp.net", ...)` and
  `Amarula.send_text(conn, Address.pn("5511..."), ...)` both work.
  """

  alias Amarula.Protocol.Binary.JID

  @type kind :: :pn | :lid | :group | :none | :unsupported
  @type t :: %__MODULE__{
          user: String.t(),
          kind: kind(),
          device: non_neg_integer() | nil,
          server: String.t() | nil
        }

  @enforce_keys [:user, :kind]
  # `server` is the raw server string, and is set ONLY for `:unsupported` — for the
  # known kinds the server is implied by `kind` (see `@server` below), so carrying it
  # twice would just be a second source of truth to keep in sync.
  defstruct [:user, :kind, :device, :server]

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

  @doc "The empty address — \"no identity\". Returned instead of `nil` (see the `:none` kind)."
  @spec empty() :: t()
  def empty, do: %__MODULE__{user: "", kind: :none, device: nil}

  @doc """
  Parse a jid string into an `Address` (via `JID.decode/1`). An already-parsed
  `Address` passes through unchanged, and `nil` passes through as `nil` — so it's
  safe to call on an optional `String.t() | nil` field without wrapping.

  `nil` means **"not a jid"** — an unparseable string with no server part. A jid
  whose server we do not model yet (`status@broadcast`, `@newsletter`, `@hosted`)
  is NOT nil: it parses to `kind: :unsupported` carrying the raw `server`, so it
  can be inspected, matched and logged like any other address. It cannot be
  addressed — `to_jid/1` refuses it (see `unsupported?/1`).

      iex> Amarula.Address.parse("status@broadcast")
      %Amarula.Address{user: "status", kind: :unsupported, device: nil, server: "broadcast"}

      iex> Amarula.Address.parse("not-a-jid")
      nil
  """
  @spec parse(String.t() | t() | nil) :: t() | nil
  def parse(nil), do: nil
  def parse(%__MODULE__{} = address), do: address

  def parse(jid) when is_binary(jid) do
    case JID.decode(jid) do
      %{user: user, server: server} = decoded ->
        device = Map.get(decoded, :device)

        case kind_of(server) do
          nil -> %__MODULE__{user: user, kind: :unsupported, device: device, server: server}
          k -> %__MODULE__{user: user, kind: k, device: device}
        end

      _ ->
        nil
    end
  end

  @doc "Like `parse/1` but raises `ArgumentError` on an unparseable jid (never `nil`)."
  @spec parse!(String.t() | t()) :: t()
  def parse!(jid), do: parse(jid) || raise(ArgumentError, "bad jid: #{inspect(jid)}")

  @doc """
  Get the jid string for an `Address` (or pass a jid string straight through).

  This is the function to use when you have a `msg.channel`/`from`/`to` (an
  `Address`) and need the `"user@server"` string WhatsApp uses — e.g. to build a
  `MessageKey`. A plain string passes through unchanged, so you can hand it
  either form.

  Returns `{:ok, jid}`, or `{:error, :no_jid}` for the empty address (`:none`),
  which has no jid. Use `to_jid!/1` for the bare string.

      iex> Amarula.Address.to_jid(Amarula.Address.pn("5511999999999"))
      {:ok, "5511999999999@s.whatsapp.net"}
  """
  @spec to_jid(String.t() | t() | nil) ::
          {:ok, String.t()} | {:error, :no_jid | {:unsupported, String.t()}}
  def to_jid(%__MODULE__{kind: :none}), do: {:error, :no_jid}

  # Refused DELIBERATELY, even though `user` + `server` would rebuild the string
  # perfectly. Handing back `"status@broadcast"` would make a send to it succeed —
  # and sending to `status@broadcast` is how one POSTS a status. An echo bot
  # replying to a friend's story would publish a story to all its contacts. A
  # crash is bad; silently broadcasting is worse. Refuse until the kind is
  # genuinely implemented (#50).
  def to_jid(%__MODULE__{kind: :unsupported, server: server}),
    do: {:error, {:unsupported, server}}

  # `parse/1` yields nil only for a string that is not a jid at all.
  def to_jid(nil), do: {:error, :no_jid}

  def to_jid(%__MODULE__{user: user, kind: kind, device: device}) do
    {:ok, JID.encode(%{user: user, server: Map.fetch!(@server, kind), device: device})}
  end

  def to_jid(jid) when is_binary(jid), do: {:ok, jid}

  @doc "Like `to_jid/1` but returns the bare string, raising on the empty address."
  @spec to_jid!(String.t() | t()) :: String.t()
  def to_jid!(jid) when is_binary(jid), do: jid

  # Deliberately still raises — `!` promises a bare string. But it names the reason
  # rather than surfacing a bare FunctionClauseError. `nil` reaching here means a
  # string that is not a jid at all (no server part); an unmodelled *kind* is a
  # separate, more likely case handled by the `:unsupported` clause below.
  def to_jid!(nil) do
    raise ArgumentError,
          "address is nil: `Amarula.Address.parse/1` returns nil for a string that is not a " <>
            "jid (no \"@server\" part). Match on nil before calling to_jid!/1."
  end

  def to_jid!(%__MODULE__{} = addr) do
    case to_jid(addr) do
      {:ok, jid} ->
        jid

      {:error, :no_jid} ->
        raise ArgumentError, "address has no jid: #{inspect(addr)}"

      {:error, {:unsupported, server}} ->
        raise ArgumentError,
              "cannot address a #{inspect(server)} jid: Amarula does not model this chat kind " <>
                "yet, so it has no safe destination. Match `Amarula.Address.unsupported?/1` first."
    end
  end

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

  # Two unsupported addresses match only if the SERVER matches too — `kind` alone
  # is `:unsupported` for every unmodelled server, so the generic user+kind clause
  # below would equate `5@hosted` with `5@newsletter`.
  def same_account?(
        %__MODULE__{kind: :unsupported, user: u, server: s},
        %__MODULE__{kind: :unsupported, user: u, server: s}
      ),
      do: true

  def same_account?(%__MODULE__{kind: :unsupported}, _b), do: false
  def same_account?(_a, %__MODULE__{kind: :unsupported}), do: false
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

  @doc """
  Whether this is a real jid whose chat kind Amarula does not model yet
  (`status@broadcast`, `@newsletter`, `@hosted`, …).

  Such an address carries its raw `server` and can be inspected and compared, but
  has no safe destination — `to_jid/1` returns `{:error, {:unsupported, server}}`
  and sends to it are refused. Match this before addressing an address that came
  off the wire.
  """
  @spec unsupported?(t()) :: boolean()
  def unsupported?(%__MODULE__{kind: :unsupported}), do: true
  def unsupported?(_), do: false

  # --- internals ---

  defp kind_of("s.whatsapp.net"), do: :pn
  defp kind_of("c.us"), do: :pn
  defp kind_of("lid"), do: :lid
  defp kind_of("g.us"), do: :group
  defp kind_of(_), do: nil

  # The user part of a bare id or full jid: strip @server, then the `:device` and
  # `_agent` segments, in that order.
  #
  # A jid encodes as `user_agent:device@server` (`JID.encode/1`), so the split order
  # mirrors `JID.decode_user_part/2` → `decode_user_agent/3` — which is the point:
  # `parse/1` goes through `JID.decode/1` and drops the agent, so a `user_of/1` that
  # kept it made `pn/1` and `parse/1` disagree on the SAME jid string, leaving
  # `same_account?/2` false for one account (#51). `same_account?/2` backs
  # `own_account?/2`, `own_chat?/2` and `own_sender?/3`, so the two constructors have
  # to agree.
  defp user_of(value) do
    value
    |> String.split("@", parts: 2)
    |> hd()
    |> String.split(":", parts: 2)
    |> hd()
    |> String.split("_", parts: 2)
    |> hd()
  end
end
