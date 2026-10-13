#!/usr/bin/env bash
# Column I. Codex CLI. Default: gpt-6-luna on the ChatGPT login. I@haiku: Haiku through LiteLLM.
# I@local: local Qwen through llama-server (/v1/responses).
# usage: codex.sh <prompt-file> <workdir> <usage-out-file>
set -euo pipefail
prompt=$1 work=$2 usage=$3
: >"$usage"
bench=$(cd "$(dirname "$0")/.." && pwd)
cd "$work"
args=(-s workspace-write --skip-git-repo-check --ephemeral -C "$work")
case ${BACKEND:-luna} in
  haiku)
    # shellcheck disable=SC1091
    source "$bench/adapters/_litellm.sh"
    export CODEX_HOME="$bench/.home/codex-haiku" LL_KEY
    mkdir -p "$CODEX_HOME"
    printf 'model = "haiku"\nmodel_provider = "ll"\n[model_providers.ll]\nname = "ll"\nbase_url = "http://127.0.0.1:%s/v1"\nenv_key = "LL_KEY"\nwire_api = "responses"\n' "$LL_PORT" >"$CODEX_HOME/config.toml"
    ;;
  local)
    # shellcheck disable=SC1091
    source "$HOME/.config/local-coder.env"
    export CODEX_HOME="$bench/.home/codex" LOCAL_KEY="$API_KEY"
    mkdir -p "$CODEX_HOME"
    printf 'model = "%s"\nmodel_provider = "local"\n[model_providers.local]\nname = "local"\nbase_url = "http://%s:%s/v1"\nenv_key = "LOCAL_KEY"\nwire_api = "responses"\n' "$MODEL_ALIAS" "$HOST" "$PORT" >"$CODEX_HOME/config.toml"
    ;;
  *) args+=(-m gpt-6-luna) ;;
esac
log=$(mktemp)
codex exec "${args[@]}" - <"$prompt" 2>&1 | tee "$log"
# codex prints the total as "tokens used" followed by the number
tok=$(awk '/^tokens used/{getline; gsub(",",""); print; exit}' "$log")
[ -z "$tok" ] || echo "input_tokens=$tok" >"$usage"
rm -f "$log"
