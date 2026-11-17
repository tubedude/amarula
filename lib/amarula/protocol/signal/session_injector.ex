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

  @doc """
  Extract and inject a fresh E2E session from a retry `<receipt>` node carrying a
  `<keys>` bundle (ported from Baileys `extractE2ESessionFromRetryReceipt`).

  Unlike an `encrypt`/`get` IQ reply (`<list><user jid=...>`), a retry receipt
  carries `<registration/>` at the receipt root, `<identity/>`, `<skey/>`, and an
  optional `<key/>` inside `<keys>`, and names the requester via `participant` (or
  `from` for a 1:1 retry). Falls back to `inject/5` if `<list>` is present.
  """
  @spec inject_retry(map(), map(), Amarula.Conn.t(), reference()) :: non_neg_integer()
  def inject_retry(receipt, creds, conn, instance_id) do
    if NodeUtils.get_binary_node_child(receipt, "list") do
      inject(receipt, creds, conn, instance_id, :always)
    else
      store = SessionStore.build(creds)
      jid = NodeUtils.get_attr(receipt, "participant") || NodeUtils.get_attr(receipt, "from")

      with jid when is_binary(jid) <- jid,
           {:ok, device} <- parse_retry_bundle(receipt),
           :ok <- inject_device(jid, device, store, conn, instance_id, :always) do
        1
      else
        _ -> 0
      end
    end
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
        inject_device(jid, device, store, conn, instance_id, mode)
    end
  end

  defp inject_device(jid, device, store, conn, instance_id, mode) do
    # LID-priority: store under the recipient's LID address when mapped, so
    # the send path (which also resolves LID) finds the injected session. The
    # write goes through the record's custodian (the per-record lock).
    addr = LidMappingFileStore.signal_address(conn, jid)

    case SessionCustodian.inject(instance_id, conn, addr, device, store, mode) do
      :ok ->
        Logger.debug("Injected session for #{jid} (#{addr})")
        :ok

      {:skipped, :session_exists} ->
        Logger.debug("Session for #{jid} (#{addr}) already present — inject skipped")
        :skipped

      other ->
        Logger.warning("Inject failed for #{jid} (#{addr}): #{inspect(other)}")
        other
    end
  end

  defp parse_retry_bundle(receipt) do
    with keys when not is_nil(keys) <- NodeUtils.get_binary_node_child(receipt, "keys"),
         true <- valid_bundle_type?(child_content(keys, "type")),
         reg when is_binary(reg) and byte_size(reg) == 4 <-
           child_content(receipt, "registration") || child_content(keys, "registration"),
         identity when is_binary(identity) and byte_size(identity) in [32, 33] <-
           child_content(keys, "identity"),
         {:ok, skey} <- parse_retry_key(NodeUtils.get_binary_node_child(keys, "skey"), true),
         {:ok, pre_key} <-
           parse_optional_retry_key(NodeUtils.get_binary_node_child(keys, "key")) do
      bundle = %{
        registration_id: :binary.decode_unsigned(reg, :big),
        identity_key: wire_key(identity),
        signed_pre_key: skey
      }

      {:ok, if(pre_key, do: Map.put(bundle, :pre_key, pre_key), else: bundle)}
    else
      _ -> :error
    end
  end

  defp valid_bundle_type?(nil), do: true
  defp valid_bundle_type?(<<5>>), do: true
  defp valid_bundle_type?(_), do: false

  defp parse_optional_retry_key(nil), do: {:ok, nil}
  defp parse_optional_retry_key(node), do: parse_retry_key(node, false)

  defp parse_retry_key(nil, _signed), do: :error

  defp parse_retry_key(node, signed) do
    id = child_content(node, "id")
    val = child_content(node, "value")
    sig = child_content(node, "signature")

    cond do
      not is_binary(id) or byte_size(id) == 0 ->
        :error

      not is_binary(val) or byte_size(val) not in [32, 33] ->
        :error

      signed and not is_binary(sig) ->
        :error

      true ->
        base = %{key_id: :binary.decode_unsigned(id, :big), public: wire_key(val)}
        {:ok, if(signed, do: Map.put(base, :signature, sig), else: base)}
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
