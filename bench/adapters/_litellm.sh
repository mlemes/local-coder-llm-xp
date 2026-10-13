# Sourced by adapters that need protocol translation (Claude Code on Luna, Codex on Haiku).
# Starts a LiteLLM proxy on 127.0.0.1:$LL_PORT with models "luna" and "haiku", stops it on exit.
bench_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LL_PORT=${LL_PORT:-4000}
ll_dir=$(mktemp -d)
cat >"$ll_dir/config.yaml" <<YML
model_list:
  - model_name: luna
    litellm_params: {model: openai/responses/gpt-6-luna, api_key: os.environ/OPENAI_API_KEY}
  - model_name: haiku
    litellm_params: {model: anthropic/claude-haiku-5-5, api_key: os.environ/ANTHROPIC_API_KEY}
litellm_settings: {drop_params: true}
YML
LL_KEY=sk-bench-$(openssl rand -hex 16)
LITELLM_MASTER_KEY=$LL_KEY \
OPENAI_API_KEY=$(sed -n 's/^OPENAI_API_KEY=//p' "$bench_dir/.keys.env") \
ANTHROPIC_API_KEY=$(sed -n 's/^ANTHROPIC_API_KEY=//p' "$bench_dir/.keys.env") \
  "$bench_dir/.tools/litellm/bin/litellm" --config "$ll_dir/config.yaml" --host 127.0.0.1 --port "$LL_PORT" >"$ll_dir/log" 2>&1 &
ll_pid=$!
trap 'kill $ll_pid 2>/dev/null; rm -rf "$ll_dir"' EXIT
for _ in $(seq 60); do curl -fsS -o /dev/null "http://127.0.0.1:$LL_PORT/health/liveliness" 2>/dev/null && break; sleep 1; done
