defmodule Amarula.Protocol.Signal.Group.KeyHelper do
  @moduledoc """
  Key Helper utilities for Signal Protocol group encryption, ported from
  `src/Signal/Group/keyhelper.ts`.

  The sender signing key is a **Curve25519** pair (signed with XEd25519), not
  Ed25519 — same scheme as the identity key. The public key is returned in
  wire form (33 bytes, 0x05-prefixed) to match libsignal's `generateKeyPair`.
  """

  alias Amarula.Protocol.Crypto.Crypto

  @doc """
  Generates a random sender key ID.
  """
  @spec generate_sender_key_id() :: integer()
  def generate_sender_key_id do
    :crypto.strong_rand_bytes(4) |> :binary.decode_unsigned() |> rem(2_147_483_647)
  end

  @doc """
  Generates a random sender key (chain key seed).
  """
  @spec generate_sender_key() :: binary()
  def generate_sender_key do
    :crypto.strong_rand_bytes(32)
  end

  @doc """
  Generates a Curve25519 sender signing key pair.
  Returns `{public, private}` with `public` 0x05-prefixed (33 bytes).
  """
  @spec generate_sender_signing_key() :: {binary(), binary()}
  def generate_sender_signing_key do
    pair = Crypto.generate_key_pair()
    {<<5>> <> pair.public, pair.private}
  end
end
