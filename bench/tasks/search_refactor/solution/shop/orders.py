from shop.users import get_user_name


def order_line(order):
    return f"{get_user_name(order['user'])} ordered {order['item']}"
