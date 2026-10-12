# Harness comparison design

Compare three coding agent harnesses on the same tasks, and report which one fits this project best.

## Goal

Pick the best harness for this project by running identical tasks through each one and scoring the results with checks the agent never sees.

The candidates are:

- `claude-local-code`: the current wrapper. It runs headless Claude Code, then adds a test loop and Gemini diagnosis.
- OpenCode: provider-agnostic, already configured in `clients/opencode.json`.
- Qwen Code: an open harness that the Qwen models are tuned for.

## Scope

In scope:

- A shell-only benchmark runner under `bench/`.
- Five tasks, each with a hidden check.
- A results file and a short report in `docs/harness-comparison.md`.
- Updates to `docs/architecture.md` and a new `docs/data_flow.md`, in the same change as the code.

Out of scope:

- Docker, Python services, or an external benchmark framework. `AGENTS.md` forbids them.
- Public benchmark subsets such as SWE-bench Lite or Terminal-Bench.
- Harnesses beyond the three listed (Aider, Cline, Pi).
- Changing the serving stack or the model.

## Constraints

- The repository stays small: shell scripts, plain files, no new services.
- The local model starts only for the local columns and stops when the run ends. The GPU hosts one model at a time.
- Install `opencode` and `qwen-code` into `bench/.tools/`, which is gitignored. Do not install them globally.
- Static checks use `bash -n` and `shellcheck`. Do not start the service in static checks.
- Never trust a self-reported pass. The runner runs every check itself.

## Comparison matrix

Each task runs three times per column.

| Column | Harness | Backend model |
| --- | --- | --- |
| A | `claude-local-code` | Claude Haiku (production baseline) |
| B | `claude-local-code` | Local Qwen3.6-35B-A3B |
| C | OpenCode | Local Qwen3.6-35B-A3B |
| D | Qwen Code | Local Qwen3.6-35B-A3B |

Columns B, C, and D isolate the harness effect because the model is the same. Column A shows what the harness does on the model you use today.

The matrix is 5 tasks × 4 columns × 3 runs, or 60 runs. At about 3 to 5 minutes per local run, the 45 local runs take roughly 2.5 to 4 hours.

## Layout

```text
bench/
  run.sh                      # runner: tasks × columns × runs
  adapters/
    claude-local-code.sh      # columns A and B
    opencode.sh               # column C
    qwen-code.sh              # column D
  tasks/<name>/
    prompt.md                 # task text given to the agent
    starter/                  # files copied into the agent's workdir
    check.sh                  # hidden check, run by the runner only
  results.tsv                 # one row per run (gitignored until reviewed)
  .tools/                     # npm installs (gitignored)
```

## Runner flow

For each task, column, and run number, `run.sh` does the following:

1. Copies `tasks/<name>/starter/` into a fresh temp directory.
2. Calls the adapter with the prompt path and the workdir. The adapter prints nothing the runner depends on, apart from its exit status and a usage file.
3. Records wall time around the adapter call.
4. Runs `tasks/<name>/check.sh <workdir>` outside the agent's reach. The check is never copied into the workdir.
5. Appends one row to `results.tsv`.

Columns A and B run the wrapper twice per task:

- Attempt 1 without `--test`. This measures the harness without the loop.
- A full run with `--test "<check>"`. This measures the harness with the loop.

The `--test` command for the loop is the real `check.sh`. The wrapper shows the agent only the filtered failure lines. The runner re-runs the check afterward and scores that result.

## Adapter contract

An adapter is a shell script with this interface:

```text
adapters/<name>.sh <prompt-file> <workdir> <usage-out-file>
```

- It runs the harness non-interactively in `<workdir>` with the prompt from `<prompt-file>`.
- It writes `input_tokens`, `output_tokens`, and `cost_usd` to `<usage-out-file>` as `key=value` lines, for each value the harness reports. It leaves a value out when the harness does not report it.
- It exits non-zero only when the harness crashes. A failed task is not a crash.
- Backend selection for the Qwen columns uses the existing environment from `~/.config/local-coder.env` (`HOST`, `PORT`, `API_KEY`, `MODEL_ALIAS`).
- The runner also sets `BACKEND` (`haiku` or `local`), `MODE` (`no-loop` or `loop`), and `TEST_CMD` in the adapter's environment.

## Model lifecycle

1. The runner runs column A first, while the GPU is free.
2. Before columns B, C, and D, it checks `http://127.0.0.1:8080/health`. If the check fails, it runs `systemctl --user start local-coder.service` and polls every 5 seconds for up to 4 minutes.
3. If the service never becomes ready, the runner prints `journalctl --user -u local-coder -n 30` and exits. It does not retry in a loop.
4. An `EXIT` trap stops the service with `systemctl --user stop local-coder.service`, but only if the runner started it.

## Tasks

| Task | Type | What it checks |
| --- | --- | --- |
| `parse_duration` | New file from spec | Parsing, units, and error cases |
| `merge_intervals` | New file from spec | Sorting, overlap, and input immutability |
| `fix_bug` | Edit existing code | Locate and fix a bug in a provided module |
| `two_file_edit` | Multi-file edit | Change a function signature and update its caller |
| `search_refactor` | Search-heavy refactor | Rename a symbol used across several files |

Rules for every task:

- The prompt states the goal and names the files. It never includes the check.
- `check.sh` exits 0 on pass. It prints the failing case on failure, to `stderr`.
- Each check includes edge cases the prompt does not spell out. The first two tasks reuse the independent checks from `docs/model-comparison.md`.

## Scoring and report

Each row in `results.tsv` has: task, column, run, attempt mode (`no-loop` or `loop`), pass (0 or 1), wall seconds, input tokens, output tokens, and cost.

The report in `docs/harness-comparison.md` shows, per column:

- Pass rate on the first attempt (no loop) and final pass rate (with loop). Only columns A and B have a loop.
- Median wall time.
- Median tokens per passing run.
- Weekly quota used by column A, from the 7-day utilization before and after the column. The wrapper prints plain text, so it exposes no per-run cost. Local runs cost no API money.

The report ends with a recommendation and states which numbers a harness did not report.

## Error handling

- A harness crash or a timeout counts as a failed run. The row keeps the exit status.
- The per-run timeout is 15 minutes. The runner kills the process group when it expires.
- A missing tool in `bench/.tools/` stops the runner before any run starts, with the install command.
- If the local model never becomes ready, the runner prints the journal and exits. It does not mark rows `skipped`.

## Testing the runner

- `bash -n` and `shellcheck` on every script.
- A dry run with a stub adapter: one that copies a known-good solution passes every check, and one that does nothing fails every check. This proves the checks fail on empty work and pass on correct work.
- Each `check.sh` runs against a known-good solution and against the unchanged starter before any real run.

## Risks and open items

- Qwen Code and OpenCode headless flags: the smoke run (plan task 4) confirmed OpenCode 1.19.0 with `run --auto` and Qwen Code 0.25.1 with `--yolo` and a positional prompt. Neither prints token usage by default, so the token columns stay blank.
- Token and cost fields may be blank for some harnesses. The report states which ones.
- Three runs per cell is a small sample. The report shows per-run results next to medians, and it does not claim statistical significance.
- Results describe five small tasks. They do not establish a general ranking.
- Source rankings of these harnesses come from secondary blogs and are unverified. This benchmark replaces them with your own measurements.
