#!/usr/bin/env bash
# Download a LiteRT-LM Gemma model into app/Models/ (gitignored).
# Requires: huggingface-cli (`pip install huggingface_hub`) and HF access if the repo is gated.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/app/Models"
mkdir -p "$OUT"

REPO="${GEMMA_HF_REPO:-litert-community/gemma-4-E2B-it-litert-lm}"
FILE="${GEMMA_HF_FILE:-gemma-4-E2B-it.litertlm}"

echo "Downloading $FILE from $REPO → $OUT"
if command -v huggingface-cli >/dev/null 2>&1; then
  huggingface-cli download "$REPO" "$FILE" --local-dir "$OUT" --local-dir-use-symlinks False
elif command -v hf >/dev/null 2>&1; then
  hf download "$REPO" "$FILE" --local-dir "$OUT"
else
  echo "Install Hugging Face CLI: pip install -U huggingface_hub" >&2
  exit 1
fi

# Normalize name if the hub layout nests the file
if [[ ! -f "$OUT/$FILE" ]]; then
  FOUND="$(find "$OUT" -name '*.litertlm' | head -n 1 || true)"
  if [[ -n "$FOUND" ]]; then
    cp "$FOUND" "$OUT/$FILE"
  fi
fi

# Models/ is bundled as a folder reference — drop the hub's download cache so it doesn't ship.
rm -rf "$OUT/.cache"

echo "Done. Set Secrets.gemmaModelFileName = \"$FILE\" if needed."
echo "Rebuild in Xcode; the model ships inside the app as Models/$FILE."
