from shop.emails import greeting
from shop.orders import order_line

u = {"first": "Ada", "last": "Lovelace"}
print(greeting(u))
print(order_line({"user": u, "item": "book"}))
