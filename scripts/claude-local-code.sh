#!/usr/bin/env bash
# Headless, code-only Claude Code run on the local model. Usage: claude-local-code "task" (or task on stdin).
set -euo pipefail
task="${1:-$(cat)}"
[ -n "$task" ] || { echo "usage: claude-local-code \"task\"" >&2; exit 1; }
SYSTEM="You are a code-writing agent. Working directory: $PWD. Use absolute paths under it. Read only the files you need, then make the requested change with Edit or Write. Do not run commands, explain, or add unrequested files. Do not re-read a file after a successful edit. Stop as soon as the change is made and reply with one line per changed file: path: what changed."
exec claude-local -p "$task" --bare --system-prompt "$SYSTEM" \
  --tools Read Edit Write Glob Grep --permission-mode acceptEdits --max-turns 30 </dev/null
