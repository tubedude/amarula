#!/usr/bin/env bash
# Extract the protobuf schema from live WhatsApp Web, in the single-file shape
# proto/wa_proto.proto uses. Needs node + npm.
#
#   scripts/extract_proto.sh proto/wa_proto.proto   # then regenerate (see CLAUDE.md)
#
# Uses Baileys' proto-extract at BAILEYS_REF (default: the docs/PARITY.md
# watermark; bump it with the watermark) with two fixes:
#   - proto3 has no `required` (Baileys #2860);
#   - proto3 enums must start at 0: add UNKNOWN_<NAME> = 0 where missing.
set -euo pipefail

out=$(realpath -m "${1:?usage: extract_proto.sh OUT.proto}")
ref=${BAILEYS_REF:-bb0a87e0326ca8f882fe716c7ee42da362f73fc0}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/proto-extract" "$work/WAProto"
for f in index.js package.json package-lock.json; do
  curl -fsSL "https://raw.githubusercontent.com/WhiskeySockets/Baileys/$ref/proto-extract/$f" \
    -o "$work/proto-extract/$f"
done

# Baileys #2860. A no-op once it is merged.
perl -0pi -e "s/flags\.push\(m\.property\.name\.toLowerCase\(\)\);/if (m.property.name !== 'REQUIRED') flags.push(m.property.name.toLowerCase());/" \
  "$work/proto-extract/index.js"
grep -q "'REQUIRED'" "$work/proto-extract/index.js" ||
  { echo "extract_proto.sh: Baileys #2860 patch did not apply — update this script" >&2; exit 1; }

(cd "$work/proto-extract" && npm ci --ignore-scripts --no-audit --no-fund --silent && node index.js)

perl -0pe 's/^([ \t]*)enum (\w+) \{\n([ \t]*)(\w+ = (-?\d+);)/$5 == 0 ? $& : "$1enum $2 {\n$3UNKNOWN_\U$2\E = 0;\n$3$4"/gme' \
  "$work/WAProto/WAProto.proto" > "$out"

echo "wrote $out ($(sed -n 's#^/// WhatsApp Version: ##p' "$out"))"
