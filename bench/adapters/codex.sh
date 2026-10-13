#!/usr/bin/env bash
# Column I. Codex CLI on gpt-6-luna (remote, ChatGPT login).
# usage: codex.sh <prompt-file> <workdir> <usage-out-file>
set -euo pipefail
prompt=$1 work=$2 usage=$3
: >"$usage"
cd "$work"
log=$(mktemp)
codex exec -m gpt-6-luna -s workspace-write --skip-git-repo-check --ephemeral -C "$work" - <"$prompt" 2>&1 | tee "$log"
# codex prints the total as "tokens used" followed by the number
tok=$(awk '/^tokens used/{getline; gsub(",",""); print; exit}' "$log")
[ -z "$tok" ] || echo "input_tokens=$tok" >"$usage"
rm -f "$log"
