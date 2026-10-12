#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${LOCAL_CODER_ENV:-$HOME/.config/local-coder.env}"
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
if [ -z "${API_KEY:-}" ]; then
  echo "API_KEY is empty; set it in $ENV_FILE" >&2
  exit 1
fi
exec "$ROOT/vendor/llama.cpp/build/bin/llama-server" \
  -m "$ROOT/models/$MODEL_FILE" --alias "$MODEL_ALIAS" --host "$HOST" --port "$PORT" \
  --api-key "$API_KEY" --jinja -ngl 99 --n-cpu-moe "$N_CPU_MOE" \
  -c "$CTX_SIZE" -ub 128 -fa on --cache-type-k q8_0 --cache-type-v q8_0 \
  --parallel 1 --threads "$THREADS" -lm none \
  --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0 --repeat-penalty 1.0 \
  --reasoning-budget 2048
