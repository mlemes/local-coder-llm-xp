from collections import namedtuple

Rect = namedtuple("Rect", "w h")


def area(rect):
    return rect.w * rect.h
