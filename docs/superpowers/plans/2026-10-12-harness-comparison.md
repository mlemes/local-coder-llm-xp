# Harness comparison implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a shell-only benchmark that runs five coding tasks through four harness and backend columns, scores each run with a hidden check, and reports the results.

**Architecture:** `bench/run.sh` loops over tasks, columns, and runs. For each run it copies a task's `starter/` into a temp directory, calls a per-harness adapter, then runs the task's `check.sh` itself and appends a row to `bench/results.tsv`. `bench/report.sh` turns that file into a markdown table.

**Tech stack:** bash, Python 3 standard library (inside checks only), `jq`, `curl`, systemd user unit, npm (for `opencode-ai` and `@qwen-code/qwen-code`, installed into `bench/.tools/`).

**Spec:** `docs/superpowers/specs/2026-10-12-harness-comparison-design.md`

## Spec adjustments

These choices differ from the spec text. Task 7 step 1 updates the spec to match.

- **Cost for column A:** the wrapper prints plain text and exposes no usage. The runner records the 7-day quota utilization before and after column A instead, using the `rate_limit_event` check.
- **Adapter inputs:** adapters read `BACKEND`, `MODE`, and `TEST_CMD` from the environment, in addition to the three positional arguments.
- **Loop test command:** loop mode passes the real `check.sh` to the wrapper. The wrapper shows the agent only filtered failure lines.
- **Unreachable local model:** the runner prints the journal and exits. It does not mark rows `skipped`.
- **Order of work:** offline pieces (tasks, runner, report) come first. Task 4 confirms the OpenCode and Qwen Code flags, because the confirmation needs the local model.

## Global constraints

- The repository stays small: shell scripts, plain files, no new services. No Docker, no Python services.
- The local model starts only for the local columns and stops when the run ends. The GPU hosts one model at a time.
- Install `opencode` and `qwen-code` into `bench/.tools/`, which is gitignored. Do not install them globally.
- Static checks use `bash -n` and `shellcheck`. `shellcheck` is not installed on this machine, so use `bash -n` and tell the user. Do not start the service in static checks.
- Never trust a self-reported pass. The runner runs every check itself.
- The per-run timeout is 15 minutes (`TIMEOUT=900`).
- Each task runs three times per column (`RUNS=3`). The matrix is 5 tasks × 4 columns × 3 runs.
- Core docs: update `docs/architecture.md` and create `docs/data_flow.md` in the same change as the code.

## Review focus

- **Agent finds the hidden check.** Harnesses with a shell tool can search the filesystem for `bench/tasks/*/check.sh`. The report states this limit. No test pins it.
- **False pass on empty work.** The check could pass on the unchanged starter. Task 1's `selftest.sh` fails if any check passes on the bare starter.
- **Timeout leaves orphans.** A hung harness must die with its child processes. Task 2 tests that a sleeping stub gets status `124` and `pass=0`.
- **Duplicate header on re-run.** Running `run.sh` twice into one results file must keep one header. Task 2 tests it.
- **Blank token fields.** Harnesses may report no tokens. Task 3's report test includes a row with blank tokens and a median over the rows that have them.
- **Gemini diagnosis does not fire.** The wrapper triggers Gemini only on lines that start with `✖` or `not ok`. These checks print Python tracebacks and `FAIL:` lines, so the loop in columns A and B retries with the failure output and no Gemini hint. The report states this.

---

## File structure

| File | Responsibility |
| --- | --- |
| `bench/selftest.sh` | Proves every check fails on the bare starter and passes on the solution. Dry-runs the runner and the report with stubs. |
| `bench/run.sh` | Runner: loops, model lifecycle, timeout, scoring, quota delta. |
| `bench/report.sh` | Prints the markdown results table. |
| `bench/adapters/{claude-local-code,opencode,qwen-code}.sh` | One headless invocation per harness. |
| `bench/stubs/{good,noop,sleep}.sh` | Fake adapters for the dry run. |
| `bench/tasks/<name>/{prompt.md,starter/,solution/,check.sh}` | One task each. |
| `bench/.gitignore` | Ignores `.tools/`, `results.tsv`, `logs/`. |

---

### Task 1: Tasks and the self-test

**Files:**
- Create: `bench/.gitignore`, `bench/selftest.sh`
- Create: `bench/tasks/parse_duration/{prompt.md,check.sh,starter/.gitkeep,solution/duration.py}`
- Create: `bench/tasks/merge_intervals/{prompt.md,check.sh,starter/.gitkeep,solution/intervals.py}`
- Create: `bench/tasks/fix_bug/{prompt.md,check.sh,starter/cart.py,solution/cart.py}`
- Create: `bench/tasks/two_file_edit/{prompt.md,check.sh,starter/{geometry.py,report.py},solution/{geometry.py,report.py}}`
- Create: `bench/tasks/search_refactor/{prompt.md,check.sh,starter/{main.py,shop/__init__.py,shop/users.py,shop/orders.py,shop/emails.py},solution/{shop/users.py,shop/orders.py,shop/emails.py}}`

**Interfaces:**
- Produces: `tasks/<name>/check.sh <workdir>` exits 0 on pass and prints `FAIL:` lines or a Python traceback to the output on failure. `tasks/<name>/solution/` is a directory that you copy over `starter/` to get a passing tree. `tasks/<name>/prompt.md` is the text given to the agent.

