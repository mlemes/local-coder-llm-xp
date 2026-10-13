#!/usr/bin/env bash
# Harness x model matrix from results.tsv: pass rate and median seconds.
# usage: bench/matrix.sh [--tsv] [results.tsv]   (--tsv prints tab-separated rows with a header)
set -euo pipefail
cd "$(dirname "$0")"
TSV=0
[ "${1:-}" = --tsv ] && { TSV=1; shift; }
R=${1:-results.tsv}
harness() { case ${1%@*} in A | B) echo "claude-local-code" ;; C) echo OpenCode ;; D) echo "Qwen Code" ;; E) echo "DeepSeek Harness" ;; F) echo "Deep Agents Code" ;; G) echo Hermes ;; H) echo OpenClaw ;; I) echo "Codex CLI" ;; esac; }
model() { case $1 in *@luna | I) echo Luna ;; *@haiku | A) echo Haiku ;; *) echo "Qwen3.6-35B-A3B (local)" ;; esac; }
rows_tsv() {
  tail -n +2 "$R" | cut -f2,4 | sort -u | while IFS=$'\t' read -r col mode; do
    rows=$(awk -F'\t' -v c="$col" -v m="$mode" '$2==c && $4==m {print $5, $6}' "$R")
    n=$(wc -l <<<"$rows")
    p=$(awk '{s+=$1} END {print s}' <<<"$rows")
    med=$(awk '{print $2}' <<<"$rows" | sort -n | awk '{a[NR]=$1} END {print (NR%2 ? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2)}')
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(model "$col")$(harness "$col")$mode" "$(harness "$col")" "$(model "$col")" "$mode" "$n" "$p" $((100 * p / n)) "$med"
  done | sort | cut -f2-
}
if [ "$TSV" = 1 ]; then
  printf 'harness\tmodel\tmode\truns\tpasses\tpass_pct\tmedian_secs\n'
  rows_tsv
else
  echo "| Harness | Model | Mode | Runs | Pass rate | Median secs |"
  echo "| --- | --- | --- | ---: | ---: | ---: |"
  rows_tsv | awk -F'\t' '{printf "| %s | %s | %s | %s | %s/%s (%s%%) | %s |\n", $1,$2,$3,$4,$5,$4,$6,$7}'
fi
