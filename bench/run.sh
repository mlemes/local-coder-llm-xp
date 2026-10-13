#!/usr/bin/env bash
# Benchmark runner.
# Env: COLS="A B C D"  RUNS=3  TASKS=<names>  TIMEOUT=900  RESULTS  LOGDIR
#      ADAPTER_OVERRIDE=<script>  (dry run: use this adapter for every column, skip the model)
# Columns: A claude-local-code on Haiku, B claude-local-code on local Qwen, C OpenCode, D Qwen Code (local Qwen).
set -euo pipefail
cd "$(dirname "$0")"
BENCH=$PWD
COLS=${COLS:-A B C D}
RUNS=${RUNS:-3}
TIMEOUT=${TIMEOUT:-900}
RESULTS=${RESULTS:-$BENCH/results.tsv}
LOGDIR=${LOGDIR:-$BENCH/logs}
TASKS=${TASKS:-$(ls tasks)}
mkdir -p "$LOGDIR"
[ -s "$RESULTS" ] || printf 'task\tcol\trun\tmode\tpass\tsecs\tstatus\tin_tok\tout_tok\n' >"$RESULTS"

# A column is a harness letter, optionally with a model: "C@luna", "C@haiku". No suffix means the default model.
adapter_for() { case ${1%@*} in A | B) echo claude-local-code ;; C) echo opencode ;; D) echo qwen-code ;; E) echo dsh ;; F) echo deepagents ;; G) echo hermes ;; H) echo openclaw ;; I) echo codex ;; esac; }
backend_for() { case $1 in *@*) echo "${1#*@}" ;; A) echo haiku ;; I) echo luna ;; *) echo local ;; esac; }
modes_for() { case ${1%@*} in A | B) echo "no-loop loop" ;; *) echo no-loop ;; esac; }

# Claude 7-day quota utilization (fraction), from a one-word headless call.
weekly_util() {
  claude -p "Reply ok" --model haiku --output-format stream-json --verbose </dev/null 2>/dev/null |
    grep -m1 rate_limit_event | jq -r '.rate_limit_info.unifiedWindows.seven_day.utilization // empty' || true
}

started_service=0
stop_local() { if [ "$started_service" = 1 ]; then systemctl --user stop local-coder.service || true; fi; }
trap stop_local EXIT

ensure_local() {
  [ -z "${ADAPTER_OVERRIDE:-}" ] || return 0
  # shellcheck disable=SC1091
  source "$HOME/.config/local-coder.env"
  health() { curl -fsS --max-time 2 "http://$HOST:$PORT/health" 2>/dev/null | grep -q '"ok"'; }
  health && return 0
  systemctl --user start local-coder.service
  started_service=1
  for ((i = 0; i < 48; i++)); do
    health && return 0
    sleep 5
  done
  journalctl --user -u local-coder -n 30 >&2
  echo "local model not ready" >&2
  exit 1
}

need_tool() { # <path under bench> <install hint>
  [ -n "${ADAPTER_OVERRIDE:-}" ] || [ -x "$1" ] || {
    echo "missing $1: $2" >&2
    exit 1
  }
}

run_one() { # task col run mode
  local task=$1 col=$2 run=$3 mode=$4 tag work usage start secs status=0 pass=0 adapter
  tag="$task-$col-$run-$mode"
  work=$(mktemp -d)
  usage=$(mktemp)
  cp -r "tasks/$task/starter/." "$work"
  adapter="adapters/$(adapter_for "$col").sh"
  [ -z "${ADAPTER_OVERRIDE:-}" ] || adapter=$ADAPTER_OVERRIDE
  start=$(date +%s)
  BACKEND=$(backend_for "$col") MODE=$mode TEST_CMD="bash $BENCH/tasks/$task/check.sh $work" \
    timeout -k 10 "$TIMEOUT" "$adapter" "$BENCH/tasks/$task/prompt.md" "$work" "$usage" \
    >"$LOGDIR/$tag.log" 2>&1 || status=$?
  secs=$(($(date +%s) - start))
  bash "tasks/$task/check.sh" "$work" >"$LOGDIR/$tag.check" 2>&1 && pass=1
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$task" "$col" "$run" "$mode" "$pass" "$secs" "$status" \
    "$(sed -n 's/^input_tokens=//p' "$usage")" "$(sed -n 's/^output_tokens=//p' "$usage")" >>"$RESULTS"
  rm -rf "$work" "$usage"
  echo "$tag pass=$pass secs=$secs status=$status"
}

for c in $COLS; do
  case ${c%@*} in
    C) need_tool .tools/node_modules/.bin/opencode "npm install --prefix bench/.tools opencode-ai" ;;
    D) need_tool .tools/node_modules/.bin/qwen "npm install --prefix bench/.tools @qwen-code/qwen-code" ;;
    E) need_tool .tools/node_modules/.bin/dsh "npm install --prefix bench/.tools @deepseek-ai/dsh" ;;
    F) need_tool .home/deepagents/.local/bin/dcode "install dcode with HOME=bench/.home/deepagents" ;;
    G) need_tool .home/hermes/.local/bin/hermes "install hermes with HOME=bench/.home/hermes" ;;
    H) need_tool .tools/node_modules/.bin/openclaw "npm install --prefix bench/.tools openclaw" ;;
  esac
done

for c in $COLS; do
  if [ "$(backend_for "$c")" = local ]; then ensure_local; fi
  q0=""
  if [ "$c" = A ] && [ -z "${ADAPTER_OVERRIDE:-}" ]; then q0=$(weekly_util); fi
  for task in $TASKS; do
    for mode in $(modes_for "$c"); do
      for ((r = 1; r <= RUNS; r++)); do
        run_one "$task" "$c" "$r" "$mode"
      done
    done
  done
  if [ "$c" = A ] && [ -z "${ADAPTER_OVERRIDE:-}" ]; then
    echo "column A weekly utilization: before=${q0:-?} after=$(weekly_util)" | tee -a "$LOGDIR/quota.txt"
  fi
done