- [ ] **Step 1: Write the self-test (it fails because no tasks exist)**

Create `bench/selftest.sh`:

```bash
#!/usr/bin/env bash
# Each check must fail on the bare starter and pass on the known-good solution.
cd "$(dirname "$0")" || exit 1
bad=0
for t in tasks/*/; do
  n=$(basename "$t")
  w=$(mktemp -d)
  cp -r "$t/starter/." "$w"
  if bash "$t/check.sh" "$w" >/dev/null 2>&1; then echo "FAIL $n: check passes on the bare starter"; bad=1; fi
  cp -r "$t/solution/." "$w"
  if ! bash "$t/check.sh" "$w" >/dev/null 2>&1; then echo "FAIL $n: check fails on the solution"; bad=1; fi
  rm -rf "$w"
done
n_tasks=$(ls -d tasks/*/ 2>/dev/null | wc -l)
[ "$n_tasks" -eq 5 ] || { echo "FAIL: expected 5 tasks, found $n_tasks"; bad=1; }
[ "$bad" = 0 ] && echo "selftest ok"
exit "$bad"
```

Create `bench/.gitignore`:

```text
.tools/
results.tsv
logs/
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash bench/selftest.sh`
Expected: prints `FAIL: expected 5 tasks, found 0` and exits 1.

- [ ] **Step 3: Create `parse_duration`**

`bench/tasks/parse_duration/prompt.md`:

```markdown
Create `duration.py` in the current directory with a function `parse_duration(text: str) -> int` that returns the total number of seconds.

- `text` is one or more `<integer><unit>` parts joined with no separators, for example `1h30m15s`.
- Units: `d` (86400 s), `h` (3600 s), `m` (60 s), `s` (1 s). Units are lowercase.
- Parts can appear in any order and can repeat. Repeated units add up.
- Raise `ValueError` for anything else, including an empty string, a bare number, an unknown unit, a negative or decimal number, or spaces.
```

`bench/tasks/parse_duration/check.sh`:

```bash
#!/usr/bin/env bash
# usage: check.sh <workdir>
cd "$1" || exit 1
python3 - <<'PY'
from duration import parse_duration as p

assert p("1h30m15s") == 5415
assert p("90s") == 90
assert p("1d") == 86400
assert p("0s") == 0
assert p("007s") == 7
assert p("1h1h") == 7200
assert p("15s30m1h") == 5415
assert p("999999d") == 999999 * 86400
for bad in ["", "5", "1x", "-1s", "1.5h", "1h 30m", " 1h", "h", "1H", "1h30", "1s\n"]:
    try:
        p(bad)
    except ValueError:
        continue
    raise AssertionError(f"no ValueError for {bad!r}")
PY
```

`bench/tasks/parse_duration/solution/duration.py`:

```python
import re

_UNITS = {"d": 86400, "h": 3600, "m": 60, "s": 1}


def parse_duration(text):
    if not re.fullmatch(r"([0-9]+[dhms])+", text):
        raise ValueError(f"invalid duration: {text!r}")
    return sum(int(n) * _UNITS[u] for n, u in re.findall(r"([0-9]+)([dhms])", text))
```

Then run `touch bench/tasks/parse_duration/starter/.gitkeep`.

- [ ] **Step 4: Create `merge_intervals`**

`bench/tasks/merge_intervals/prompt.md`:

```markdown
Create `intervals.py` in the current directory with a function `merge_intervals(intervals)`.

- `intervals` is a list of `(start, end)` pairs of numbers.
- Return a new list of `(start, end)` tuples, sorted by start, where overlapping or touching intervals are merged. For example, `(1, 2)` and `(2, 3)` merge into `(1, 3)`.
- Do not modify the input list or its items.
- Raise `ValueError` if any pair has `start > end`.
- An empty list returns an empty list.
```

`bench/tasks/merge_intervals/check.sh`:

```bash
#!/usr/bin/env bash
# usage: check.sh <workdir>
cd "$1" || exit 1
python3 - <<'PY'
import copy
import random

from intervals import merge_intervals as m

assert m([]) == []
assert m([(1, 3), (2, 6), (8, 10), (15, 18)]) == [(1, 6), (8, 10), (15, 18)]
assert m([(1, 2), (2, 3)]) == [(1, 3)]
assert m([(5, 6), (1, 10)]) == [(1, 10)]
assert m([(3, 3)]) == [(3, 3)]
assert m([[1, 2], [4, 5]]) == [(1, 2), (4, 5)]
src = [(5, 7), (1, 3), (2, 4)]
snap = copy.deepcopy(src)
out = m(src)
assert src == snap
assert out == [(1, 4), (5, 7)]
assert all(type(x) is tuple for x in out)
try:
    m([(3, 1)])
except ValueError:
    pass
else:
    raise AssertionError("no ValueError for start > end")


def brute(iv):
    iv = [tuple(x) for x in iv]
    changed = True
    while changed:
        changed = False
        for i in range(len(iv)):
            for j in range(i + 1, len(iv)):
                a, b = iv[i], iv[j]
                if a[0] <= b[1] and b[0] <= a[1]:
                    iv[i] = (min(a[0], b[0]), max(a[1], b[1]))
                    del iv[j]
                    changed = True
                    break
            if changed:
                break
    return sorted(iv)


random.seed(1)
for _ in range(300):
    iv = []
    for _ in range(random.randint(0, 8)):
        a = random.randint(0, 20)
        iv.append((a, a + random.randint(0, 6)))
    assert m(iv) == brute(iv), iv
PY
```

