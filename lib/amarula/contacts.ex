defmodule Amarula.Contacts do
  @moduledoc """
  Contact discovery via USync. The consumer-facing half of Baileys' `onWhatsApp`
  / `fetchStatus`.

  Both functions build a single USync `iq` (see `Amarula.Protocol.USync`), send it
  through the connection's generic IQ primitive (`Amarula.Connection.query_iq/3`),
  and turn the reply into friendly maps carrying `Amarula.Address` values — never
  raw jid strings, matching `Amarula.Msg`/`Amarula.Group`.

  These are re-exported from the `Amarula` facade (`Amarula.on_whatsapp/2`,
  `Amarula.fetch_status/2`).
  """

  alias Amarula.Address
  alias Amarula.Connection
  alias Amarula.Protocol.USync

  @type conn :: GenServer.server()

  @typedoc "One `on_whatsapp/2` result: the resolved address and whether it's on WhatsApp."
  @type presence :: %{address: Address.t() | nil, exists: boolean()}

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
    jids = jids |> List.wrap() |> Enum.map(&Address.to_wire!/1)

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
