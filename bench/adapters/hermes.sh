#!/usr/bin/env bash
# Column G. Hermes Agent on the local server (custom OpenAI-compatible endpoint, 64K context minimum).
# usage: hermes.sh <prompt-file> <workdir> <usage-out-file>
set -euo pipefail
prompt=$1 work=$2 usage=$3
: >"$usage"
bench=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$HOME/.config/local-coder.env"
export HOME="$bench/.home/hermes" HERMES_HOME="$bench/.home/hermes/.hermes"
mkdir -p "$HERMES_HOME"
cat >"$HERMES_HOME/config.yaml" <<YML
model:
  default: $MODEL_ALIAS
  provider: custom
  base_url: http://$HOST:$PORT/v1
  context_length: $CTX_SIZE
YML
printf 'OPENAI_API_KEY=%s\n' "$API_KEY" >"$HERMES_HOME/.env"
cd "$work"
"$HOME/.local/bin/hermes" chat -q "$(cat "$prompt")"
