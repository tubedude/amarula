defmodule Amarula.AddressFixtures do
  @moduledoc """
  Canonical **hostile** address shapes — the device/agent/LID/hosted/broadcast/
  newsletter forms real WhatsApp traffic carries but hand-rolled fixtures tend to
  omit. That omission is the blind spot behind #41 and #46–#51: a bug that only
  fires on a device (`user:29@…`) or agent (`user_1@…`) suffix, or a non-PN server,
  sails through a suite that only ever uses a clean `"<n>@s.whatsapp.net"`.

  Reference these instead of inlining literals, and sweep the lists to prove a
  boundary handles every shape (see `test/address_shapes_test.exs`).

    * `resolvable/0` — shapes `Amarula.Address` understands. Each entry is
      `{label, jid, kind, account_jid}`, where `account_jid` is the account-level
      form a `MessageKey`/reply handle must carry (device + agent stripped, per
      `JID.jid_normalized_user/1`).
    * `unresolvable/0` — the servers `Address.parse/1` deliberately returns `nil`
      for today (#50). Kept separate so a sweep can assert the current contract
      without pretending they're addressable identities.
  """

  @pn "5511888888888"
  @lid "147451226890315"
  @group "120363000000000000"

  @resolvable [
    {"clean PN", "#{@pn}@s.whatsapp.net", :pn, "#{@pn}@s.whatsapp.net"},
    {"PN + device", "#{@pn}:29@s.whatsapp.net", :pn, "#{@pn}@s.whatsapp.net"},
    {"PN + agent", "#{@pn}_1@s.whatsapp.net", :pn, "#{@pn}@s.whatsapp.net"},
    {"c.us PN", "#{@pn}@c.us", :pn, "#{@pn}@s.whatsapp.net"},
    {"clean LID", "#{@lid}@lid", :lid, "#{@lid}@lid"},
    {"LID + device", "#{@lid}:12@lid", :lid, "#{@lid}@lid"},
    {"group", "#{@group}@g.us", :group, "#{@group}@g.us"},
    {"hosted PN device", "#{@pn}:99@hosted", :pn, "#{@pn}@hosted"},
    {"hosted LID device", "#{@lid}:99@hosted.lid", :lid, "#{@lid}@hosted.lid"}
  ]

  @unresolvable [
    {"broadcast", "status@broadcast"},
    {"newsletter", "#{@group}@newsletter"}
  ]

  @doc "Address shapes `Amarula.Address` resolves — `{label, jid, kind, account_jid}`."
  def resolvable, do: @resolvable

  @doc "Server shapes `Address.parse/1` returns nil for today (#50) — `{label, jid}`."
  def unresolvable, do: @unresolvable

  # Named accessors for the shapes tests reach for most.
  def pn, do: "#{@pn}@s.whatsapp.net"
  def pn_with_device, do: "#{@pn}:29@s.whatsapp.net"
  def pn_with_agent, do: "#{@pn}_1@s.whatsapp.net"
  def lid, do: "#{@lid}@lid"
  def lid_with_device, do: "#{@lid}:12@lid"
  def group, do: "#{@group}@g.us"
end
