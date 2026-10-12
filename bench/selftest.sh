#!/usr/bin/env bash
# Each check must fail on the bare starter and pass on the known-good solution.
cd "$(dirname "$0")" || exit 1
bad=0
for t in tasks/*/; do
  n=$(basename "$t")
  w=$(mktemp -d)
  cp -r "$t/starter/." "$w"
  if bash "$t/check.sh" "$w" >/dev/null 2>&1; then echo "FAIL $n: check passes on the bare starter"; bad=1; fi
  cp -r "$t/solution/." "$w"
  if ! bash "$t/check.sh" "$w" >/dev/null 2>&1; then echo "FAIL $n: check fails on the solution"; bad=1; fi
  rm -rf "$w"
done
n_tasks=$(ls -d tasks/*/ 2>/dev/null | wc -l)
[ "$n_tasks" -eq 5 ] || { echo "FAIL: expected 5 tasks, found $n_tasks"; bad=1; }
[ "$bad" = 0 ] && echo "selftest ok"
exit "$bad"
