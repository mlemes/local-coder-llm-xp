#!/usr/bin/env bash
# usage: check.sh <workdir>
cd "$1" || exit 1
python3 - <<'PY'
import copy
import random

from intervals import merge_intervals as m

assert m([]) == []
assert m([(1, 3), (2, 6), (8, 10), (15, 18)]) == [(1, 6), (8, 10), (15, 18)]
assert m([(1, 2), (2, 3)]) == [(1, 3)]
assert m([(5, 6), (1, 10)]) == [(1, 10)]
assert m([(3, 3)]) == [(3, 3)]
assert m([[1, 2], [4, 5]]) == [(1, 2), (4, 5)]
src = [(5, 7), (1, 3), (2, 4)]
snap = copy.deepcopy(src)
out = m(src)
assert src == snap
assert out == [(1, 4), (5, 7)]
assert all(type(x) is tuple for x in out)
try:
    m([(3, 1)])
except ValueError:
    pass
else:
    raise AssertionError("no ValueError for start > end")


def brute(iv):
    iv = [tuple(x) for x in iv]
    changed = True
    while changed:
        changed = False
        for i in range(len(iv)):
            for j in range(i + 1, len(iv)):
                a, b = iv[i], iv[j]
                if a[0] <= b[1] and b[0] <= a[1]:
                    iv[i] = (min(a[0], b[0]), max(a[1], b[1]))
                    del iv[j]
                    changed = True
                    break
            if changed:
                break
    return sorted(iv)


random.seed(1)
for _ in range(300):
    iv = []
    for _ in range(random.randint(0, 8)):
        a = random.randint(0, 20)
        iv.append((a, a + random.randint(0, 6)))
    assert m(iv) == brute(iv), iv
PY
