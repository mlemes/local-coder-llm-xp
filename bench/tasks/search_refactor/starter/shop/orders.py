from shop.users import get_usr_nm


def order_line(order):
    return f"{get_usr_nm(order['user'])} ordered {order['item']}"
