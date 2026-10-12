#!/usr/bin/env bash
set -euo pipefail
ENV_FILE="${LOCAL_CODER_ENV:-$HOME/.config/local-coder.env}"
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
BASE="http://$HOST:$PORT"
AUTH=(-H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json")

fail() { echo "FAIL: $*" >&2; exit 1; }

status="$(curl -fs "$BASE/health" | jq -r '.status')" || fail "health request"
[ "$status" = "ok" ] || fail "health status: $status"
echo "ok: health"

content="$(curl -fs "$BASE/v1/chat/completions" "${AUTH[@]}" \
  -d "{\"model\":\"$MODEL_ALIAS\",\"max_tokens\":64,\"messages\":[{\"role\":\"user\",\"content\":\"Say hello.\"}]}" \
  | jq -r '.choices[0].message.content // empty')" || fail "chat request"
[ -n "$content" ] || fail "empty chat content"
echo "ok: chat"

tool="$(curl -fs "$BASE/v1/chat/completions" "${AUTH[@]}" -d "{
  \"model\":\"$MODEL_ALIAS\",\"max_tokens\":256,
  \"messages\":[{\"role\":\"user\",\"content\":\"Read README.md\"}],
  \"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"read_file\",
    \"description\":\"Read a file from disk\",
    \"parameters\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}}}]
}" | jq -r '.choices[0].message.tool_calls[0].function.name // empty')" || fail "tool request"
[ "$tool" = "read_file" ] || fail "tool call name: '$tool'"
echo "ok: tool call"
