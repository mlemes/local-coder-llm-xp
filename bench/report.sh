#!/usr/bin/env bash
# Print a markdown table from a results file. Usage: report.sh [results.tsv]
set -euo pipefail
cd "$(dirname "$0")"
f=${1:-results.tsv}
median() { sort -n | awk '{a[NR]=$1} END{if(!NR)print "-"; else print (NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2}'; }
echo '| Column | Mode | Runs | Pass rate | Median secs | Median tokens per pass |'
echo '| --- | --- | ---: | ---: | ---: | ---: |'
for key in $(awk -F'\t' 'NR>1{print $2":"$4}' "$f" | sort -u); do
  col=${key%%:*}
  mode=${key##*:}
  rows=$(awk -F'\t' -v c="$col" -v m="$mode" 'NR>1 && $2==c && $4==m' "$f")
  n=$(wc -l <<<"$rows")
  p=$(awk -F'\t' '$5==1' <<<"$rows" | wc -l)
  secs=$(cut -f6 <<<"$rows" | median)
  tok=$(awk -F'\t' '$5==1 && $8!="" && $9!="" {print $8+$9}' <<<"$rows" | median)
  printf '| %s | %s | %s | %s/%s (%s%%) | %s | %s |\n' "$col" "$mode" "$n" "$p" "$n" "$((100 * p / n))" "$secs" "$tok"
done
