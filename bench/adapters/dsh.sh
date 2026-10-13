#!/usr/bin/env bash
# Column E. DeepSeek Harness headless profile on the local server (custom openai-completions route via the dsh-llm-pi-ai plugin).
# usage: dsh.sh <prompt-file> <workdir> <usage-out-file>
set -euo pipefail
prompt=$1 work=$2 usage=$3
: >"$usage"
bench=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$HOME/.config/local-coder.env"
export HOME="$bench/.home/dsh" DSH_HOME="$bench/.home/dsh/.dsh" LOCAL_CODER_API_KEY="$API_KEY"
mkdir -p "$DSH_HOME"
cat >"$DSH_HOME/cordis.patch.yml" <<YML
- id: llm-pi-ai
  name: '@deepseek-ai/dsh-llm-pi-ai'
  config:
    providers:
      local:
        displayName: Local Qwen
        apiKeyEnv: LOCAL_CODER_API_KEY
        api: openai-completions
        baseURL: http://$HOST:$PORT/v1
        models:
          - id: $MODEL_ALIAS
            contextWindow: $CTX_SIZE
- id: agent-default-model
  name: '@deepseek-ai/dsh-agent-default-model'
  config:
    provider: local
    model: $MODEL_ALIAS
YML
cd "$work"
"$bench/.tools/node_modules/.bin/dsh" --profile headless "$(cat "$prompt")"
