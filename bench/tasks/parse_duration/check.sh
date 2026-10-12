#!/usr/bin/env bash
# usage: check.sh <workdir>
cd "$1" || exit 1
python3 - <<'PY'
from duration import parse_duration as p

assert p("1h30m15s") == 5415
assert p("90s") == 90
assert p("1d") == 86400
assert p("0s") == 0
assert p("007s") == 7
assert p("1h1h") == 7200
assert p("15s30m1h") == 5415
assert p("999999d") == 999999 * 86400
for bad in ["", "5", "1x", "-1s", "1.5h", "1h 30m", " 1h", "h", "1H", "1h30", "1s\n"]:
    try:
        p(bad)
    except ValueError:
        continue
    raise AssertionError(f"no ValueError for {bad!r}")
PY
