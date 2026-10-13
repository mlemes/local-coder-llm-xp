#!/usr/bin/env bash
# Column H. OpenClaw embedded agent on the local server (custom OpenAI-compatible provider).
# usage: openclaw.sh <prompt-file> <workdir> <usage-out-file>
set -euo pipefail
prompt=$1 work=$2 usage=$3
: >"$usage"
bench=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$HOME/.config/local-coder.env"
export HOME="$bench/.home/openclaw"
rm -rf "$HOME" && mkdir -p "$HOME"
oc="$bench/.tools/node_modules/.bin/openclaw"
"$oc" onboard --non-interactive --accept-risk --auth-choice custom-api-key \
  --custom-base-url "http://$HOST:$PORT/v1" --custom-model-id "$MODEL_ALIAS" \
  --custom-api-key "$API_KEY" --custom-compatibility openai --skip-health --workspace "$work" --skip-bootstrap >/dev/null
cd "$work"
"$oc" agent --local --message-file "$prompt"