`bench/tasks/merge_intervals/solution/intervals.py`:

```python
def merge_intervals(intervals):
    pairs = [tuple(p) for p in intervals]
    if any(s > e for s, e in pairs):
        raise ValueError("start > end")
    out = []
    for s, e in sorted(pairs):
        if out and s <= out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], e))
        else:
            out.append((s, e))
    return out
```

Then run `touch bench/tasks/merge_intervals/starter/.gitkeep`.

- [ ] **Step 5: Create `fix_bug`**

`bench/tasks/fix_bug/prompt.md`:

```markdown
`cart.py` returns wrong totals when a discount is given. Find and fix the bug. Keep the function names and signatures. Change nothing else.
```

`bench/tasks/fix_bug/starter/cart.py`:

```python
def line_total(price, qty, discount_pct=0):
    """Return price * qty after a percentage discount, rounded to 2 decimals."""
    return round(price * qty - discount_pct, 2)


def cart_total(lines):
    """Sum line totals. Each line is (price, qty) or (price, qty, discount_pct)."""
    return round(sum(line_total(*line) for line in lines), 2)
```

`bench/tasks/fix_bug/solution/cart.py`: same file, with the first function body changed to:

```python
def line_total(price, qty, discount_pct=0):
    """Return price * qty after a percentage discount, rounded to 2 decimals."""
    return round(price * qty * (1 - discount_pct / 100), 2)


def cart_total(lines):
    """Sum line totals. Each line is (price, qty) or (price, qty, discount_pct)."""
    return round(sum(line_total(*line) for line in lines), 2)
```

`bench/tasks/fix_bug/check.sh`:

```bash
#!/usr/bin/env bash
# usage: check.sh <workdir>
cd "$1" || exit 1
python3 - <<'PY'
from cart import cart_total, line_total

assert line_total(10, 3) == 30
assert line_total(10, 3, 10) == 27
assert line_total(19.99, 3, 15) == 50.97
assert line_total(10, 1, 100) == 0
assert line_total(10, 0, 50) == 0
assert cart_total([]) == 0
assert cart_total([(10, 3, 10), (5, 2)]) == 37
assert cart_total([(19.99, 3, 15), (0.1, 3)]) == 51.27
PY
```

- [ ] **Step 6: Create `two_file_edit`**

`bench/tasks/two_file_edit/prompt.md`:

```markdown
In `geometry.py`, define `Rect = namedtuple("Rect", "w h")` and change `area(w, h)` to `area(rect)`, which returns `rect.w * rect.h`. Update `report.py` so `summary(dims)` still accepts a list of `(width, height)` pairs and returns the same strings as before.
```

`bench/tasks/two_file_edit/starter/geometry.py`:

```python
def area(w, h):
    return w * h
```

`bench/tasks/two_file_edit/starter/report.py`:

```python
from geometry import area


def summary(dims):
    """dims is a list of (width, height) pairs."""
    total = sum(area(w, h) for w, h in dims)
    return f"total area: {total}"
```

`bench/tasks/two_file_edit/solution/geometry.py`:

```python
from collections import namedtuple

Rect = namedtuple("Rect", "w h")


def area(rect):
    return rect.w * rect.h
```

`bench/tasks/two_file_edit/solution/report.py`:

```python
from geometry import Rect, area


def summary(dims):
    """dims is a list of (width, height) pairs."""
    total = sum(area(Rect(w, h)) for w, h in dims)
    return f"total area: {total}"
```

`bench/tasks/two_file_edit/check.sh`:

```bash
#!/usr/bin/env bash
# usage: check.sh <workdir>
cd "$1" || exit 1
python3 - <<'PY'
from geometry import Rect, area
from report import summary

assert Rect(2, 3).w == 2 and Rect(2, 3).h == 3
assert tuple(Rect(2, 3)) == (2, 3)
assert area(Rect(2, 3)) == 6
assert area(Rect(0, 5)) == 0
assert summary([(2, 3), (4, 5)]) == "total area: 26"
assert summary([]) == "total area: 0"
try:
    area(2, 3)
except TypeError:
    pass
else:
    raise AssertionError("old two-argument area() signature still works")
PY
```

- [ ] **Step 7: Create `search_refactor`**

`bench/tasks/search_refactor/prompt.md`:

```markdown
Rename the function `get_usr_nm` to `get_user_name` everywhere in this project: its definition, every call, every import, and every mention in comments. Behavior must not change. Running `python3 main.py` must print the same output as before.
```

Starter files:

`bench/tasks/search_refactor/starter/shop/__init__.py`: empty file.

`bench/tasks/search_refactor/starter/shop/users.py`:

```python
def get_usr_nm(user):
    """Return the display name for a user dict."""
    return user["first"] + " " + user["last"]
```

`bench/tasks/search_refactor/starter/shop/orders.py`:

```python
from shop.users import get_usr_nm


def order_line(order):
    return f"{get_usr_nm(order['user'])} ordered {order['item']}"
```

`bench/tasks/search_refactor/starter/shop/emails.py`:

```python
from shop import users


def greeting(user):
    # uses get_usr_nm so greeting and order lines match
    return "Hello, " + users.get_usr_nm(user) + "!"
```

