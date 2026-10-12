from geometry import area


def summary(dims):
    """dims is a list of (width, height) pairs."""
    total = sum(area(w, h) for w, h in dims)
    return f"total area: {total}"
