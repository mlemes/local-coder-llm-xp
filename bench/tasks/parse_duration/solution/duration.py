import re

_UNITS = {"d": 86400, "h": 3600, "m": 60, "s": 1}


def parse_duration(text):
    if not re.fullmatch(r"([0-9]+[dhms])+", text):
        raise ValueError(f"invalid duration: {text!r}")
    return sum(int(n) * _UNITS[u] for n, u in re.findall(r"([0-9]+)([dhms])", text))
