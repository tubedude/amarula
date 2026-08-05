defmodule Amarula.MixProject do
  use Mix.Project

  # `Amarula.Protocol.*` modules that ARE consumer-facing and so stay in the docs
  # (see `filter_modules` below).
  @doc_exceptions [
    "Amarula.Protocol.Call",
    "Amarula.Protocol.Messages.Poll",
    "Amarula.Protocol.Messages.PollCrypto"
  ]

  def project do
    [
      app: :amarula,
      version: "0.6.0",
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

  # ExDoc config. `mix docs` builds the HTML/epub reference; the architecture
  # guides ride along as extras so they're published, not just in-repo.
  # (`usage-rules.md` is deliberately NOT an extra — it ships in the hex package
  # for consumers' agents to sync via `mix usage_rules.sync`, but it's an
  # agent-facing spec, not a human docs page, so it stays off the ExDoc surface.)
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
      #
      # Three `Amarula.Protocol.*` modules are exceptions: the consumer-facing API
      # documents them by name, so hiding them left the docs pointing at pages that
      # don't exist. `Call` is the `:call_update` event payload; `Poll` and
      # `PollCrypto` are how a consumer tallies and decrypts incoming poll votes
      # (`Amarula.Content.PollVote` is explicitly "not self-contained" and sends you
      # to them).
      filter_modules: fn mod, _meta ->
        name = inspect(mod)

        name in @doc_exceptions or
          not (String.starts_with?(name, "Amarula.Protocol.") or
                 String.starts_with?(name, "Amarula.Connection."))
      end,
      # Collapse module families into "folders" in the sidebar instead of many
      # flat top-level entries: the ~20 Amarula.Content.* message-content structs,
      # and the Storage / RetryCache behaviours with their adapters.
      nest_modules_by_prefix: [
        Amarula.Content,
        Amarula.Storage,
        Amarula.RetryCache,
        Amarula.MessageSecretStore
      ],
      extras: [
        "README.md",
        "docs/INFRASTRUCTURE.md",
        "docs/CUSTODIAN_BENCHMARKS.md",
        "docs/LID_PN.md",
        "docs/GOING_PROD.md",
        "docs/PARITY.md",
        "docs/PITFALLS.md",
        "CHANGELOG.md",
        "LICENSE",
        "NOTICE"
      ],
      # Internal `Amarula.Protocol.*` modules are deliberately referenced by name in
      # docs ("built via `…JID`", "see `…SessionCustodian`") — the name IS the
      # information, even though the page isn't published. Render them as code, not
      # links, instead of warning on every mention. The three published exceptions
      # above still autolink.
      skip_code_autolink_to: &skip_autolink?/1,
      # The CHANGELOG documents functions that genuinely no longer exist (renames and
      # removals in earlier releases). Those references are correct history; they just
      # can't resolve.
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
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

  # Skip autolinking (and its warning) for internal modules: the whole
  # `Amarula.Protocol.*` layer bar the published exceptions, and the generated
  # protobuf structs, which are `@moduledoc false`.
  defp skip_autolink?(ref) do
    (String.starts_with?(ref, "Amarula.Protocol.") and
       not Enum.any?(@doc_exceptions, &String.starts_with?(ref, &1))) or
      String.starts_with?(ref, "Amarula.Connection.")
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
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  #
  # Constraint style, and the one trade-off worth understanding before editing.
  #
  # DEFAULT for 0.x deps: stay inside the minor — `~> 0.5.1`, meaning
  # `>= 0.5.1 and < 0.6.0`. Patch releases float in; a 0.6 does not. By Elixir
  # convention a 0.x MINOR bump is upstream's breaking/feature channel, and this
  # is a LIBRARY: our requirements compose with the consumer's, so a wide bound
  # lets them resolve onto a version we have never compiled against.
  #
  # The cost is the protobuf CVE in miniature: that fix shipped in 0.16.1 while
  # our `~> 0.15.0` capped at `< 0.16.0`, blocking consumers by one digit (see
  # the 0.5.6 CHANGELOG). A tight bound WILL eventually sit in front of a fix,
  # because 0.x projects ship fixes in minor bumps.
  #
  # What makes that acceptable is that a bound is no longer allowed to go stale
  # quietly: `.github/workflows/deps-freshness.yml` runs
  # `scripts/check_dep_headroom.exs` weekly and FAILS when a newer version
  # exists that one of these bounds forbids. Widening is then a reviewed commit
  # that ran the suite first, rather than something a consumer discovers for us.
  # If that job is ever removed, revisit this policy with it — they are a pair.
  #
  # DELIBERATE EXCEPTION — `protobuf` is `~> 0.17`, not `~> 0.17.0`. It decodes
  # bytes from any peer that can open a Signal session with us, so it is the
  # dependency where a security fix most needs to reach consumers without
  # waiting on us to cut a release. Here the CVE lesson outranks the
  # untested-minor risk, and the floor is what matters: `~> 0.17` guarantees
  # consumers are above CVE-2026-54451. Do not tighten it to `~> 0.17.0`.
  #
  # `req` is `~> 0.4` and predates this policy; it is wide for no articulated
  # reason. Narrow it to the current minor when someone has time to test that.
  #
  # `mix.lock` still pins exact versions for our CI; it is not shipped.
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
      {:protobuf, "~> 0.17"},

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
