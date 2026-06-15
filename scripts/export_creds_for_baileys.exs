#!/usr/bin/env elixir

# Script to export Amarula credentials to Baileys format
# Usage: elixir scripts/export_creds_for_baileys.exs [amarula_auth_folder] [baileys_auth_folder]
#
# This script reads Amarula credentials and creates a Baileys-compatible auth state.
# The key requirement for handshake comparison is the same `noiseKey` (ephemeral key pair).

Mix.install([
  {:jason, "~> 1.4"}
])

require Logger

# Convert Elixir binary to Baileys Buffer format (base64 in JSON)
defmodule CredConverter do
  def binary_to_baileys_buffer(binary) when is_binary(binary) do
    %{
      "type" => "Buffer",
      "data" => Base.encode64(binary)
    }
  end

  def key_pair_to_baileys(key_pair) when is_map(key_pair) do
    %{
      "private" => binary_to_baileys_buffer(key_pair.private),
      "public" => binary_to_baileys_buffer(key_pair.public)
    }
  end

  def create_baileys_creds(amarula_creds) do
    %{
      "noiseKey" => key_pair_to_baileys(amarula_creds.noise_key),
      "signedIdentityKey" => key_pair_to_baileys(amarula_creds.signed_identity_key),
      "signedPreKey" => %{
        "keyId" => amarula_creds.signed_pre_key.key_id,
        "keyPair" => key_pair_to_baileys(amarula_creds.signed_pre_key.key_pair),
        "signature" => binary_to_baileys_buffer(amarula_creds.signed_pre_key.signature)
      },
      "registrationId" => amarula_creds.registration_id,
      "advSecretKey" => amarula_creds.adv_secret_key,
      "me" => nil,
      "account" => nil,
      "signalIdentities" => [],
      "platform" => amarula_creds.platform,
      "pairingEphemeralKeyPair" => key_pair_to_baileys(
        # Generate a pairing key if not present
        amarula_creds[:pairing_ephemeral_key_pair] ||
        Amarula.Protocol.Crypto.Crypto.generate_key_pair()
      ),
      "registered" => false,
      "pairingCode" => nil,
      "lastPropHash" => nil,
      "routingInfo" => nil,
      "additionalData" => nil,
      "processedHistoryMessages" => [],
      "nextPreKeyId" => 1,
      "firstUnuploadedPreKeyId" => 1,
      "accountSyncCounter" => 0,
      "accountSettings" => %{
        "unarchiveChats" => false
      }
    }
  end
end

# Main execution
[amarula_auth_folder, baileys_auth_folder] = System.argv()

if not amarula_auth_folder or not baileys_auth_folder do
  IO.puts("""
  Usage: elixir scripts/export_creds_for_baileys.exs <amarula_auth_folder> <baileys_auth_folder>

  Example:
    elixir scripts/export_creds_for_baileys.exs ./amarula_auth ./baileys_auth

  This will:
  1. Read Amarula credentials from amarula_auth_folder
  2. Convert them to Baileys format
  3. Write to baileys_auth_folder/creds.json

  Note: For handshake comparison, the critical value is the 'noiseKey' which must match exactly.
  """)
  System.halt(1)
end

# Create output directory
File.mkdir_p!(baileys_auth_folder)

# Try to read Amarula credentials
# Note: Amarula may not persist credentials yet, so we'll create a script that can be modified
# to extract credentials from a running process or from logs

IO.puts("""
⚠️  NOTE: Amarula may not persist credentials to disk by default.

If credentials are not found in #{amarula_auth_folder}, you can:
1. Modify connection_demo.ex to export credentials before connecting
2. Or extract noiseKey from logs after running Amarula

For now, this script creates a template. You'll need to manually extract the noiseKey from Amarula logs.
""")

# For now, we'll create a helper function to extract credentials from logs
IO.puts("""
To extract credentials from Amarula:

1. Run Amarula and capture the noise key from logs (look for 'noise_key' in debug output)
2. Or modify connection_demo.ex to export credentials before connecting:

```elixir
# In connection_demo.ex, before connecting:
case Amarula.Protocol.Socket.get_connection_state(socket_pid) do
  {:ok, state} ->
    # Export credentials
    creds = state.auth_creds  # or however you access them
    json = Jason.encode!(CredConverter.create_baileys_creds(creds))
    File.write!("creds.json", json)
end
```

Alternatively, you can manually create creds.json with the noiseKey extracted from logs:

```json
{
  "noiseKey": {
    "private": {"type": "Buffer", "data": "<base64>"},
    "public": {"type": "Buffer", "data": "<base64>"}
  },
  ...
}
```

The critical values for handshake comparison:
- noiseKey.private (32 bytes, base64)
- noiseKey.public (32 bytes, base64)

These determine the encrypted noise key in ClientFinish.
""")

# Create a template creds.json
template_creds = %{
  "noiseKey" => %{
    "private" => %{"type" => "Buffer", "data" => "REPLACE_WITH_AMARULA_NOISE_KEY_PRIVATE_BASE64"},
    "public" => %{"type" => "Buffer", "data" => "REPLACE_WITH_AMARULA_NOISE_KEY_PUBLIC_BASE64"}
  },
  "signedIdentityKey" => %{
    "private" => %{"type" => "Buffer", "data" => "REPLACE_IF_AVAILABLE"},
    "public" => %{"type" => "Buffer", "data" => "REPLACE_IF_AVAILABLE"}
  },
  "signedPreKey" => %{
    "keyId" => 1,
    "keyPair" => %{
      "private" => %{"type" => "Buffer", "data" => "REPLACE_IF_AVAILABLE"},
      "public" => %{"type" => "Buffer", "data" => "REPLACE_IF_AVAILABLE"}
    },
    "signature" => %{"type" => "Buffer", "data" => "REPLACE_IF_AVAILABLE"}
  },
  "registrationId" => 0,
  "advSecretKey" => "REPLACE_IF_AVAILABLE",
  "pairingEphemeralKeyPair" => %{
    "private" => %{"type" => "Buffer", "data" => "REPLACE_IF_AVAILABLE"},
    "public" => %{"type" => "Buffer", "data" => "REPLACE_IF_AVAILABLE"}
  },
  "registered" => false,
  "me" => nil,
  "account" => nil,
  "signalIdentities" => [],
  "platform" => nil,
  "pairingCode" => nil,
  "lastPropHash" => nil,
  "routingInfo" => nil,
  "additionalData" => nil,
  "processedHistoryMessages" => [],
  "nextPreKeyId" => 1,
  "firstUnuploadedPreKeyId" => 1,
  "accountSyncCounter" => 0,
  "accountSettings" => %{
    "unarchiveChats" => false
  }
}

output_path = Path.join(baileys_auth_folder, "creds.json")
File.write!(output_path, Jason.encode!(template_creds, pretty: true))

IO.puts("""
✅ Created template creds.json at: #{output_path}

⚠️  IMPORTANT: You must replace the noiseKey values with the actual values from Amarula.

To extract noiseKey from Amarula logs:
1. Run: iex -S mix
2. Run: Amarula.Examples.ConnectionDemo.demo_connection()
3. Look in logs for the noise_key (or modify connection_demo.ex to log it)
4. Convert the hex/base64 values to Baileys Buffer format
""")
