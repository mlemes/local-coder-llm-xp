#!/usr/bin/env bash
# Column G. Hermes Agent on the local server (custom OpenAI-compatible endpoint, 64K context minimum).
# usage: hermes.sh <prompt-file> <workdir> <usage-out-file>
set -euo pipefail
prompt=$1 work=$2 usage=$3
: >"$usage"
bench=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$HOME/.config/local-coder.env"
source "$bench/adapters/_remote.sh"
export HOME="$bench/.home/hermes" HERMES_HOME="$bench/.home/hermes/.hermes"
mkdir -p "$HERMES_HOME"
if [ "$PROV_NAME" = anthropic ]; then
  printf 'model:\n  default: %s\n  provider: anthropic\n' "$PROV_MODEL" >"$HERMES_HOME/config.yaml"
  printf 'ANTHROPIC_API_KEY=%s\n' "$PROV_KEY" >"$HERMES_HOME/.env"
elif [ "$PROV_NAME" = openai ]; then
  printf 'model:\n  default: %s\n  provider: custom\n  base_url: %s\n  api_key: %s\n' "$PROV_MODEL" "$PROV_URL" "$PROV_KEY" >"$HERMES_HOME/config.yaml"
  printf 'OPENAI_API_KEY=%s\n' "$PROV_KEY" >"$HERMES_HOME/.env"
else
  printf 'model:\n  default: %s\n  provider: custom\n  base_url: http://%s:%s/v1\n  context_length: %s\n  api_key: %s\n' "$MODEL_ALIAS" "$HOST" "$PORT" "$CTX_SIZE" "$API_KEY" >"$HERMES_HOME/config.yaml"
  printf 'OPENAI_API_KEY=%s\n' "$API_KEY" >"$HERMES_HOME/.env"
fi
cd "$work"
"$HOME/.local/bin/hermes" chat --query-file "$prompt" -Q --yolo --no-restore-cwd
