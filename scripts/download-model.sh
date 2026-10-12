#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${LOCAL_CODER_ENV:-$HOME/.config/local-coder.env}"
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
mkdir -p "$ROOT/models"
DEST="$ROOT/models/$MODEL_FILE"
if [ -f "$DEST" ]; then
  echo "Model exists: $DEST"
  exit 0
fi
curl -L -C - --fail -o "$DEST.part" "https://huggingface.co/$MODEL_REPO/resolve/main/$MODEL_FILE"
mv "$DEST.part" "$DEST"
