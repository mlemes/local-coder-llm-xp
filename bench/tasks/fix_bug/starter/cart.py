def line_total(price, qty, discount_pct=0):
    """Return price * qty after a percentage discount, rounded to 2 decimals."""
    return round(price * qty - discount_pct, 2)


def cart_total(lines):
    """Sum line totals. Each line is (price, qty) or (price, qty, discount_pct)."""
    return round(sum(line_total(*line) for line in lines), 2)
