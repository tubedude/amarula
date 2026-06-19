defmodule Amarula.MixProject do
  use Mix.Project

  def project do
    [
      app: :amarula,
      version: "0.1.1",
      # 1.18 is the real floor: 1.17- compiles but the test suite uses the
      # built-in JSON module (1.18+). Verified by CI (see .github elixir.yml).
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      description: "A WhatsApp Web client for Elixir — an idiomatic OTP port of Baileys.",
      package: package(),
      docs: docs(),
      test_coverage: test_coverage()
    ]
  end

  # Coverage config. The generated `Proto.*` modules are compiled protobuf, not
  # hand-written logic, so excluding them stops them from drowning the signal —
  # they're either trivially 100% or unused-and-0%, neither of which tells us
  # anything about test quality.
  defp test_coverage do
    [
      # Realistic floor for hand-written code (protos excluded below). Raise it as
      # coverage grows; keep it at/under the current number so `--cover` stays green.
      summary: [threshold: 64],
      ignore_modules: [~r/^Amarula\.Protocol\.Proto\./]
    ]
  end

  # Hex/package metadata. MIT-licensed; ships the LICENSE + NOTICE that retain the
  # upstream Baileys (MIT) copyright as that license requires.
  defp package do
    [
      licenses: ["MIT"],
      files: ~w(lib mix.exs README.md usage-rules.md LICENSE NOTICE),
      links: %{
        "GitHub" => "https://github.com/tubedude/amarula",
        "Baileys (upstream)" => "https://github.com/WhiskeySockets/Baileys"
      }
    ]
  end

  # ExDoc config. `mix docs` builds the HTML/epub reference; the architecture and
  # usage guides ride along as extras so they're published, not just in-repo.
  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/INFRASTRUCTURE.md",
        "docs/GOING_PROD.md",
        "docs/PARITY.md",
        "usage-rules.md",
        "CHANGELOG.md"
      ],
      source_url: "https://github.com/tubedude/amarula"
    ]
  end

  # `mix check` runs the test suite, so default it to the :test env.
  def cli do
    [preferred_envs: [check: :test]]
  end

  # `mix check` — format the code and run the test suite. Run before committing.
  defp aliases do
    [
      check: ["format", "test"]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Amarula.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Telemetry events (operators attach handlers / a metrics reporter)
      {:telemetry, "~> 1.0"},

      # WebSocket client
      {:websockex, "~> 0.5.1"},

      # JSON handling
      {:jason, "~> 1.4"},

      # Protocol buffers
      {:protobuf, "~> 0.15.0"},

      # HTTP client
      {:req, "~> 0.4"},

      # UUID generation
      {:uuid, "~> 1.1"},

      # Base64 encoding
      {:base64url, "~> 1.0"},

      # Binary manipulation
      {:binary, "~> 0.0.5"},

      # Image processing (optional)
      {:ex_image_info, "~> 0.2.4"},

      # QR code generation
      {:qr_code, "~> 3.2.0"},

      # Cryptographic operations (using built-in :crypto for most operations)

      # Development dependencies
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},

      # Testing dependencies
      # Plug powers Req.Test stubs (HTTP fakes for the media download path).
      {:plug, "~> 1.16", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
