#!/usr/bin/env bash
# Columns A and B. BACKEND=haiku uses the production default; BACKEND=local points the same wrapper at the local server.
# usage: claude-local-code.sh <prompt-file> <workdir> <usage-out-file>   env: BACKEND MODE TEST_CMD
set -euo pipefail
prompt=$1 work=$2 usage=$3
: >"$usage"
adir=$(cd "$(dirname "$0")" && pwd)
cd "$work"
if [ "$BACKEND" = local ]; then
  # shellcheck disable=SC1091
  source "$HOME/.config/local-coder.env"
  unset ANTHROPIC_API_KEY
  export ANTHROPIC_BASE_URL="http://$HOST:$PORT" ANTHROPIC_AUTH_TOKEN="$API_KEY" CODER_MODEL="$MODEL_ALIAS"
  export ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL_ALIAS" ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL_ALIAS" ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL_ALIAS"
  export CLAUDE_CODE_MAX_CONTEXT_TOKENS="$CTX_SIZE" CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
fi
if [ "$BACKEND" = luna ]; then
  # shellcheck disable=SC1091
  source "$adir/_litellm.sh"
  unset ANTHROPIC_API_KEY
  export ANTHROPIC_BASE_URL="http://127.0.0.1:$LL_PORT" ANTHROPIC_AUTH_TOKEN="$LL_KEY" CODER_MODEL=luna
  export ANTHROPIC_DEFAULT_HAIKU_MODEL=luna ANTHROPIC_DEFAULT_SONNET_MODEL=luna ANTHROPIC_DEFAULT_OPUS_MODEL=luna CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
fi
if [ "$MODE" = loop ]; then
  claude-local-code --test "$TEST_CMD" "$(cat "$prompt")"
else
  claude-local-code "$(cat "$prompt")"
fi
