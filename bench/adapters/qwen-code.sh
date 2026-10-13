#!/usr/bin/env bash
# Column D. Qwen Code on the local server through its OpenAI-compatible settings.
# usage: qwen-code.sh <prompt-file> <workdir> <usage-out-file>
set -euo pipefail
prompt=$1 work=$2 usage=$3
: >"$usage"
bench=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$HOME/.config/local-coder.env"
source "$bench/adapters/_remote.sh"
if [ -n "$PROV_NAME" ]; then
  # Luna rejects max_tokens; the bench proxy renames it.
  pport=$((PORT + 2))
  python3 -I "$bench/adapters/fix_empty_content.py" "$pport" "https://$(echo "${PROV_URL#https://}" | cut -d/ -f1)" &
  proxy=$!
  trap 'kill $proxy 2>/dev/null' EXIT
  sleep 1
  PROV_URL="http://127.0.0.1:$pport/v1"
  export OPENAI_API_KEY="$PROV_KEY" OPENAI_BASE_URL="$PROV_URL" OPENAI_MODEL="$PROV_MODEL"
else
  export OPENAI_API_KEY="$API_KEY" OPENAI_BASE_URL="http://$HOST:$PORT/v1" OPENAI_MODEL="$MODEL_ALIAS"
fi
cd "$work"
"$bench/.tools/node_modules/.bin/qwen" --yolo "$(cat "$prompt")"
