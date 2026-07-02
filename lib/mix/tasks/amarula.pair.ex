defmodule Mix.Tasks.Amarula.Pair do
  @shortdoc "Link a WhatsApp account to a profile via QR or phone code"

  @moduledoc """
  Link (pair) a WhatsApp account to a named profile — by QR code or phone code.

  Unlike the `examples/` scripts (which are not shipped in the Hex package), this
  task lives under `lib/` and so is available to **any project that depends on
  Amarula**. That's the intended way for a downstream integration (e.g. a
  `jido_chat` WhatsApp adapter) to get a user paired before running an agent.

      # QR: prints a scannable QR in your terminal
      mix amarula.pair <profile>
      mix amarula.pair guest

      # Phone code: prints an 8-char code to type into WhatsApp instead of scanning
      mix amarula.pair <profile> --phone <e164-digits>
      mix amarula.pair guest --phone 5511999999999

  On the phone: **WhatsApp → Settings → Linked Devices → Link a device** (QR), or
  **"Link with phone number instead"** (phone code).

  Credentials persist under the storage root (`AMARULA_DATA_DIR`, default
  `./amarula_data`), scoped to `<profile>/`, so your app reconnects later without
  re-pairing. If the profile is already paired, this just connects, confirms, and
  exits.

  ## Options

    * `--phone <digits>` — pair by phone code for this E.164 number (digits only;
      `+`, spaces and dashes are stripped) instead of showing a QR.
    * `--timeout <seconds>` — give-up bound for the whole flow (default `180`).
  """

  use Mix.Task

  require Logger

  alias Amarula.Protocol.Auth.QRCodeGenerator

  @switches [phone: :string, timeout: :integer]

  @impl Mix.Task
  def run(argv) do
    {opts, args} = OptionParser.parse!(argv, strict: @switches)

    profile =
      case args do
        [p] ->
          String.to_atom(p)

        _ ->
          Mix.raise(
            "usage: mix amarula.pair <profile> [--phone <e164-digits>] [--timeout <seconds>]"
          )
      end

    phone =
      case opts[:phone] do
        nil ->
          nil

        raw ->
          digits = String.replace(raw, ~r/\D/, "")
          if digits == "", do: Mix.raise("--phone must be E.164 digits, e.g. 5511999999999")
          digits
      end

    timeout_ms = (opts[:timeout] || 180) * 1000

    # Start the consumer app (loads config) and Amarula's supervision tree.
    Mix.Task.run("app.start")

    {:ok, conn} =
      %{profile: profile}
      |> Amarula.new()
      |> Amarula.connect(parent_pid: self())

    if phone,
      do:
        Logger.info(
          "Pairing #{inspect(profile)} by phone code for +#{phone} — watch for the code below."
        ),
      else: Logger.info("Pairing #{inspect(profile)} — scan the QR below with the target phone.")

    deadline = System.monotonic_time(:millisecond) + timeout_ms

    case loop(conn, %{phone: phone, requested?: false}, deadline) do
      :ok ->
        Logger.info(
          "✅ #{inspect(profile)} linked. Credentials persisted; your app can now connect without re-pairing."
        )

        # Brief grace for the final creds write to land.
        Process.sleep(1000)

      :timeout ->
        Mix.raise(
          "Timed out before the connection opened — link faster, or check the logs above."
        )
    end
  end

  # Drive the pairing by reacting to {:amarula, _, _} events until :open (linked).
  defp loop(conn, state, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      :timeout
    else
      receive do
        # First QR while unregistered: either request a phone code, or render the QR.
        {:amarula, :connection_update, %{qr: qr}} when is_binary(qr) ->
          state = on_qr(conn, qr, state)
          loop(conn, state, deadline)

        {:amarula, :pairing_code, %{code: code}} ->
          announce_code(code)
          loop(conn, state, deadline)

        {:amarula, :pairing_success, _data} ->
          Logger.info("Paired — completing login…")
          loop(conn, state, deadline)

        {:amarula, :connection_update, %{connection: :open}} ->
          :ok

        {:amarula, :error, error} ->
          Logger.error("Connection error: #{inspect(error)}")
          loop(conn, state, deadline)

        {:amarula, _type, _data} ->
          loop(conn, state, deadline)
      after
        remaining -> :timeout
      end
    end
  end

  # Phone-code path: request the code once, on the first QR window. Ignore rotations.
  defp on_qr(conn, _qr, %{phone: phone, requested?: false} = state) when is_binary(phone) do
    case Amarula.request_pairing_code(conn, phone) do
      {:ok, code} -> announce_code(code)
      {:error, reason} -> Logger.error("request_pairing_code failed: #{inspect(reason)}")
    end

    %{state | requested?: true}
  end

  defp on_qr(_conn, _qr, %{phone: phone} = state) when is_binary(phone), do: state

  # QR path: render the (rotating) QR each time.
  defp on_qr(_conn, qr, state) do
    case QRCodeGenerator.render_terminal(qr) do
      {:ok, ascii} -> IO.puts("\n" <> ascii <> "\n")
      {:error, reason} -> Logger.warning("Could not render QR (#{inspect(reason)}); raw: #{qr}")
    end

    state
  end

  defp announce_code(code) do
    IO.puts("\n  Link with phone number → enter this code in WhatsApp: #{code}\n")
  end
end