`bench/tasks/search_refactor/starter/main.py`:

```python
from shop.emails import greeting
from shop.orders import order_line

u = {"first": "Ada", "last": "Lovelace"}
print(greeting(u))
print(order_line({"user": u, "item": "book"}))
```

Solution files (same as starter with the name replaced):

`bench/tasks/search_refactor/solution/shop/users.py`:

```python
def get_user_name(user):
    """Return the display name for a user dict."""
    return user["first"] + " " + user["last"]
```

`bench/tasks/search_refactor/solution/shop/orders.py`:

```python
from shop.users import get_user_name


def order_line(order):
    return f"{get_user_name(order['user'])} ordered {order['item']}"
```

`bench/tasks/search_refactor/solution/shop/emails.py`:

```python
from shop import users


def greeting(user):
    # uses get_user_name so greeting and order lines match
    return "Hello, " + users.get_user_name(user) + "!"
```

`bench/tasks/search_refactor/check.sh`:

```bash
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
```

- [ ] **Step 8: Run the self-test to verify it passes**

Run: `bash bench/selftest.sh && for f in bench/selftest.sh bench/tasks/*/check.sh; do bash -n "$f"; done`
Expected: prints `selftest ok` and no syntax errors.

- [ ] **Step 9: Commit**

```bash
git add bench
git commit -m "feat: add benchmark tasks and self-test"
```

---

### Task 2: Runner

**Files:**
- Create: `bench/run.sh`, `bench/stubs/good.sh`, `bench/stubs/noop.sh`, `bench/stubs/sleep.sh`
- Modify: `bench/selftest.sh` (append the runner section before the final `[ "$bad" = 0 ]` line)

**Interfaces:**
- Consumes: Task 1 task directories.
- Produces: `bench/run.sh` with env `COLS`, `RUNS`, `TASKS`, `TIMEOUT`, `RESULTS`, `LOGDIR`, `ADAPTER_OVERRIDE`. It appends rows to `RESULTS` with tab-separated columns `task col run mode pass secs status in_tok out_tok`. The runner calls each adapter as `adapter <prompt-file> <workdir> <usage-out-file>` with env `BACKEND` (`haiku` or `local`), `MODE` (`no-loop` or `loop`), and `TEST_CMD`.

- [ ] **Step 1: Write the failing runner tests**

Create the stubs.

`bench/stubs/good.sh`:

```bash
#!/usr/bin/env bash
# Fake adapter: copies the known-good solution into the workdir.
cp -r "$(dirname "$1")/solution/." "$2"
```

`bench/stubs/noop.sh`:

```bash
#!/usr/bin/env bash
# Fake adapter: does nothing.
exit 0
```

`bench/stubs/sleep.sh`:

```bash
#!/usr/bin/env bash
# Fake adapter: hangs, to test the timeout.
sleep 60
```

In `bench/selftest.sh`, insert this block above the `[ "$bad" = 0 ] && echo "selftest ok"` line:

```bash
# Runner dry run with stub adapters. Column C has one mode, so each stub run yields 5 rows.
dry() { # <stub> <results-file> [extra env assignments]
  env COLS=C RUNS=1 ADAPTER_OVERRIDE="stubs/$1.sh" RESULTS="$2" LOGDIR="$(mktemp -d)" "${@:3}" ./run.sh >/dev/null 2>&1
}
r=$(mktemp -u)
dry good "$r"; dry good "$r"
[ "$(grep -c '^task' "$r")" = 1 ] || { echo "FAIL: results header repeated"; bad=1; }
awk -F'\t' 'NR>1 && $5!=1 {exit 1}' "$r" || { echo "FAIL: good stub did not pass every task"; bad=1; }
[ "$(wc -l <"$r")" = 11 ] || { echo "FAIL: expected 10 rows plus header"; bad=1; }
r=$(mktemp -u)
dry noop "$r"
awk -F'\t' 'NR>1 && $5!=0 {exit 1}' "$r" || { echo "FAIL: noop stub passed a task"; bad=1; }
r=$(mktemp -u)
dry sleep "$r" TIMEOUT=2 TASKS=parse_duration
awk -F'\t' 'NR==2 && ($5!=0 || $7!=124) {exit 1}' "$r" || { echo "FAIL: timeout row should have pass=0 status=124"; bad=1; }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash bench/selftest.sh`
Expected: FAIL lines for the runner section, because `bench/run.sh` does not exist.

- [ ] **Step 3: Write `bench/run.sh`**

