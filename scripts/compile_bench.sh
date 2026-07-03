#!/usr/bin/env bash
# Compile-time benchmark for Amarula.
#
# Measures the phases that make up a cold ("first time") build and the warm
# incremental edit loop, so changes to compile cost are measurable rather than
# felt. Run from the repo root: `bash scripts/compile_bench.sh`.
#
# Nothing here is destructive beyond the build/deps caches it is meant to
# rebuild; it restores a normal dev build (`mix compile`) at the end.
set -euo pipefail
cd "$(dirname "$0")/.."

ms() { echo "$(( ($2 - $1) / 1000000 ))ms"; }
now() { date +%s%N; }

echo "cores: $(nproc)"
echo "elixir: $(elixir --version | tail -1)"
echo

echo "== deps: runtime-only (MIX_ENV=prod) =="
mix deps.clean --all >/dev/null 2>&1
MIX_ENV=prod mix deps.get >/dev/null 2>&1
t0=$(now); MIX_ENV=prod mix deps.compile >/dev/null 2>&1; t1=$(now)
echo "  $(ms "$t0" "$t1")"

echo "== deps: full dev toolchain (ex_doc/credo/dialyxir) =="
mix deps.get >/dev/null 2>&1
t0=$(now); mix deps.compile >/dev/null 2>&1; t1=$(now)
echo "  $(ms "$t0" "$t1")   (delta vs runtime-only ≈ dev tooling)"

echo "== app: clean compile =="
rm -rf _build/dev/lib/amarula
t0=$(now); mix compile >/dev/null 2>&1; t1=$(now)
echo "  $(ms "$t0" "$t1")"

echo "== app: slowest single files (--force) =="
mix compile --force --long-compilation-threshold 3 2>&1 | grep -iE "more than" | sed 's/^/  /'

echo "== app: incremental edit of connection.ex =="
printf '\n# compile-bench-touch\n' >> lib/amarula/connection.ex
t0=$(now); mix compile >/dev/null 2>&1; t1=$(now)
echo "  $(ms "$t0" "$t1")"
git checkout lib/amarula/connection.ex

echo "== app: no-op (fixed mix/BEAM overhead floor) =="
t0=$(now); mix compile >/dev/null 2>&1; t1=$(now)
echo "  $(ms "$t0" "$t1")"
