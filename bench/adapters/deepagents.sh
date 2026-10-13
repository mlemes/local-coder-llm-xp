#!/usr/bin/env bash
# Column F. LangChain Deep Agents Code (dcode) on the local server (OpenAI-compatible route).
# usage: deepagents.sh <prompt-file> <workdir> <usage-out-file>
set -euo pipefail
prompt=$1 work=$2 usage=$3
: >"$usage"
bench=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$HOME/.config/local-coder.env"
export HOME="$bench/.home/deepagents" OPENAI_API_KEY="$API_KEY" OPENAI_BASE_URL="http://$HOST:$PORT/v1"
cd "$work"
"$HOME/.local/bin/dcode" -n "$(cat "$prompt")" --model "openai:$MODEL_ALIAS"
