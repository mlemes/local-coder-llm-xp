#!/usr/bin/env bash
# Column C. OpenCode on the local server, using clients/opencode.json.
# usage: opencode.sh <prompt-file> <workdir> <usage-out-file>
set -euo pipefail
prompt=$1 work=$2 usage=$3
: >"$usage"
bench=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$HOME/.config/local-coder.env"
source "$bench/adapters/_remote.sh"
export LOCAL_CODER_API_KEY="$API_KEY"
export OPENCODE_CONFIG="$bench/../clients/opencode.json"
export OPENCODE_PERMISSION='{"edit":"allow","bash":"allow","webfetch":"deny"}'
cd "$work"
if [ -n "$PROV_NAME" ]; then
  export "$KEYVAR=$PROV_KEY"
  "$bench/.tools/node_modules/.bin/opencode" run --auto -m "$PROV_NAME/$PROV_MODEL" "$(cat "$prompt")"
else
  "$bench/.tools/node_modules/.bin/opencode" run --auto "$(cat "$prompt")"
fi
