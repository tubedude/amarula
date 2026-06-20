defmodule Amarula.Contacts do
  @moduledoc """
  Contact discovery via USync. The consumer-facing half of Baileys' `onWhatsApp`
  / `fetchStatus`.

  Both functions build a single USync `iq` (see `Amarula.Protocol.USync`), send it
  through the connection's generic IQ primitive (`Amarula.Connection.query_iq/3`),
  and turn the reply into friendly maps carrying `Amarula.Address` values — never
  raw jid strings, matching `Amarula.Msg`/`Amarula.Group`.

  Call them on this module: `on_whatsapp/2`, `fetch_status/2`, `resolve_lid/2`.
  """

  alias Amarula.Address
  alias Amarula.Connection
  alias Amarula.Protocol.Signal.LidMappingFileStore
  alias Amarula.Protocol.USync

  @type conn :: GenServer.server()

  @typedoc "One `on_whatsapp/2` result: the resolved address and whether it's on WhatsApp."
  @type presence :: %{address: Address.t() | nil, exists: boolean()}

  @typedoc "One `resolve_lid/2` result: the contact's LID and PN addresses."
  @type lid_pair :: %{lid: Address.t(), pn: Address.t()}

  @typedoc "One `fetch_status/2` result: the address, its status/bio text, and when it was set."
  @type status :: %{
          address: Address.t() | nil,
          status: String.t() | nil,
          set_at: DateTime.t() | nil
        }

  @doc """
  Check which of the given phone numbers are on WhatsApp.

  `phones` are bare numbers or `+`-prefixed (e.g. `"15551234567"`); each is sent
  as a USync `contact` lookup. Returns one result per number with the resolved
  `Amarula.Address` and an `exists` flag.

      Amarula.Contacts.on_whatsapp(conn, ["15551234567"])
      #=> {:ok, [%{address: %Amarula.Address{...}, exists: true}]}
  """
  @spec on_whatsapp(conn(), [String.t()] | String.t()) :: {:ok, [presence()]} | {:error, term()}
  def on_whatsapp(conn, phones) do
    phones = List.wrap(phones)

    query =
      USync.new()
      |> USync.with_context("interactive")
      |> USync.with_mode("query")
      |> USync.with_protocol(:contact)

    query = Enum.reduce(phones, query, fn phone, q -> USync.with_user(q, %{phone: phone}) end)

    with {:ok, entries} <- run(conn, query) do
      {:ok, Enum.map(entries, &to_presence/1)}
    end
  end

  @doc """
  Fetch the status/bio text of the given users.

  `jids` are wire jid strings or `Amarula.Address` values. Returns one result per
  user with the status text (`nil` when not visible to you, `""` when explicitly
  empty) and the time it was set.
  """
  @spec fetch_status(conn(), [String.t() | Address.t()] | String.t() | Address.t()) ::
          {:ok, [status()]} | {:error, term()}
  def fetch_status(conn, jids) do
    jids = jids |> List.wrap() |> Enum.map(&Address.to_jid!/1)

    query =
      USync.new()
      |> USync.with_context("interactive")
      |> USync.with_mode("query")
      |> USync.with_protocol(:status)

    query = Enum.reduce(jids, query, fn jid, q -> USync.with_user(q, %{id: jid}) end)

    with {:ok, entries} <- run(conn, query) do
      {:ok, Enum.map(entries, &to_status/1)}
    end
  end

  @doc """
  Resolve each phone number to its privacy **LID** (`<n>@lid`) and persist the
  LID↔PN mapping, so the LID/PN mapping (and the Signal addressing the send
  pipeline uses) resolve that contact afterwards.

  `on_whatsapp/2` returns only the PN, so it can't establish a mapping; this runs
  a `:lid`+`:contact` USync (the only query that returns the pairing) and feeds the
  result into the same mapping store Amarula auto-populates from group metadata and
  the send pipeline. Returns one entry per number that resolved to a LID; numbers
  not on WhatsApp (no LID in the reply) are omitted.

      Amarula.Contacts.resolve_lid(conn, ["15551234567"])
      #=> {:ok, [%{lid: %Amarula.Address{kind: :lid, ...},
      #           pn: %Amarula.Address{kind: :pn, ...}}]}
  """
  @doc """
  Look up a contact's **PN** from their **LID** in the local mapping store — a
  cheap read, no server query. Returns an `Amarula.Address` (`:pn`) or `nil` when
  the mapping isn't known yet.

  Amarula auto-populates this store from group metadata, the send pipeline, and
  `resolve_lid/2`. So after a `:messages_upsert` from a group member you can map
  their LID back to a PN without hitting WhatsApp — call `resolve_lid/2` first if
  the mapping is missing.

      Amarula.Contacts.pn_for_lid(conn, "12345@lid")
      #=> %Amarula.Address{kind: :pn, ...} | nil
  """
  @spec pn_for_lid(conn(), String.t() | Address.t()) :: Address.t() | nil
  def pn_for_lid(conn, lid) do
    # The store holds bare user strings; the result is a PN user → wrap as :pn.
    conn
    |> Connection.get_conn()
    |> LidMappingFileStore.pn_for_lid(Address.to_jid!(lid))
    |> maybe_address(&Address.pn/1)
  end

  @doc """
  Look up a contact's **LID** from their **PN** in the local mapping store — the
  inverse of `pn_for_lid/2`. A cheap read; `nil` when unmapped.
  """
  @spec lid_for_pn(conn(), String.t() | Address.t()) :: Address.t() | nil
  def lid_for_pn(conn, pn) do
    conn
    |> Connection.get_conn()
    |> LidMappingFileStore.lid_for_pn(Address.to_jid!(pn))
    |> maybe_address(&Address.lid/1)
  end

  defp maybe_address(nil, _kind), do: nil
  defp maybe_address(user, kind) when is_binary(user), do: kind.(user)

  @spec resolve_lid(conn(), [String.t()] | String.t()) :: {:ok, [lid_pair()]} | {:error, term()}
  def resolve_lid(conn, phones) do
    phones = List.wrap(phones)

    query =
      USync.new()
      |> USync.with_context("interactive")
      |> USync.with_mode("query")
      |> USync.with_protocol(:lid)
      |> USync.with_protocol(:contact)

    query = Enum.reduce(phones, query, fn phone, q -> USync.with_user(q, %{phone: phone}) end)

    with {:ok, entries} <- run(conn, query) do
      pairs = entries |> Enum.map(&entry_lid_pn/1) |> Enum.reject(&is_nil/1)
      # store_mappings keys by %Conn{} (the Storage scope), not the pid query_iq
      # uses — fetch it so the consumer never has to juggle the two.
      LidMappingFileStore.store_mappings(Connection.get_conn(conn), pairs)

      {:ok,
       Enum.map(pairs, fn {lid, pn} -> %{lid: Address.parse(lid), pn: Address.parse(pn)} end)}
    end
  end

  # An entry pairs the PN (`:id`, from the :contact protocol) with the LID (the
  # "lid" wire tag, from the :lid protocol). Both must be present to map.
  defp entry_lid_pn(%{:id => pn, "lid" => lid})
       when is_binary(pn) and is_binary(lid) and lid != "",
       do: {lid, pn}

  defp entry_lid_pn(_entry), do: nil

  # Build the IQ, round-trip it via the connection's generic IQ primitive, and
  # parse the reply back into USync result entries.
  defp run(conn, query) do
    with {:ok, iq} <- USync.build_iq(query),
         {:ok, reply} <- Connection.query_iq(conn, iq) do
      case USync.parse_result(query, reply) do
        %{list: list} -> {:ok, list}
        nil -> {:error, :unexpected_reply}
      end
    end
  end

  defp to_presence(entry) do
    %{address: Address.parse(entry[:id]), exists: entry["contact"] == true}
  end

  # The :status protocol parses to %{status: text, set_at: DateTime} under the
  # "status" wire tag; absent when the user has no status visible to us.
  defp to_status(%{"status" => %{status: text, set_at: set_at}} = entry) do
    %{address: Address.parse(entry[:id]), status: text, set_at: set_at}
  end

  defp to_status(entry) do
    %{address: Address.parse(entry[:id]), status: nil, set_at: nil}
  end
end
