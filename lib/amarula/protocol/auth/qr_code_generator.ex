defmodule Amarula.Protocol.Auth.QRCodeGenerator do
  @moduledoc """
  QR Code Generator for WhatsApp authentication.

  This module provides utilities for generating QR codes from authentication data
  and handling QR code formatting and validation.
  """

  @doc """
  Generates a QR code string from authentication components.

  The QR code format is: "ref,noiseKeyB64,identityKeyB64,advSecretKeyB64"
  """
  @spec generate_qr_string(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def generate_qr_string(ref, noise_key_b64, identity_key_b64, adv_secret_key_b64) do
    [ref, noise_key_b64, identity_key_b64, adv_secret_key_b64] |> Enum.join(",")
  end

  @doc """
  Parses a QR code string into its components.

  Returns {:ok, {ref, noise_key_b64, identity_key_b64, adv_secret_key_b64}} on success,
  or {:error, reason} on failure.
  """
  @spec parse_qr_string(String.t()) ::
          {:ok, {String.t(), String.t(), String.t(), String.t()}} | {:error, String.t()}
  def parse_qr_string(qr_string) do
    case String.split(qr_string, ",", parts: 4) do
      [ref, noise_key_b64, identity_key_b64, adv_secret_key_b64] ->
        # Validate that all components are non-empty
        if ref != "" and noise_key_b64 != "" and identity_key_b64 != "" and
             adv_secret_key_b64 != "" do
          {:ok, {ref, noise_key_b64, identity_key_b64, adv_secret_key_b64}}
        else
          {:error, "QR code components cannot be empty"}
        end

      _ ->
        {:error, "Invalid QR code format - expected 4 comma-separated components"}
    end
  end

  @doc """
  Validates a QR code string format.
  """
  @spec validate_qr_string(String.t()) :: :ok | {:error, String.t()}
  def validate_qr_string(qr_string) do
    case parse_qr_string(qr_string) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generates a QR code reference string.

  This creates a unique reference string for QR code generation.
  """
  @spec generate_ref() :: String.t()
  def generate_ref do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end

  @doc """
  Generates multiple QR code references.
  """
  @spec generate_refs(integer()) :: list(String.t())
  def generate_refs(count) when count > 0 do
    Enum.map(1..count, fn _ -> generate_ref() end)
  end

  def generate_refs(0), do: []

  @doc """
  Checks if a QR code has expired based on its generation time.
  """
  @spec is_qr_expired?(integer(), integer()) :: boolean()
  def is_qr_expired?(generation_time, timeout_ms) do
    current_time = System.monotonic_time(:millisecond)
    current_time - generation_time >= timeout_ms
  end

  @doc """
  Formats a QR code for display (e.g., in terminal or UI).
  """
  @spec format_qr_for_display(String.t()) :: String.t()
  def format_qr_for_display(qr_string) do
    """
    ╔══════════════════════════════════════════════════════════════╗
    ║                    WhatsApp QR Code                         ║
    ╠══════════════════════════════════════════════════════════════╣
    ║                                                              ║
    ║  #{String.pad_trailing(qr_string, 60)}  ║
    ║                                                              ║
    ║  Scan this QR code with your phone to connect               ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝
    """
  end

  @doc """
  Extracts the reference from a QR code string.
  """
  @spec extract_ref(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def extract_ref(qr_string) do
    case parse_qr_string(qr_string) do
      {:ok, {ref, _, _, _}} -> {:ok, ref}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Extracts the noise key from a QR code string.
  """
  @spec extract_noise_key(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def extract_noise_key(qr_string) do
    case parse_qr_string(qr_string) do
      {:ok, {_, noise_key_b64, _, _}} -> {:ok, noise_key_b64}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Extracts the identity key from a QR code string.
  """
  @spec extract_identity_key(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def extract_identity_key(qr_string) do
    case parse_qr_string(qr_string) do
      {:ok, {_, _, identity_key_b64, _}} -> {:ok, identity_key_b64}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Extracts the advertisement secret key from a QR code string.
  """
  @spec extract_adv_secret_key(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def extract_adv_secret_key(qr_string) do
    case parse_qr_string(qr_string) do
      {:ok, {_, _, _, adv_secret_key_b64}} -> {:ok, adv_secret_key_b64}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Renders a QR string as ASCII art using the qr_code library.

  Takes a QR string and returns an ASCII representation of the QR code matrix.
  Uses half-height blocks to correct for terminal character aspect ratio.
  """
  @spec render_ascii(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def render_ascii(qr_string) do
    case QRCode.create(qr_string) do
      {:ok, qr_code} ->
        # Convert QR matrix to ASCII using half-height blocks
        # Each terminal line represents 2 QR pixels (top and bottom)
        matrix = qr_code.matrix

        ascii_qr =
          matrix
          |> Enum.chunk_every(2)
          |> Enum.map(fn
            # Two rows - use half blocks
            [top_row, bottom_row] ->
              top_row
              |> Enum.zip(bottom_row)
              |> Enum.map_join("", fn
                # Both pixels filled
                {1, 1} -> "█"
                # Top pixel filled
                {1, 0} -> "▀"
                # Bottom pixel filled
                {0, 1} -> "▄"
                # Both pixels empty
                {0, 0} -> " "
              end)

            # Single row (odd number of rows) - use top half block
            [single_row] ->
              Enum.map_join(single_row, "", fn
                1 -> "▀"
                0 -> " "
              end)
          end)
          |> Enum.join("\n")

        {:ok, ascii_qr}

      {:error, reason} ->
        {:error, "Failed to create QR code: #{reason}"}
    end
  end

  @doc """
  Renders a QR string with pretty terminal formatting including borders and branding.

  Takes a QR string and returns a formatted ASCII QR code suitable for terminal display.
  """
  @spec render_terminal(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def render_terminal(qr_string) do
    case render_ascii(qr_string) do
      {:ok, ascii_qr} ->
        # Split ASCII QR into lines
        qr_lines = String.split(ascii_qr, "\n", trim: true)

        qr_width =
          case qr_lines do
            [first_line | _] -> String.length(first_line)
            [] -> 0
          end

        # Create pretty terminal formatting
        border_width = max(qr_width + 4, 66)
        border_line = String.duplicate("═", border_width)
        empty_line = "║" <> String.duplicate(" ", border_width) <> "║"

        # Center the title
        title = "WhatsApp QR Code"
        title_padding = div(border_width - String.length(title), 2)

        title_line =
          "║" <>
            String.duplicate(" ", title_padding) <>
            title <>
            String.duplicate(" ", border_width - title_padding - String.length(title)) <> "║"

        # Format each QR line with borders
        formatted_qr_lines =
          Enum.map_join(qr_lines, "\n", fn line ->
            padding_needed = border_width - String.length(line) - 4
            left_pad = div(padding_needed, 2)
            right_pad = padding_needed - left_pad

            "║  " <>
              String.duplicate(" ", left_pad) <> line <> String.duplicate(" ", right_pad) <> "  ║"
          end)

        # Instructions line
        instructions = "Scan this QR code with your phone to connect"
        instr_padding = div(border_width - String.length(instructions), 2)

        instr_line =
          "║" <>
            String.duplicate(" ", instr_padding) <>
            instructions <>
            String.duplicate(" ", border_width - instr_padding - String.length(instructions)) <>
            "║"

        terminal_qr = """
        ╔#{border_line}╗
        #{title_line}
        ╠#{border_line}╣
        #{empty_line}
        #{formatted_qr_lines}
        #{empty_line}
        #{instr_line}
        #{empty_line}
        ╚#{border_line}╝
        """

        {:ok, terminal_qr}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Convenience function that generates a QR string and renders it as terminal output.

  Takes authentication components and returns a formatted ASCII QR code.
  """
  @spec generate_and_render(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def generate_and_render(ref, noise_key_b64, identity_key_b64, adv_b64) do
    # Handle nil values by converting to empty strings
    safe_ref = ref || ""
    safe_noise = noise_key_b64 || ""
    safe_identity = identity_key_b64 || ""
    safe_adv = adv_b64 || ""

    qr_string = generate_qr_string(safe_ref, safe_noise, safe_identity, safe_adv)
    render_terminal(qr_string)
  end
end
