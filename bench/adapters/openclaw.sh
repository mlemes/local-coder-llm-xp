#!/usr/bin/env bash
# Column H. OpenClaw embedded agent on the local server (custom OpenAI-compatible provider).
# usage: openclaw.sh <prompt-file> <workdir> <usage-out-file>
set -euo pipefail
prompt=$1 work=$2 usage=$3
: >"$usage"
bench=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$HOME/.config/local-coder.env"
source "$bench/adapters/_remote.sh"
export HOME="$bench/.home/openclaw"
rm -rf "$HOME" && mkdir -p "$HOME"
oc="$bench/.tools/node_modules/.bin/openclaw"
url="http://$HOST:$PORT/v1" model=$MODEL_ALIAS key=$API_KEY compat=openai
case $PROV_NAME in
  openai) url=$PROV_URL model=$PROV_MODEL key=$PROV_KEY compat=openai-responses ;;
  anthropic) url=https://api.anthropic.com model=$PROV_MODEL key=$PROV_KEY compat=anthropic ;;
esac
"$oc" onboard --non-interactive --accept-risk --auth-choice custom-api-key \
  --custom-base-url "$url" --custom-model-id "$model" \
  --custom-api-key "$key" --custom-compatibility "$compat" --skip-health --workspace "$work" --skip-bootstrap >/dev/null
cd "$work"
"$oc" agent --local --message-file "$prompt"
