#!/usr/bin/env bash
# usage: check.sh <workdir>
cd "$1" || exit 1
python3 - <<'PY'
from geometry import Rect, area
from report import summary

assert Rect(2, 3).w == 2 and Rect(2, 3).h == 3
assert tuple(Rect(2, 3)) == (2, 3)
assert area(Rect(2, 3)) == 6
assert area(Rect(0, 5)) == 0
assert summary([(2, 3), (4, 5)]) == "total area: 26"
assert summary([]) == "total area: 0"
try:
    area(2, 3)
except TypeError:
    pass
else:
    raise AssertionError("old two-argument area() signature still works")
PY
