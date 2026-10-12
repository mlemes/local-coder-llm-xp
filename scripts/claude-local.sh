#!/usr/bin/env bash
set -euo pipefail
source "$HOME/.config/local-coder.env"
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
export ANTHROPIC_BASE_URL="http://$HOST:$PORT"
export ANTHROPIC_AUTH_TOKEN="$API_KEY"
export ANTHROPIC_MODEL="$MODEL_ALIAS"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL_ALIAS"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL_ALIAS"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL_ALIAS"
export CLAUDE_CODE_MAX_CONTEXT_TOKENS="$CTX_SIZE"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
systemctl --user start local-coder.service
ready=false
for ((attempt=0; attempt<120; attempt++)); do
  if curl -fsS --max-time 2 "$ANTHROPIC_BASE_URL/health" 2>/dev/null | jq -e '.status == "ok"' >/dev/null; then
    ready=true
    break
  fi
  sleep 2
done
if [ "$ready" != true ]; then
  echo "Local model is not ready; inspect journalctl --user -u local-coder." >&2
  exit 1
fi
exec claude --settings "$HOME/.config/local-coder-claude.json" --model "$MODEL_ALIAS" "$@"
