from shop import users


def greeting(user):
    # uses get_usr_nm so greeting and order lines match
    return "Hello, " + users.get_usr_nm(user) + "!"