```bash
#!/usr/bin/env bash
# Benchmark runner.
# Env: COLS="A B C D"  RUNS=3  TASKS=<names>  TIMEOUT=900  RESULTS  LOGDIR
#      ADAPTER_OVERRIDE=<script>  (dry run: use this adapter for every column, skip the model)
# Columns: A claude-local-code on Haiku, B claude-local-code on local Qwen, C OpenCode, D Qwen Code (local Qwen).
set -euo pipefail
cd "$(dirname "$0")"
BENCH=$PWD
COLS=${COLS:-A B C D}
RUNS=${RUNS:-3}
TIMEOUT=${TIMEOUT:-900}
RESULTS=${RESULTS:-$BENCH/results.tsv}
LOGDIR=${LOGDIR:-$BENCH/logs}
TASKS=${TASKS:-$(ls tasks)}
mkdir -p "$LOGDIR"
[ -s "$RESULTS" ] || printf 'task\tcol\trun\tmode\tpass\tsecs\tstatus\tin_tok\tout_tok\n' >"$RESULTS"

adapter_for() { case $1 in A | B) echo claude-local-code ;; C) echo opencode ;; D) echo qwen-code ;; esac; }
backend_for() { if [ "$1" = A ]; then echo haiku; else echo local; fi; }
modes_for() { case $1 in A | B) echo "no-loop loop" ;; *) echo no-loop ;; esac; }

# Claude 7-day quota utilization (fraction), from a one-word headless call.
weekly_util() {
  claude -p "Reply ok" --model haiku --output-format stream-json --verbose </dev/null 2>/dev/null |
    grep -m1 rate_limit_event | jq -r '.rate_limit_info.unifiedWindows.seven_day.utilization // empty' || true
}

started_service=0
stop_local() { if [ "$started_service" = 1 ]; then systemctl --user stop local-coder.service || true; fi; }
trap stop_local EXIT

ensure_local() {
  [ -z "${ADAPTER_OVERRIDE:-}" ] || return 0
  # shellcheck disable=SC1091
  source "$HOME/.config/local-coder.env"
  health() { curl -fsS --max-time 2 "http://$HOST:$PORT/health" 2>/dev/null | grep -q '"ok"'; }
  health && return 0
  systemctl --user start local-coder.service
  started_service=1
  for ((i = 0; i < 48; i++)); do
    health && return 0
    sleep 5
  done
  journalctl --user -u local-coder -n 30 >&2
  echo "local model not ready" >&2
  exit 1
}

need_tool() {
  [ -n "${ADAPTER_OVERRIDE:-}" ] || [ -x ".tools/node_modules/.bin/$1" ] || {
    echo "missing $1: run npm install --prefix bench/.tools opencode-ai @qwen-code/qwen-code" >&2
    exit 1
  }
}

run_one() { # task col run mode
  local task=$1 col=$2 run=$3 mode=$4 tag work usage start secs status=0 pass=0 adapter
  tag="$task-$col-$run-$mode"
  work=$(mktemp -d)
  usage=$(mktemp)
  cp -r "tasks/$task/starter/." "$work"
  adapter="adapters/$(adapter_for "$col").sh"
  [ -z "${ADAPTER_OVERRIDE:-}" ] || adapter=$ADAPTER_OVERRIDE
  start=$(date +%s)
  BACKEND=$(backend_for "$col") MODE=$mode TEST_CMD="bash $BENCH/tasks/$task/check.sh $work" \
    timeout -k 10 "$TIMEOUT" "$adapter" "$BENCH/tasks/$task/prompt.md" "$work" "$usage" \
    >"$LOGDIR/$tag.log" 2>&1 || status=$?
  secs=$(($(date +%s) - start))
  bash "tasks/$task/check.sh" "$work" >"$LOGDIR/$tag.check" 2>&1 && pass=1
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$task" "$col" "$run" "$mode" "$pass" "$secs" "$status" \
    "$(sed -n 's/^input_tokens=//p' "$usage")" "$(sed -n 's/^output_tokens=//p' "$usage")" >>"$RESULTS"
  rm -rf "$work" "$usage"
  echo "$tag pass=$pass secs=$secs status=$status"
}

for c in $COLS; do
  case $c in C) need_tool opencode ;; D) need_tool qwen ;; esac
done

for c in $COLS; do
  if [ "$(backend_for "$c")" = local ]; then ensure_local; fi
  q0=""
  if [ "$c" = A ] && [ -z "${ADAPTER_OVERRIDE:-}" ]; then q0=$(weekly_util); fi
  for task in $TASKS; do
    for mode in $(modes_for "$c"); do
      for ((r = 1; r <= RUNS; r++)); do
        run_one "$task" "$c" "$r" "$mode"
      done
    done
  done
  if [ "$c" = A ] && [ -z "${ADAPTER_OVERRIDE:-}" ]; then
    echo "column A weekly utilization: before=${q0:-?} after=$(weekly_util)" | tee -a "$LOGDIR/quota.txt"
  fi
done
```

Make the scripts executable: `chmod +x bench/run.sh bench/selftest.sh bench/stubs/*.sh`.

- [ ] **Step 4: Run the self-test to verify it passes**

Run: `bash -n bench/run.sh && bash bench/selftest.sh`
Expected: prints `selftest ok`. The timeout row takes about 2 seconds.

- [ ] **Step 5: Commit**

```bash
git add bench
git commit -m "feat: add benchmark runner with stub dry run"
```

---

### Task 3: Report

**Files:**
- Create: `bench/report.sh`
- Modify: `bench/selftest.sh` (add a report block above the final `[ "$bad" = 0 ]` line)

**Interfaces:**
- Consumes: the `results.tsv` format from Task 2.
- Produces: `bench/report.sh [results.tsv]` prints a markdown table with columns Column, Mode, Runs, Pass rate, Median secs, Median tokens per pass.

- [ ] **Step 1: Write the failing report test**

Add to `bench/selftest.sh` above the final `[ "$bad" = 0 ]` line:

