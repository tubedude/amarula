defmodule Amarula.MixProject do
  use Mix.Project

  def project do
    [
      app: :amarula,
      version: "0.5.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      description:
        "An independent, OTP-native WhatsApp Web client for Elixir — Noise handshake, Signal end-to-end encryption, multi-device.",
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
      # Keep internals out of the published docs. The Amarula.Protocol.* layer
      # (socket, crypto, signal, binary, messages, …) and the Amarula.Connection.*
      # helper submodules (Pairing, Notifications, PreKeyOps, Receive, …) are pure
      # implementation — consumers use only the top-level Amarula.* facade, structs,
      # and behaviours. The top-level Amarula.Connection coordinator is kept (the
      # architecture guide links it). Hidden modules stay compiled and readable in
      # IEx (`h Module`); only the hexdocs surface shrinks.
      filter_modules: fn mod, _meta ->
        name = inspect(mod)

        not (String.starts_with?(name, "Amarula.Protocol.") or
               String.starts_with?(name, "Amarula.Connection."))
      end,
      # Collapse module families into "folders" in the sidebar instead of many
      # flat top-level entries: the ~20 Amarula.Content.* message-content structs,
      # and the Storage / RetryCache behaviours with their adapters.
      nest_modules_by_prefix: [Amarula.Content, Amarula.Storage, Amarula.RetryCache],
      extras: [
        "README.md",
        "docs/INFRASTRUCTURE.md",
        "docs/CUSTODIAN_BENCHMARKS.md",
        "docs/LID_PN.md",
        "docs/GOING_PROD.md",
        "docs/PARITY.md",
        "usage-rules.md",
        "CHANGELOG.md",
        "LICENSE",
        "NOTICE"
      ],
      source_url: "https://github.com/tubedude/amarula",
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  # Renders ```mermaid fenced blocks in the extras (e.g. docs/INFRASTRUCTURE.md's
  # supervision tree) as diagrams. ExDoc has no built-in Mermaid support; this is
  # the documented recipe (see deps/ex_doc/README.md, "Rendering Mermaid graphs")
  # — a CDN script that finds `pre code.mermaid` after the page loads and swaps
  # in a rendered SVG.
  defp before_closing_body_tag(:html) do
    """
    <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
    <script>
      let initialized = false;
      window.addEventListener("exdoc:loaded", () => {
        if (!initialized) {
          mermaid.initialize({
            startOnLoad: false,
            theme: document.body.className.includes("dark") ? "dark" : "default"
          });
          initialized = true;
        }
        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp before_closing_body_tag(_), do: ""

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
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Telemetry events (operators attach handlers / a metrics reporter)
      {:telemetry, "~> 1.0"},

      # Option schemas: validate + auto-document the `opts` on facade send_* fns
      {:nimble_options, "~> 1.0"},

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
