from geometry import Rect, area


def summary(dims):
    """dims is a list of (width, height) pairs."""
    total = sum(area(Rect(w, h)) for w, h in dims)
    return f"total area: {total}"