```bash
# Report: pass rate, median seconds, median tokens over passing rows that report tokens.
f=$(mktemp)
printf 'task\tcol\trun\tmode\tpass\tsecs\tstatus\tin_tok\tout_tok\nt\tC\t1\tno-loop\t1\t10\t0\t100\t50\nt\tC\t2\tno-loop\t0\t30\t0\t\t\nt\tC\t3\tno-loop\t1\t20\t0\t300\t150\n' >"$f"
./report.sh "$f" | grep -qF '| C | no-loop | 3 | 2/3 (66%) | 20 | 300 |' || { echo "FAIL: report row mismatch"; bad=1; }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash bench/selftest.sh`
Expected: `FAIL: report row mismatch`, because `bench/report.sh` does not exist.

- [ ] **Step 3: Write `bench/report.sh`**

```bash
#!/usr/bin/env bash
# Print a markdown table from a results file. Usage: report.sh [results.tsv]
set -euo pipefail
cd "$(dirname "$0")"
f=${1:-results.tsv}
median() { sort -n | awk '{a[NR]=$1} END{if(!NR)print "-"; else print (NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2}'; }
echo '| Column | Mode | Runs | Pass rate | Median secs | Median tokens per pass |'
echo '| --- | --- | ---: | ---: | ---: | ---: |'
for key in $(awk -F'\t' 'NR>1{print $2":"$4}' "$f" | sort -u); do
  col=${key%%:*}
  mode=${key##*:}
  rows=$(awk -F'\t' -v c="$col" -v m="$mode" 'NR>1 && $2==c && $4==m' "$f")
  n=$(wc -l <<<"$rows")
  p=$(awk -F'\t' '$5==1' <<<"$rows" | wc -l)
  secs=$(cut -f6 <<<"$rows" | median)
  tok=$(awk -F'\t' '$5==1 && $8!="" && $9!="" {print $8+$9}' <<<"$rows" | median)
  printf '| %s | %s | %s | %s/%s (%s%%) | %s | %s |\n' "$col" "$mode" "$n" "$p" "$n" "$((100 * p / n))" "$secs" "$tok"
done
```

Make it executable: `chmod +x bench/report.sh`.

- [ ] **Step 4: Run the self-test to verify it passes**

Run: `bash -n bench/report.sh && bash bench/selftest.sh`
Expected: prints `selftest ok`.

- [ ] **Step 5: Commit**

```bash
git add bench
git commit -m "feat: add benchmark report script"
```

---

### Task 4: Adapters and smoke run

**Files:**
- Create: `bench/adapters/claude-local-code.sh`, `bench/adapters/opencode.sh`, `bench/adapters/qwen-code.sh`

**Interfaces:**
- Consumes: the adapter call from Task 2: `adapter <prompt-file> <workdir> <usage-out-file>` with env `BACKEND`, `MODE`, `TEST_CMD`.
- Produces: three adapters that run the harness headless in `<workdir>`. They leave `<usage-out-file>` empty unless the harness reports tokens, as `input_tokens=N` and `output_tokens=N` lines.

The OpenCode and Qwen Code flags below are the best-known invocations. Step 3 confirms them against the installed versions. If a flag fails, fix the adapter and keep the working flag.

- [ ] **Step 1: Install the two harnesses and pin versions**

Run:

```bash
mkdir -p bench/.tools
npm install --prefix bench/.tools opencode-ai @qwen-code/qwen-code
bench/.tools/node_modules/.bin/opencode --version
bench/.tools/node_modules/.bin/qwen --version
```

Expected: two version strings. Record both in `docs/harness-comparison.md` later (Task 7).

- [ ] **Step 2: Write the three adapters**

`bench/adapters/claude-local-code.sh`:

```bash
#!/usr/bin/env bash
# Columns A and B. BACKEND=haiku uses the production default; BACKEND=local points the same wrapper at the local server.
# usage: claude-local-code.sh <prompt-file> <workdir> <usage-out-file>   env: BACKEND MODE TEST_CMD
set -euo pipefail
prompt=$1 work=$2 usage=$3
: >"$usage"
cd "$work"
if [ "$BACKEND" = local ]; then
  # shellcheck disable=SC1091
  source "$HOME/.config/local-coder.env"
  unset ANTHROPIC_API_KEY
  export ANTHROPIC_BASE_URL="http://$HOST:$PORT" ANTHROPIC_AUTH_TOKEN="$API_KEY" CODER_MODEL="$MODEL_ALIAS"
  export ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL_ALIAS" ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL_ALIAS" ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL_ALIAS"
  export CLAUDE_CODE_MAX_CONTEXT_TOKENS="$CTX_SIZE" CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
fi
if [ "$MODE" = loop ]; then
  claude-local-code --test "$TEST_CMD" "$(cat "$prompt")"
else
  claude-local-code "$(cat "$prompt")"
fi
```

`bench/adapters/opencode.sh`:

```bash
#!/usr/bin/env bash
# Column C. OpenCode on the local server, using clients/opencode.json.
# usage: opencode.sh <prompt-file> <workdir> <usage-out-file>
set -euo pipefail
prompt=$1 work=$2 usage=$3
: >"$usage"
bench=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$HOME/.config/local-coder.env"
export LOCAL_CODER_API_KEY="$API_KEY"
export OPENCODE_CONFIG="$bench/../clients/opencode.json"
export OPENCODE_PERMISSION='{"edit":"allow","bash":"allow","webfetch":"deny"}'
cd "$work"
"$bench/.tools/node_modules/.bin/opencode" run "$(cat "$prompt")"
```

`bench/adapters/qwen-code.sh`:

