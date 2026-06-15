defmodule Amarula.Protocol.USync.Devices do
  @moduledoc """
  Turn a parsed USync result into the concrete list of device JIDs to encrypt
  for. Port of Baileys `extractDeviceJids` (`src/Utils/signal.ts`).

  Each USync result entry carries the user's `id` (jid) and a `"devices"` map
  with a `:device_list`. We expand that into one JID per device, applying the
  same three filters Baileys uses:

    1. drop device 0 when `exclude_zero_devices?` is set
    2. drop our own sending device (same user *and* same device)
    3. drop non-zero devices that lack a `key_index` (server rejects them)
  """

  alias Amarula.Protocol.Binary.JID

  @type device_jid :: %{
          user: String.t(),
          device: non_neg_integer(),
          server: String.t(),
          jid: String.t()
        }

  @doc """
  Expand `result_list` (the `:list` from `USync.parse_result/2`) into device JIDs.

  `my_jid` / `my_lid` identify our own account so we can skip our sending
  device. `exclude_zero_devices?` mirrors Baileys' `excludeZeroDevices` flag.
  """
  @spec extract([map()], String.t(), String.t() | nil, boolean()) :: [device_jid()]
  def extract(result_list, my_jid, my_lid, exclude_zero_devices?) do
    %{user: my_user, device: my_device} = decode_self(my_jid)
    my_lid_user = my_lid && Map.get(JID.decode(my_lid) || %{}, :user)

    Enum.flat_map(result_list, fn entry ->
      with %{user: user, server: server} <- JID.decode(entry.id),
           device_list when is_list(device_list) <- device_list(entry) do
        Enum.flat_map(device_list, fn device ->
          expand_device(device, %{
            user: user,
            server: server,
            my_user: my_user,
            my_lid_user: my_lid_user,
            my_device: my_device,
            exclude_zero?: exclude_zero_devices?
          })
        end)
      else
        _ -> []
      end
    end)
  end

  defp expand_device(%{id: device, key_index: key_index}, ctx) do
    if keep_device?(device, key_index, ctx) do
      jid = JID.encode(%{user: ctx.user, server: ctx.server, device: device})
      [%{user: ctx.user, device: device, server: ctx.server, jid: jid}]
    else
      []
    end
  end

  # Three-part filter, matching Baileys' condition exactly.
  defp keep_device?(device, key_index, ctx) do
    not_excluded_zero?(device, ctx.exclude_zero?) and
      not_own_device?(device, ctx) and
      addressable?(device, key_index)
  end

  defp not_excluded_zero?(0, true), do: false
  defp not_excluded_zero?(_device, _exclude?), do: true

  # Either a different user, or — if it is us — a different device than ours.
  defp not_own_device?(device, %{
         user: user,
         my_user: my_user,
         my_lid_user: my_lid_user,
         my_device: my_device
       }) do
    user not in [my_user, my_lid_user] or device != my_device
  end

  defp addressable?(0, _key_index), do: true
  defp addressable?(_device, key_index), do: not is_nil(key_index) and key_index != 0

  defp device_list(%{"devices" => %{device_list: list}}), do: list
  defp device_list(_), do: nil

  # our own jid may or may not carry a device suffix; default to device 0.
  defp decode_self(my_jid) do
    case JID.decode(my_jid) do
      %{user: user} = decoded -> %{user: user, device: Map.get(decoded, :device, 0) || 0}
      _ -> %{user: nil, device: 0}
    end
  end
end
