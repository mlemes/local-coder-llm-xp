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
# Runner dry run with stub adapters. Column C has one mode, so each stub run yields 5 rows.
dry() { # <stub> <results-file> [extra env assignments]
  env COLS=C RUNS=1 ADAPTER_OVERRIDE="stubs/$1.sh" RESULTS="$2" LOGDIR="$(mktemp -d)" "${@:3}" ./run.sh >/dev/null 2>&1
}
r=$(mktemp -u)
dry good "$r"; dry good "$r"
[ "$(grep -c '^task' "$r")" = 1 ] || { echo "FAIL: results header repeated"; bad=1; }
awk -F'\t' 'NR>1 && $5!=1 {exit 1}' "$r" || { echo "FAIL: good stub did not pass every task"; bad=1; }
[ "$(wc -l <"$r")" = 11 ] || { echo "FAIL: expected 10 rows plus header"; bad=1; }
r=$(mktemp -u)
dry noop "$r"
awk -F'\t' 'NR>1 && $5!=0 {exit 1}' "$r" || { echo "FAIL: noop stub passed a task"; bad=1; }
r=$(mktemp -u)
dry sleep "$r" TIMEOUT=2 TASKS=parse_duration
awk -F'\t' 'NR==2 && ($5!=0 || $7!=124) {exit 1}' "$r" || { echo "FAIL: timeout row should have pass=0 status=124"; bad=1; }
[ "$bad" = 0 ] && echo "selftest ok"
exit "$bad"
