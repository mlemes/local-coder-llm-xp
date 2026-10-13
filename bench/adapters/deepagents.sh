#!/usr/bin/env bash
# Column F. LangChain Deep Agents Code (dcode) on the local server (OpenAI-compatible route).
# usage: deepagents.sh <prompt-file> <workdir> <usage-out-file>
set -euo pipefail
prompt=$1 work=$2 usage=$3
: >"$usage"
bench=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$HOME/.config/local-coder.env"
# llama-server rejects empty message content that dcode sends after tool calls; proxy fixes it.
pport=$((PORT + 1))
python3 -I "$bench/adapters/fix_empty_content.py" "$pport" "$PORT" &
proxy=$!
trap 'kill $proxy 2>/dev/null' EXIT
sleep 1
export HOME="$bench/.home/deepagents" OPENAI_API_KEY="$API_KEY" OPENAI_BASE_URL="http://$HOST:$pport/v1"
cd "$work"
"$HOME/.local/bin/dcode" -n "$(cat "$prompt")" --model "openai:$MODEL_ALIAS"
