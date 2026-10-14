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
# Report: pass rate, median seconds, median tokens over passing rows that report tokens.
f=$(mktemp)
printf 'task\tcol\trun\tmode\tpass\tsecs\tstatus\tin_tok\tout_tok\nt\tC\t1\tno-loop\t1\t10\t0\t100\t50\nt\tC\t2\tno-loop\t0\t30\t0\t\t\nt\tC\t3\tno-loop\t1\t20\t0\t300\t150\n' >"$f"
./report.sh "$f" | grep -qF '| C | no-loop | 3 | 2/3 (66%) | 20 | 300 |' || { echo "FAIL: report row mismatch"; bad=1; }
# Every column letter, with or without an @model suffix, must resolve to an adapter script and a backend.
for c in A B C D E F G H I C@luna F@haiku I@local A@luna; do
  a=$(bash -c "source <(sed -n '/^adapter_for()/p' run.sh); adapter_for $c")
  [ -x "adapters/$a.sh" ] || { echo "FAIL: column $c has no adapter ($a)"; bad=1; }
done
be() { bash -c "source <(sed -n '/^backend_for()/p' run.sh); backend_for $1"; }
[ "$(be A)" = haiku ] && [ "$(be I)" = luna ] && [ "$(be C)" = local ] && [ "$(be C@luna)" = luna ] && [ "$(be I@local)" = local ] ||
  { echo "FAIL: backend_for mapping"; bad=1; }
# No adapter may hold a literal key, and the key file must stay ignored.
! grep -rEn 'sk-[A-Za-z0-9_-]{16,}' adapters/ run.sh || { echo "FAIL: literal key in bench"; bad=1; }
grep -qx '.keys.env' .gitignore || { echo "FAIL: .keys.env not ignored"; bad=1; }
[ "$bad" = 0 ] && echo "selftest ok"
exit "$bad"
