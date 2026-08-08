# Credo configuration.
#
# Deliberately minimal — this is the default check set with two documented
# adjustments, not a hand-tuned ruleset. Anything else that credo reports is meant
# to be fixed or explicitly disabled at the call site with a reason, so the count
# stays at zero and CI can keep `mix credo` blocking (see .github/workflows/elixir.yml).
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [
          ~r"/_build/",
          ~r"/deps/",
          # Generated from proto/wa_proto.proto by protoc — 30k+ lines we do not
          # write or review, and cannot fix. Already excluded from coverage in
          # mix.exs (`ignore_modules`) for the same reason; without this it
          # contributed permanent findings nobody could act on.
          ~r"lib/amarula/protocol/proto/"
        ]
      },
      strict: false,
      checks: %{
        extra: [
          # Credo's default is 2, which is strict for protocol code: one `case` on a
          # decoded node inside a `with` already reaches 3. Raised once, here, with a
          # reason — rather than scattered disables across six crypto/protocol
          # functions where reshaping the code for style carries more risk than the
          # nesting costs in readability.
          {Credo.Check.Refactor.Nesting, max_nesting: 3}
        ],
        disabled: []
      }
    }
  ]
}
