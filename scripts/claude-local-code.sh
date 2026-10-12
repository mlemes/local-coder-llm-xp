#!/usr/bin/env bash
# Headless, code-only Claude Code run on the local model.
# Usage: claude-local-code [--test "cmd"] [--max N] "task"   (or task on stdin)
# With --test, the wrapper runs the test command after each edit and sends the failure back to the model.
# When the same test fails 3 times, Gemini (agy, plan mode: no edits) diagnoses the cause, and the
# diagnosis goes into the next attempt. Stops when the tests pass or after N attempts (default 8).
set -euo pipefail
test_cmd="" max=8
while [ $# -gt 0 ]; do
  case "$1" in
    --test) test_cmd="$2"; shift 2 ;;
    --max) max="$2"; shift 2 ;;
    *) break ;;
  esac
done
task="${1:-$(cat)}"
[ -n "$task" ] || { echo "usage: claude-local-code [--test cmd] [--max N] \"task\"" >&2; exit 1; }
SYSTEM="You are a code-writing agent. Working directory: $PWD. Use absolute paths under it.
Rules:
1. Locate files with Glob or Grep. Never guess a path or a symbol name.
2. Read a file before you edit it. For Edit, copy old_string exactly from the file, including indentation, and make it unique. If Edit fails, Read the file again and retry once with more context.
3. Match the existing style, naming, imports, and error handling. Reuse existing helpers.
4. Make the smallest change that meets the spec. Do not touch unrelated code. Do not add unrequested files, comments, or tests.
5. Use Write only for new files named in the task.
6. You cannot run commands. The wrapper runs the tests after your edit and sends you any failure.
7. If the spec is ambiguous, take the simplest reading and say so in the reply.
8. Do not re-read a file after a successful edit. Stop once the change is complete.
Reply with one line per changed file, path: what changed. Add one line per assumption, if any."
run() { claude-local -p "$1" --bare --system-prompt "$SYSTEM" --tools Read Edit Write Glob Grep --permission-mode acceptEdits --max-turns 30 </dev/null; }

[ -z "$test_cmd" ] && { run "$task"; exit; }

declare -A fails=()
prompt="$task" log=""
for ((i = 1; i <= max; i++)); do
  run "$prompt" || echo "attempt $i: model run ended with an error" >&2
  if out=$(bash -c "$test_cmd" 2>&1); then echo "tests pass (attempt $i): $test_cmd"; exit 0; fi
  log=$(printf '%s\n' "$out" | grep -E '✖|not ok|FAIL|Error|assert|expected|actual|\+ |- ' | head -60)
  names=$(printf '%s\n' "$out" | grep -E '^\s*(✖|not ok)' | sed -E 's/^\s*(✖|not ok [0-9]+ -)\s*//; s/\s*\([0-9.]+ms\)$//' | sort -u)
  hint=""
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    fails[$n]=$(( ${fails[$n]:-0} + 1 ))
    if [ "${fails[$n]}" -ge 3 ] && [ -z "$hint" ]; then
      echo "attempt $i: \"$n\" failed 3 times, consulting Gemini" >&2
      hint=$(timeout 360 agy -p "Diagnose a failing test. Do not edit any file. Repo: $PWD. Task given to the coder: $task
Test command: $test_cmd
Failure output:
$log
Read the code and the test it names. Reply in under 15 lines: the root cause and the exact change that fixes it." --mode plan --print-timeout 300s 2>&1 | tail -20) || hint=""
      for k in "${!fails[@]}"; do fails[$k]=0; done
    fi
  done <<< "$names"
  prompt="$task

Attempt $i failed. Test command: $test_cmd
Failure output:
$log${hint:+

Diagnosis from a reviewer (follow it):
$hint}"
done
echo "tests still failing after $max attempts:" >&2
printf '%s\n' "$log" | tail -20 >&2
exit 1
