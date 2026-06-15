# Script to capture and log handshake messages for comparison with Baileys
# Run this alongside Baileys to capture identical handshake messages

Mix.install([
  {:amarula, path: "."}
])

# Configure logger to capture all messages
Logger.configure(level: :debug)

# Add hex logging to capture binary messages
defmodule HandshakeCapture do
  require Logger

  def log_message(direction, message_name, data) when is_binary(data) do
    hex = Base.encode16(data, case: :lower)
    base64 = Base.encode64(data)
    size = byte_size(data)

    Logger.info("""
    === #{direction} #{message_name} ===
    Size: #{size} bytes
    Hex: #{hex}
    Base64: #{base64}
    First 32 bytes hex: #{Base.encode16(:binary.part(data, 0, min(32, size)), case: :lower)}
    """)

    # Also save to file for comparison
    filename = "handshake_#{direction}_#{message_name}_#{:erlang.system_time(:second)}.bin"
    File.write!(filename, data)
    Logger.info("Saved to: #{filename}")
  end
end

# Now you can instrument the connection to capture messages
# This would need to be integrated into the actual connection code
