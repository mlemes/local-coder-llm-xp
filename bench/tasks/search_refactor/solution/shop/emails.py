from shop import users


def greeting(user):
    # uses get_user_name so greeting and order lines match
    return "Hello, " + users.get_user_name(user) + "!"