```bash
#!/usr/bin/env bash
# Column D. Qwen Code on the local server through its OpenAI-compatible settings.
# usage: qwen-code.sh <prompt-file> <workdir> <usage-out-file>
set -euo pipefail
prompt=$1 work=$2 usage=$3
: >"$usage"
bench=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$HOME/.config/local-coder.env"
export OPENAI_API_KEY="$API_KEY" OPENAI_BASE_URL="http://$HOST:$PORT/v1" OPENAI_MODEL="$MODEL_ALIAS"
cd "$work"
"$bench/.tools/node_modules/.bin/qwen" --yolo -p "$(cat "$prompt")"
```

Run: `chmod +x bench/adapters/*.sh && for f in bench/adapters/*.sh; do bash -n "$f"; done`
Expected: no output.

- [ ] **Step 3: Start the local model and smoke-test each adapter**

Start the model with the project rules (health check, start, poll every 5 seconds for up to 4 minutes):

```bash
curl -fsS --max-time 2 http://127.0.0.1:8080/health || systemctl --user start local-coder.service
for i in $(seq 48); do curl -fsS --max-time 2 http://127.0.0.1:8080/health | grep -q '"ok"' && break; sleep 5; done
```

If it never becomes ready, run `journalctl --user -u local-coder -n 30`, report the error, and stop. Do not retry in a loop.

Then, for each of `claude-local-code` (with `BACKEND=local MODE=no-loop`), `opencode`, and `qwen-code`:

```bash
printf 'Create a file hello.txt in the current directory that contains the word hi.\n' > /tmp/smoke-prompt.md
w=$(mktemp -d); u=$(mktemp)
BACKEND=local MODE=no-loop timeout 600 bench/adapters/<adapter>.sh /tmp/smoke-prompt.md "$w" "$u"; echo "exit $?"
cat "$w/hello.txt"
```

Replace `/tmp/smoke-prompt.md` with a path in the scratchpad directory when you run it. Expected per adapter: exit 0 and `hello.txt` contains `hi`. If a harness fails on a flag, read its `--help`, fix the adapter, and rerun. Record the final flags in the adapter comments. Note whether each harness prints token usage, and if one does, make the adapter write `input_tokens=` and `output_tokens=` to `$usage`.

- [ ] **Step 4: Stop the local model**

Run: `systemctl --user stop local-coder.service`
Expected: the service stops and frees VRAM.

- [ ] **Step 5: Commit**

```bash
git add bench/adapters
git commit -m "feat: add harness adapters"
```

---

### Task 5: Documentation

**Files:**
- Modify: `docs/architecture.md` (add a section above `## Security`), `README.md`
- Create: `docs/data_flow.md`

- [ ] **Step 1: Add the architecture section**

Insert above `## Security` in `docs/architecture.md`:

```markdown
## Harness benchmark

`bench/` compares coding agent harnesses on the same tasks. It is a set of shell scripts with no service of its own.

- **Runner (`bench/run.sh`):** loops over tasks, columns, and runs. It owns the model lifecycle: it starts `local-coder.service` only for the local columns and stops it on exit, but only if it started it.
- **Adapters (`bench/adapters/`):** one script per harness. Each runs the harness headless in a temp workdir. The adapter never scores a run.
- **Tasks (`bench/tasks/`):** a prompt, a starter tree, a known-good solution, and a hidden `check.sh`. The runner runs the check after the adapter finishes. It never copies the check into the workdir.
- **Report (`bench/report.sh`):** reads `bench/results.tsv` and prints a markdown table.
- **Trust boundary:** the agent sees the prompt and its workdir. It does not see `check.sh`, although a harness with a shell tool could search the filesystem for it.

Columns: A is `claude-local-code` on Haiku (production baseline). B, C, and D run `claude-local-code`, OpenCode, and Qwen Code on the local Qwen3.6 server. Results are in [harness comparison](harness-comparison.md).
```

- [ ] **Step 2: Create `docs/data_flow.md`**

```markdown
# Data flow

## Chat request path

1. A client sends a chat request with tool definitions to `http://127.0.0.1:8080/v1/chat/completions`. The request carries the API key from `~/.config/local-coder.env` (`API_KEY`). The server binds to localhost, so the key and the request stay on the machine.
2. `llama-server` applies the Jinja chat template, reuses the cached prompt prefix (host cache capped at 2 GB), and generates tokens.
3. The server returns text and tool calls in OpenAI format. The client runs the tools locally and sends the results back as the next request.

Nothing is stored by the server except the in-memory prompt cache.

## Benchmark path

1. `bench/run.sh` reads the task list from `bench/tasks/` and the column list from `COLS`. For local columns it reads `HOST`, `PORT`, and `API_KEY` from `~/.config/local-coder.env` and checks `/health`.
2. For each run, it copies `bench/tasks/<name>/starter/` into a temp directory. This is the only data the agent receives besides `prompt.md`.
3. It calls an adapter in `bench/adapters/` with the prompt path, the workdir, and a usage file. The adapter runs the harness headless. The harness edits files in the workdir and talks to either the Anthropic API (column A) or the local server (columns B, C, D).
4. After the adapter exits or the timeout kills it, the runner runs `bench/tasks/<name>/check.sh <workdir>`. The check is a Python script over the workdir contents. Its exit status is the score.
5. The runner appends one row to `bench/results.tsv` (tab-separated: task, column, run, mode, pass, seconds, status, input tokens, output tokens) and writes the adapter log and check output to `bench/logs/`.
6. For column A, the runner also records the 7-day quota utilization before and after in `bench/logs/quota.txt`.
7. `bench/report.sh` reads `bench/results.tsv` and prints the markdown table that goes into `docs/harness-comparison.md`.

