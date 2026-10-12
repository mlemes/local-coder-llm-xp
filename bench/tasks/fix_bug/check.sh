#!/usr/bin/env bash
# usage: check.sh <workdir>
cd "$1" || exit 1
python3 - <<'PY'
from cart import cart_total, line_total

assert line_total(10, 3) == 30
assert line_total(10, 3, 10) == 27
assert line_total(19.99, 3, 15) == 50.97
assert line_total(10, 1, 100) == 0
assert line_total(10, 0, 50) == 0
assert cart_total([]) == 0
assert cart_total([(10, 3, 10), (5, 2)]) == 37
assert cart_total([(19.99, 3, 15), (0.1, 3)]) == 51.27
PY
