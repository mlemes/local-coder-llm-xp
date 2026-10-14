# A good harness closes the gap between a free model and a hosted one

Benchmarks of coding agents mostly vary the model. The program wrapped around the model, the harness, gets treated as plumbing. This experiment inverts that. It holds the model fixed, swaps the harness, and asks when the choice changes the result.

The short answer: with a strong model, almost never. With a weak model, a lot. And one specific harness feature moved a local model that costs nothing per token to the same pass rate as two hosted models.

## Models

Three models ran in every harness.

| Role | Model | Exact identifier | How it ran |
| --- | --- | --- | --- |
| Hosted, small | Claude Haiku 5.5 | `claude-haiku-5-5` | Anthropic API |
| Hosted, large | OpenAI Luna | `gpt-6-luna` | OpenAI API, or the ChatGPT login for Codex CLI |
| Local | Qwen3.6-35B-A3B | `Qwen3.6-35B-A3B-UD-Q4_K_M.gguf` (22,134,528,992 bytes, SHA256 `ac0e2c1189e055faa36eff361580e79c5bd6f8e76bffb4ce547f167d53e31a61`) | `llama-server` from `llama.cpp` build b11559, 64K context, temperature 0.6, top-p 0.95, min-p 0, reasoning budget 2048 |

Qwen3.6-35B-A3B is a mixture-of-experts model with about 3 billion active parameters. It ran on one RTX 3070 with 8 GB of VRAM and 30 GB of RAM, at 35 to 40 tokens per second. It has no per-token cost.

## Harnesses

| Harness | Version |
| --- | --- |
| `claude-local-code` (headless Claude Code with an optional test-and-retry loop) | Claude Code 2.1.296 |
| OpenCode | 1.19.0 |
| Qwen Code | 0.25.1 |
| Deep Agents Code | 0.1.84 |
| Hermes Agent | 0.21.7 |
| OpenClaw | 2026.10.2 |
| Codex CLI | 0.160.1 |
| DeepSeek Harness | version not recorded |

## Tasks and scoring

Five small tasks, each with a hidden check that the agent never sees:

- Write `parse_duration` from a spec.
- Write `merge_intervals` from a spec.
- Fix a bug in a discount calculation.
- Change a function signature and update its caller.
- Rename a function across a small project.

The runner copies starter files into a temp directory, calls the harness headless, and runs the check itself. The checks include edge cases the prompt does not mention. A self-reported pass counts for nothing. Each cell is five tasks times three runs, 15 runs, and the full matrix is 405 runs.

## With a strong model, the harness barely matters

Haiku 5.5 and Luna passed 299 of 300 runs across all eight harnesses. The single miss was Codex CLI on Luna.

Speed was the only difference. The `claude-local-code` wrapper on Haiku took a median of 6 seconds per task. OpenClaw took 26 seconds for the same correct result. On short tasks, a capable model carries the harness. Choosing among these eight is a question of latency and ergonomics.

## With a weak model, the harness decides the outcome

Qwen3.6 on the same server and the same tasks, no retry loop, passed between 4 and 12 of 15 runs depending on the harness:

| Harness | Passed | Median time |
| --- | --- | --- |
| Codex CLI | 12/15 | 76 s |
| Qwen Code | 12/15 | 86 s |
| DeepSeek Harness | 11/15 | 75 s |
| OpenCode | 10/15 | 157 s |
| Hermes | 10/15 | 44 s |
| OpenClaw | 9/15 | 147 s |
| `claude-local-code`, no loop | 8/15 | 40 s |
| Deep Agents Code | 4/15 | 109 s |

Same weights, same sampling settings, a threefold spread. Two things explain most of it.

First, the tasks are not equally hard for this model. Across the eight no-loop harnesses, 120 local runs split like this:

| Task | Passed |
| --- | --- |
| `fix_bug` | 22/24 |
| `search_refactor` | 21/24 |
| `two_file_edit` | 21/24 |
| `parse_duration` | 12/24 |
| `merge_intervals` | 0/24 |

`merge_intervals` failed in every harness. At least 19 of the 24 failures stop at the same assertion: input given as lists, `[[1, 2], [4, 5]]`, must come back as the tuples `[(1, 2), (4, 5)]`. The prompt says to return tuples but never shows list input. The agents wrote code, tested the cases the prompt mentioned, reported success, and stopped. A harness that only executes tool calls cannot tell the model something the model does not already check, so no harness fixed it.

Second, the harnesses differ in how well they work with a local server. Deep Agents Code needed a proxy to repair `llama-server` Responses API output and still scored lowest. This benchmark did not diagnose the remaining spread between the middle harnesses.

## A feedback loop recovers the missing runs

The `claude-local-code` wrapper can run a test command after each edit, pass the failing lines back to the agent, and let it retry. With the loop on, Qwen3.6 scored 15/15, including 3/3 on `merge_intervals`. With the loop off, the same wrapper and model scored 8/15.

| Configuration | Passed | Median time |
| --- | --- | --- |
| Qwen3.6, no loop | 8/15 | 40 s |
| Qwen3.6, loop | 15/15 | 54 s |
| Haiku 5.5, loop | 15/15 | 8 s |
| Luna, loop | 15/15 | 16 s |

The loop added 14 seconds at the median and turned a 53% pass rate into 100%. That matches the hosted models on this suite, at no per-token cost. The extra time is the price: the local model is still three to seven times slower than Haiku and Luna.

The loop works because it supplies what the model lacks, an outside check. The model that missed the list-to-tuple case did not need a stronger mind. It needed to be told the assertion failed.

### What the result does not show

In this benchmark the loop's test command is the hidden check, the strongest feedback signal possible. Real projects have weaker tests, and the 15/15 is an upper bound. The result shows how much a feedback signal is worth. It does not show that a 3-billion-active-parameter model equals a hosted model on arbitrary work.

## What makes a harness good

The data points to three properties, in order of effect:

1. **An external verification step.** Running tests and returning the failing lines moved one model from 53% to 100%. No other feature in the eight harnesses came close.
2. **Compatibility with the serving stack.** The lowest local score came from the harness that needed protocol repairs to talk to the server at all.
3. **Low overhead.** With strong models, per-task time ranged from 6 to 34 seconds with identical pass rates.

Model choice sets the ceiling on what one pass can do. The harness decides how much of the gap to the ceiling gets recovered when the first pass is wrong.

## Limits

- **Small suite.** Five tasks, three runs each. One failed run moves a cell by seven points.
- **Small tasks.** Each fits in one prompt and a few files. The results say nothing about large repositories or long sessions.
- **Loop upper bound.** The loop test is the hidden check, as described above.
- **Altered cells.** Qwen Code on Luna ran with reasoning off because OpenAI rejects `reasoning_effort` together with tools. Deep Agents Code on Qwen ran through a repair proxy.
- **Cost not measured.** API spend per cell was not recorded, and tokens are blank for most harnesses.

## Reproduce

The runner, adapters, tasks, and checks are in the repository. `bench/selftest.sh` proves every check fails on the empty starter and passes on the reference solution. Then select columns:

```bash
COLS="A C@luna I" RUNS=3 bench/run.sh
bench/matrix.sh
```

A column is a harness letter with an optional `@haiku`, `@luna`, or `@local` model suffix. The full matrix is in [`docs/harness-comparison.md`](harness-comparison.md).
