#!/usr/bin/env bash
# Column D. Qwen Code on the local server through its OpenAI-compatible settings.
# usage: qwen-code.sh <prompt-file> <workdir> <usage-out-file>
set -euo pipefail
prompt=$1 work=$2 usage=$3
: >"$usage"
bench=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$HOME/.config/local-coder.env"
export OPENAI_API_KEY="$API_KEY" OPENAI_BASE_URL="http://$HOST:$PORT/v1" OPENAI_MODEL="$MODEL_ALIAS"
cd "$work"
"$bench/.tools/node_modules/.bin/qwen" --yolo "$(cat "$prompt")"
