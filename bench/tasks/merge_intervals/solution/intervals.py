def merge_intervals(intervals):
    pairs = [tuple(p) for p in intervals]
    if any(s > e for s, e in pairs):
        raise ValueError("start > end")
    out = []
    for s, e in sorted(pairs):
        if out and s <= out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], e))
        else:
            out.append((s, e))
    return out
