defmodule Amarula.Protocol.Signal.SessionInjector do
  @moduledoc """
  Parse an `encrypt`/`get` prekey-bundle IQ result and build outgoing sessions,
  ported from Baileys `parseAndInjectE2ESessions` (`src/Utils/signal.ts`) +
  `repository.injectE2ESession`.

  The IQ result looks like:

      <iq type=result><list>
        <user jid=...>
          <registration/>           (4-byte big-endian)
          <identity/>               (32-byte raw pubkey)
          <skey><id/><value/><signature/></skey>   (signed prekey)
          <key><id/><value/></key>                 (one-time prekey, optional)
          <error/>                  (present if no bundle for this device)
        </user>
        ...
      </list></iq>

  For each error-free `<user>` we run `SessionBuilder.init_outgoing` against the
  bundle and persist the session under the user's signal address.
  """

  require Logger

  alias Amarula.Protocol.Binary.NodeUtils
  alias Amarula.Protocol.Signal.{LidMappingFileStore, SessionCustodian, SessionStore}

  @doc """
  Inject every session in the IQ `result` node. `creds` supplies our identity
  (via `SessionStore.build/1`); `conn` (`Amarula.Conn`) scopes where
  sessions persist.

  Returns the number of sessions injected.
  """
  @spec inject(map(), map(), Amarula.Conn.t(), reference(), :always | :if_absent) ::
          non_neg_integer()
  def inject(result, creds, conn, instance_id, mode) do
    store = SessionStore.build(creds)
    list = NodeUtils.get_binary_node_child(result, "list")
    users = if list, do: NodeUtils.get_binary_node_children(list, "user"), else: []

    Enum.reduce(users, 0, fn user, count ->
      case inject_user(user, store, conn, instance_id, mode) do
        :ok -> count + 1
        _ -> count
      end
    end)
  end

  defp inject_user(user, store, conn, instance_id, mode) do
    jid = NodeUtils.get_attr(user, "jid")

    cond do
      NodeUtils.get_binary_node_child(user, "error") != nil ->
        Logger.warning("No prekey bundle for #{jid} — skipping")
        :skip

      is_nil(jid) ->
        :skip

      true ->
        device = parse_bundle(user)
        # LID-priority: store under the recipient's LID address when mapped, so
        # the send path (which also resolves LID) finds the injected session. The
        # write goes through the record's custodian (the per-record lock).
        addr = LidMappingFileStore.signal_address(conn, jid)

        with {:ok, custodian} <- SessionCustodian.for_address(instance_id, conn, addr),
             :ok <- SessionCustodian.inject(custodian, device, store, mode) do
          Logger.debug("Injected session for #{jid} (#{addr})")
          :ok
        else
          {:skipped, :session_exists} ->
            Logger.debug("Session for #{jid} (#{addr}) already present — inject skipped")
            :skipped

          other ->
            Logger.warning("Inject failed for #{jid} (#{addr}): #{inspect(other)}")
            other
        end
    end
  end

  # Build the device bundle map init_outgoing expects from a <user> node.
  defp parse_bundle(user) do
    registration = child_content(user, "registration")
    identity = child_content(user, "identity")
    skey = NodeUtils.get_binary_node_child(user, "skey")
    key = NodeUtils.get_binary_node_child(user, "key")

    bundle = %{
      registration_id: :binary.decode_unsigned(registration, :big),
      identity_key: wire_key(identity),
      signed_pre_key: parse_key(skey, signed: true)
    }

    if key, do: Map.put(bundle, :pre_key, parse_key(key, signed: false)), else: bundle
  end

  defp parse_key(node, signed: signed) do
    base = %{
      key_id: :binary.decode_unsigned(child_content(node, "id"), :big),
      public: wire_key(child_content(node, "value"))
    }

    if signed, do: Map.put(base, :signature, child_content(node, "signature")), else: base
  end

  defp child_content(node, tag) do
    case NodeUtils.get_binary_node_child(node, tag) do
      %{content: content} when is_binary(content) -> content
      _ -> nil
    end
  end

  # generateSignalPubKey: ensure 33-byte 0x05-prefixed wire form.
  defp wire_key(<<5, _::binary-size(32)>> = k), do: k
  defp wire_key(<<k::binary-size(32)>>), do: <<5>> <> k
end
