#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${LOCAL_CODER_ENV:-$HOME/.config/local-coder.env}"
TEST_PORT="${TUNE_PORT:-8099}"
MIN_FREE_MB=500
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

TMP_ENV="$(mktemp)"
PID=""
stop_server() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  PID=""
}
cleanup() { stop_server; rm -f "$TMP_ENV"; }
trap cleanup EXIT

BEST=""
SPEED=""
for N in 48 44 40 36 32 28 24 20 16 12 8 4 0; do
  # run.sh sources the env file, so overrides go in a temp copy appended last.
  { cat "$ENV_FILE"; printf '\nN_CPU_MOE=%s\nPORT=%s\nHOST=127.0.0.1\n' "$N" "$TEST_PORT"; } > "$TMP_ENV"
  LOCAL_CODER_ENV="$TMP_ENV" "$ROOT/scripts/run.sh" >/dev/null 2>&1 &
  PID=$!
  ok=0
  for _ in $(seq 1 120); do
    kill -0 "$PID" 2>/dev/null || break
    if curl -fs "http://127.0.0.1:$TEST_PORT/health" >/dev/null 2>&1; then ok=1; break; fi
    sleep 2
  done
  if [ "$ok" -eq 1 ]; then
    free="$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -n1 | tr -d ' ')"
    echo "N_CPU_MOE=$N free_vram_mb=$free" >&2
    if [ "$free" -ge "$MIN_FREE_MB" ]; then
      BEST="$N"
      SPEED="$(curl -fs "http://127.0.0.1:$TEST_PORT/completion" \
        -H "Authorization: Bearer $API_KEY" -H 'Content-Type: application/json' \
        -d '{"prompt":"Write a Python function that reverses a string.","n_predict":200}' \
        | jq -r '.timings.predicted_per_second // empty' || true)"
    fi
  else
    echo "N_CPU_MOE=$N failed to load" >&2
  fi
  stop_server
  sleep 2
done

if [ -z "$BEST" ]; then
  echo "No N_CPU_MOE value loaded with at least ${MIN_FREE_MB} MB free VRAM" >&2
  exit 1
fi
echo "N_CPU_MOE=$BEST"
echo "decode_tokens_per_second=${SPEED:-unknown}" >&2
