Create `duration.py` in the current directory with a function `parse_duration(text: str) -> int` that returns the total number of seconds.

- `text` is one or more `<integer><unit>` parts joined with no separators, for example `1h30m15s`.
- Units: `d` (86400 s), `h` (3600 s), `m` (60 s), `s` (1 s). Units are lowercase.
- Parts can appear in any order and can repeat. Repeated units add up.
- Raise `ValueError` for anything else, including an empty string, a bare number, an unknown unit, a negative or decimal number, or spaces.
