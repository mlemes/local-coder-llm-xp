# Harness comparison

This report compares eight coding agent harnesses on the same five tasks, with three models. You can reproduce every number with the scripts in `bench/`.

## Result

Each cell is the pass rate over 15 runs (5 tasks, 3 runs each) and the median wall time. The hidden `check.sh` scores each run, never the agent.

| Harness | Haiku | Luna | Local Qwen3.6-35B-A3B |
| --- | --- | --- | --- |
| `claude-local-code`, with loop | 15/15, 8 s | 15/15, 16 s | 15/15, 54 s |
| `claude-local-code`, no loop | 15/15, 6 s | 15/15, 15 s | 8/15, 40 s |
| Codex CLI | 15/15, 14 s | 14/15, 17 s | 12/15, 76 s |
| Deep Agents Code | 15/15, 13 s | 15/15, 19 s | 4/15, 109 s |
| DeepSeek Harness | 15/15, 8 s | 15/15, 17 s | 11/15, 75 s |
| Hermes | 15/15, 13 s | 15/15, 23 s | 10/15, 44 s |
| OpenClaw | 15/15, 26 s | 15/15, 34 s | 9/15, 147 s |
| OpenCode | 15/15, 9 s | 15/15, 18 s | 10/15, 157 s |
| Qwen Code | 15/15, 18 s | 15/15, 21 s | 12/15, 86 s |

The raw table is `bench/matrix.tsv`. Regenerate it with `bench/matrix.sh --tsv > bench/matrix.tsv`.

## What the numbers say

- **A strong model hides the harness.** Haiku and Luna pass 299 of 300 runs across all eight harnesses. On these tasks, only speed separates the harnesses.
- **A weak model exposes the harness.** With the same local Qwen model, pass rates range from 4/15 to 12/15 without a loop. Codex CLI and Qwen Code lead at 12/15. Deep Agents Code trails at 4/15.
- **A test loop beats every harness choice on the weak model.** `claude-local-code` with its loop reaches 15/15 on Qwen. The loop re-runs the hidden check as its test command, so this number is an upper bound. Without the loop, the same wrapper scores 8/15.
- **Speed follows overhead, not model.** Haiku through `claude-local-code` takes 6 s. OpenClaw takes 26 s for the same passing result.

## Harnesses and versions

| Column | Harness | Version | Default model |
| --- | --- | --- | --- |
| A, B | `claude-local-code` (headless Claude Code, test loop, Gemini diagnosis) | Claude Code 2.1.296 | Haiku (A), local Qwen (B) |
| C | OpenCode | 1.19.0 | local Qwen |
| D | Qwen Code | 0.25.1 | local Qwen |
| E | DeepSeek Harness (`dsh`) | not recorded | local Qwen |
| F | Deep Agents Code (`dcode`) | 0.1.84 | local Qwen |
| G | Hermes Agent | 0.21.7 | local Qwen |
| H | OpenClaw | 2026.10.2 | local Qwen |
| I | Codex CLI | 0.160.1 | Luna on the ChatGPT login |

Luna is `gpt-6-luna`. Haiku is `claude-haiku-5-5`. The local model is Qwen3.6-35B-A3B `UD-Q4_K_M` on `llama-server`.

## Tasks

Each task has a prompt, a starter tree, a known-good solution, and a hidden check with edge cases the prompt does not spell out.

| Task | Type |
| --- | --- |
| `parse_duration` | New file from a spec |
| `merge_intervals` | New file from a spec |
| `fix_bug` | Fix a bug in existing code |
| `two_file_edit` | Change a signature and update its caller |
| `search_refactor` | Rename a symbol across several files |

## How the model reaches each harness

- **Local Qwen:** every harness talks to `llama-server` on `127.0.0.1:8080`. Deep Agents Code and Qwen Code go through `bench/adapters/fix_empty_content.py` because `llama-server` mangles two things in the Responses API: empty reasoning items, and tool arguments that land in the reasoning item.
- **Haiku and Luna:** the harnesses use the vendor API with keys from `bench/.keys.env`. Codex CLI on Haiku and `claude-local-code` on Luna go through a local LiteLLM proxy (`bench/adapters/_litellm.sh`) that translates the Responses and Messages protocols.
- **Luna on Codex CLI:** this cell uses the ChatGPT login, not an API key.
- **Anthropic subscription tokens:** Anthropic bars them in third-party harnesses. Only `claude-local-code`, which runs the official `claude` binary, uses the subscription. Every other Haiku cell uses an API key.

## Limits

- **Small sample.** Five tasks and three runs per task. The report claims no statistical significance. One failed run moves a cell by 7 points.
- **Small tasks.** Each task takes one prompt and a few files. The results do not rank harnesses on large repositories or long sessions.
- **Loop runs are easier.** The `claude-local-code` loop gets the hidden check as its test command. Compare it with the no-loop cells only as an upper bound.
- **Qwen Code on Luna runs with reasoning off.** OpenAI rejects `reasoning_effort` together with tools on chat completions, so the proxy sets it to `none` for that cell.
- **Deep Agents Code on Qwen runs through the bench proxy.** Its 4/15 may reflect the proxy fix and not only the harness.
- **Tokens and cost are blank for most harnesses.** Few harnesses print usage in headless mode. Codex CLI reports total tokens only.
- **Money.** The Haiku and Luna API cells cost money. The run did not record spend per cell.
- **Timeout.** Each run has a 900 s limit. A timeout counts as a failure.
- **Wall time includes startup.** A harness with a slow cold start looks slower than its model.

## Rulings

Decisions made while building the benchmark, with the cost if wrong.

- OpenCode runs with `run --auto`. The bare `run` blocks on permission prompts. Cost if wrong: OpenCode rows fail.
- Qwen Code takes the prompt as a positional argument. `-p` is deprecated in 0.25.1. Cost if wrong: one flag swap.
- OpenClaw wipes its fake `HOME` each run and onboards with `--skip-health --workspace "$work" --skip-bootstrap`. The default workspace sits outside the task directory. Cost if wrong: OpenClaw rows fail or see a different prompt.
- The `claude-local-code` retry loop had a bug: `grep` with no match ended the loop after the first failure under `set -euo pipefail`. The fix adds `|| true`. After it, the loop result on Qwen moved from 9/15 to 15/15.

## Recommendation

- **Keep `claude-local-code` with Haiku** for daily work. It is the fastest cell with a perfect score.
- **Use the loop whenever the model is weak.** On local Qwen, a test command with retries is worth more than any harness swap.
- **If you must run local Qwen without a loop,** pick Codex CLI or Qwen Code.
- **Do not pick a harness from a blog ranking.** Rankings from secondary sources were not checked here. Run your own tasks.

## Reproduce

1. Install the harnesses into `bench/.tools/` and `bench/.home/` (each adapter prints its install hint when a tool is missing).
2. Put `ANTHROPIC_API_KEY` and `OPENAI_API_KEY` in `bench/.keys.env`. The file is gitignored.
3. Run `bash bench/selftest.sh`. It proves each check fails on the bare starter and passes on the solution.
4. Run `COLS="A C@luna I" RUNS=3 bench/run.sh`.
5. Run `bench/matrix.sh` for the table.
