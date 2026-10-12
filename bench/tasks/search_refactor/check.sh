#!/usr/bin/env bash
# usage: check.sh <workdir>
cd "$1" || exit 1
if grep -rqI --exclude-dir=__pycache__ 'get_usr_nm' .; then
  echo "FAIL: get_usr_nm still present" >&2
  exit 1
fi
grep -q 'def get_user_name' shop/users.py || { echo "FAIL: get_user_name not defined in shop/users.py" >&2; exit 1; }
out=$(python3 main.py 2>&1)
want=$'Hello, Ada Lovelace!\nAda Lovelace ordered book'
[ "$out" = "$want" ] || { echo "FAIL: unexpected output: $out" >&2; exit 1; }
