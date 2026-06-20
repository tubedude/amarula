defmodule Amarula.Connection.GroupOps do
  @moduledoc """
  Pure group-query builders for `Amarula.Connection`.

  Each function builds the `{iq, transform}` pair the group callbacks feed to
  `Connection.send_waiter_iq/4` — the IQ node to send and the fun that turns the
  reply node into the consumer result (`%Amarula.Group{}` / a list of them). No
  socket, no `state`: the IQ correlation + dispatch stay on `Connection`; only the
  request shape and reply parsing live here, testable in isolation.
  """

  alias Amarula.Protocol.Groups.Metadata

  @type transform :: ({:ok, term()} | {:error, term()} -> {:ok, term()} | {:error, term()})

  @doc "Query one group's metadata → `{iq, transform}` yielding `%Amarula.Group{}`."
  @spec metadata(String.t()) :: {term(), transform()}
  def metadata(group_jid) do
    iq = Metadata.query_iq(group_jid)

    transform = fn
      {:ok, node} ->
        with {:ok, meta} <- Metadata.parse(node),
             do: {:ok, Amarula.Group.from_metadata(meta)}

      {:error, node} ->
        {:error, node}
    end

    {iq, transform}
  end

  @doc "Query all joined groups → `{iq, transform}` yielding `[%Amarula.Group{}]`."
  @spec list() :: {term(), transform()}
  def list do
    iq = Metadata.query_all_iq()

    transform = fn
      {:ok, node} ->
        {:ok, metas} = Metadata.parse_all(node)
        {:ok, Enum.map(metas, &Amarula.Group.from_metadata/1)}

      {:error, node} ->
        {:error, node}
    end

    {iq, transform}
  end
end
