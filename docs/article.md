# How the harness changes coding agent results

*October 2026. Eight harnesses, three models, 405 scored runs, and one result: a feedback loop brought a free local model level with two hosted models.*

Coding agent benchmarks mostly vary the model. The harness, the program that sends prompts, runs tools, and decides when to stop, is usually held constant or treated as plumbing. This experiment holds the model constant and varies the harness.

Three findings:

- With a strong model, the harness barely changes the pass rate. It changes speed.
- With a weak model, the same weights scored from 4/15 to 12/15 depending on the harness.
- One harness feature, running tests and returning the failures to the agent, took a local model from 8/15 to 15/15. That equals the hosted models on this suite.

## Experiment design

### Models

| Role | Model | Identifier | How it ran |
| --- | --- | --- | --- |
| Hosted, small | Claude Haiku 5.5 | `claude-haiku-5-5` | Anthropic API |
| Hosted, large | OpenAI Luna | `gpt-6-luna` | OpenAI API, or the ChatGPT login for Codex CLI |
| Local | Qwen3.6-35B-A3B | `Qwen3.6-35B-A3B-UD-Q4_K_M.gguf`, 22,134,528,992 bytes, SHA256 `ac0e2c1189e055faa36eff361580e79c5bd6f8e76bffb4ce547f167d53e31a61` | `llama-server` from `llama.cpp` build b11559, 64K context, temperature 0.6, top-p 0.95, min-p 0, reasoning budget 2048 |

Qwen3.6-35B-A3B is a mixture-of-experts model with about 3 billion active parameters. It ran on one RTX 3070 with 8 GB of VRAM and 30 GB of RAM at 35 to 40 tokens per second, with no per-token cost.

### Harnesses

| Harness | Version |
| --- | --- |
| `claude-local-code` (headless Claude Code with an optional test-and-retry loop) | Claude Code 2.1.296 |
| OpenCode | 1.19.0 |
| Qwen Code | 0.25.1 |
| Deep Agents Code | 0.1.84 |
| Hermes Agent | 0.21.7 |
| OpenClaw | 2026.10.2 |
| Codex CLI | 0.160.1 |
| DeepSeek Harness | not recorded |

### Tasks and grading

Five small tasks, each with a hidden check the agent never sees:

- Write `parse_duration` from a spec.
- Write `merge_intervals` from a spec.
- Fix a bug in a discount calculation.
- Change a function signature and update its caller.
- Rename a function across a small project.

The checks include edge cases the prompt does not mention. The runner copies the starter files into a temp directory, calls the harness headless, and runs the check itself. A self-reported pass counts for nothing. Each cell is five tasks times three runs, 15 runs.

## Results

### Strong models: the harness barely matters

Haiku 5.5 and Luna passed 299 of 300 runs across the eight harnesses. The single miss was Codex CLI on Luna.

Speed was the only difference. The `claude-local-code` wrapper on Haiku took a median of 6 seconds per task. OpenClaw took 26 seconds for the same correct result. On short tasks, a capable model carries the harness, so the choice among these eight is a question of latency and ergonomics.

### Weak model: the harness decides

Qwen3.6 on the same server, the same tasks, and no retry loop:

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

The weights and sampling settings are identical, and the pass rate spans a factor of three. Most of the variation comes from one task. Across the 120 local no-loop runs:

| Task | Passed |
| --- | --- |
| `fix_bug` | 22/24 |
| `search_refactor` | 21/24 |
| `two_file_edit` | 21/24 |
| `parse_duration` | 12/24 |
| `merge_intervals` | 0/24 |

`merge_intervals` failed in every harness. At least 19 of the 24 failures stop at the same assertion: input given as lists, `[[1, 2], [4, 5]]`, must return the tuples `[(1, 2), (4, 5)]`. The prompt asks for tuples but never shows list input. The agents wrote code, tested the cases the prompt mentioned, reported success, and stopped. A harness that only executes tool calls cannot tell the model something the model does not already check, so none of them fixed it.

The remaining spread between harnesses on the other tasks was not diagnosed. Deep Agents Code needed a proxy to repair `llama-server` Responses API output and still scored lowest.

### A feedback loop closes the gap

`claude-local-code` can run a test command after each edit, pass the failing lines to the agent, and let it retry. With the loop on, Qwen3.6 passed 15/15, including 3/3 on `merge_intervals`. With the loop off, the same wrapper and model passed 8/15.

| Configuration | Passed | Median time |
| --- | --- | --- |
| Qwen3.6, no loop | 8/15 | 40 s |
| Qwen3.6, loop | 15/15 | 54 s |
| Haiku 5.5, loop | 15/15 | 8 s |
| Luna, loop | 15/15 | 16 s |

The loop added 14 seconds at the median and moved the pass rate from 53% to 100%, which matches the hosted models on this suite. The local model remains three to seven times slower than Haiku and Luna.

## Why the loop worked

Each failure had the same shape: the model skipped a case the prompt did not show, and nothing in the harness told it so.

| Failure mode | Observed in | Harness feature that addresses it |
| --- | --- | --- |
| The model misses an edge case and reports success | `merge_intervals`, 19 of 24 local no-loop failures | Run the tests, return only the failing lines, retry |
| The server and harness disagree on a protocol | Deep Agents Code on `llama-server` | A repair proxy (partial effect: 4/15) |
| Startup and tool overhead dominate short tasks | OpenClaw, 26 s against 6 s on Haiku | Fewer round trips per task |

The model that missed the list-to-tuple case did not need to be smarter. It needed to be told that an assertion failed. An external check supplies the signal a single pass lacks.

## Recommendations

1. **Add a verification step before you change the model.** On the weak model, a test loop was worth more than any harness swap.
2. **Match the check to the real project.** This benchmark used the hidden check as the loop's test command. Your own test suite is a weaker signal, so expect less than 15/15.
3. **Pick the harness by latency when the model is strong.** Eight harnesses were indistinguishable on pass rate.
4. **Test a harness against your serving stack.** Protocol differences with a local server cost runs that have nothing to do with model quality.

## Limitations and future work

- **Suite size.** Five tasks, three runs each. One failed run moves a cell by seven points.
- **Task size.** Each task fits in one prompt and a few files. The results say nothing about large repositories or long sessions.
- **Loop upper bound.** The loop's test command is the hidden check, the strongest feedback signal available.
- **Altered cells.** Qwen Code on Luna ran with reasoning off, because OpenAI rejects `reasoning_effort` together with tools. Deep Agents Code on Qwen ran through a repair proxy.
- **Unmeasured cost.** API spend per cell was not recorded, and token counts are blank for most harnesses.
- **Open question.** Whether a weaker feedback signal, such as a project's own unit tests, still lifts the local model to hosted-model levels.

## Reproduce

The runner, adapters, tasks, and checks are in the repository. `bench/selftest.sh` proves that every check fails on the empty starter and passes on the reference solution. Then select columns:

```bash
COLS="A C@luna I" RUNS=3 bench/run.sh
bench/matrix.sh
```

A column is a harness letter with an optional `@haiku`, `@luna`, or `@local` suffix for the model. The full matrix is in [`docs/harness-comparison.md`](harness-comparison.md).

Read the failing check output before you tune anything. The `merge_intervals` result came from one line of it.
