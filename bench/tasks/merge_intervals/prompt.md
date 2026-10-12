Create `intervals.py` in the current directory with a function `merge_intervals(intervals)`.

- `intervals` is a list of `(start, end)` pairs of numbers.
- Return a new list of `(start, end)` tuples, sorted by start, where overlapping or touching intervals are merged. For example, `(1, 2)` and `(2, 3)` merge into `(1, 3)`.
- Do not modify the input list or its items.
- Raise `ValueError` if any pair has `start > end`.
- An empty list returns an empty list.