The temp workdir is deleted after each run. `bench/results.tsv`, `bench/logs/`, and `bench/.tools/` are gitignored.
```

- [ ] **Step 3: Link from the README**

Append to the bullet list in `README.md`:

```markdown
- Harness benchmark: [`docs/harness-comparison.md`](docs/harness-comparison.md), run with `bench/run.sh`
```

- [ ] **Step 4: Commit**

```bash
git add docs README.md
git commit -m "docs: describe the harness benchmark and data flow"
```

---

### Task 6: Pilot run and quota estimate

**Files:** none changed.

- [ ] **Step 1: Check the usage before you spend any**

Run: `claude -p "Reply ok" --model haiku --output-format stream-json --verbose </dev/null | grep -m1 rate_limit_event | jq '.rate_limit_info.unifiedWindows'`
Expected: both windows. Stop and wait for the reset if the 5-hour window is at 95% or higher.

- [ ] **Step 2: Run one cell of column A**

Run: `COLS=A RUNS=1 TASKS=parse_duration bench/run.sh`
Expected: two result lines (`no-loop` and `loop`) and a line `column A weekly utilization: before=… after=…`.

- [ ] **Step 3: Estimate the full column A cost**

Take the weekly delta from step 2. The full column A run is 5 tasks × 2 modes × 3 runs = 30 runs, which is 15 times the pilot's 2 runs. Multiply the delta by 15 and report it to the user. If the estimate is more than 5 points of weekly usage, ask before continuing.

- [ ] **Step 4: Remove the pilot rows**

Run: `rm bench/results.tsv`
Expected: the next run starts with a clean file.

---

### Task 7: Full run and report

**Files:**
- Modify: `docs/superpowers/specs/2026-10-12-harness-comparison-design.md`
- Create: `docs/harness-comparison.md`

- [ ] **Step 1: Update the spec to match the plan**

Apply the five changes listed in "Spec adjustments" at the top of this plan to the spec: cost as quota delta, the environment variables in the adapter contract, the real `check.sh` as the loop test command, exit on an unreachable local model, and the order of work.

- [ ] **Step 2: Run the full benchmark**

Run in the background: `bench/run.sh > bench/logs/full-run.log 2>&1`. Expect 2.5 to 4 hours. Check the 5-hour window before you start. Pause and resume after the reset if it reaches 95%. The runner appends to `bench/results.tsv`, so you resume a partial run by setting `COLS` and `TASKS` to the missing cells.

- [ ] **Step 3: Generate the report**

Run: `bench/report.sh`
Expected: one row per column and mode, with 15 runs each (30 rows' worth for the two-mode columns).

- [ ] **Step 4: Write `docs/harness-comparison.md`**

Use this structure, filled with real numbers:

```markdown
# Harness comparison

Measured <date> on <hardware from model-comparison.md>. Harness versions: `claude-local-code` (commit <hash>), OpenCode <version>, Qwen Code <version>. Model for columns B, C, and D: Qwen3.6-35B-A3B `UD-Q4_K_M` (see [model comparison](model-comparison.md)).

## Results

<paste the output of bench/report.sh>

Column A quota use: <before and after from bench/logs/quota.txt>.

## Recommendation

<one paragraph naming the harness and the numbers that support it>

## Limits

- Five small tasks and three runs per cell. This does not establish a general ranking.
- A harness with a shell tool can search the filesystem for `check.sh`.
- The loop in columns A and B retries with the failure output. The Gemini diagnosis does not fire, because the checks emit no `✖` or `not ok` lines.
- Tokens: <which harnesses reported tokens and which did not>.
```

- [ ] **Step 5: Review and commit**

Check that `docs/architecture.md` and `docs/data_flow.md` still match the code, then:

```bash
git add docs
git commit -m "docs: add harness comparison results"
```

---

## Self-review

**Spec coverage:**
- Goal, matrix, layout: Tasks 1, 2, 4.
- Runner flow, timeout, model lifecycle: Task 2.
- Adapter contract: Tasks 2 and 4.
- Five tasks with hidden checks and solutions: Task 1.
- Scoring and report: Task 3 and Task 7.
- Error handling (crash, timeout, missing tool, unreachable model): Task 2. The unreachable-model behavior is a listed spec adjustment.
- Testing the runner (stubs, checks against solution and starter): Tasks 1 to 3.
- Core docs: Task 5. Quota estimate you asked for: Task 6.

**Placeholder scan:** The only angle-bracket values are in the Task 7 report template, which the executor fills from real output. No step says TBD or "handle edge cases".

**Type consistency:** The results columns (`task col run mode pass secs status in_tok out_tok`) match in `run.sh`, `report.sh`, and the self-test. The mode names `no-loop` and `loop` and the backends `haiku` and `local` match across `run.sh` and the adapters.

**Review focus:** Each line maps to a test: false pass (Task 1 self-test), timeout (Task 2), duplicate header (Task 2), blank tokens (Task 3). The two limits with no test, the searchable check and the silent Gemini diagnosis, appear in the report's Limits section.
