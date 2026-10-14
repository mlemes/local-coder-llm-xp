# How the harness changes coding agent results

*October 2026. Eight harnesses, three models, 405 scored runs. With test-guided retries, a locally served Qwen model matched the hosted models' pass rate on a five-task suite.*

This experiment compares eight coding agent harnesses separately for each of three models, then tests test-guided retries in one wrapper. A harness is the program that sends prompts, runs tools, and decides when to stop.

Three findings:

- Hosted models scored near the ceiling in every harness. Pass rates did not separate the harnesses. Wall time did.
- The local Qwen model passed between 4/15 and 12/15 runs depending on the harness, with the same model file and server defaults.
- In one wrapper, adding grading feedback and retries raised the local model from 8/15 to 15/15, matching the hosted models' observed scores. The retry loop received the grading check's failure output, which makes this an upper bound.

## Experiment design

### Models

| Model | Identifier | How it ran |
| --- | --- | --- |
| Claude Haiku 5.5 | `claude-haiku-5-5` | Anthropic API; the `claude-local-code` wrapper used a Claude subscription |
| OpenAI Luna | `gpt-6-luna` | OpenAI API; Codex CLI used the ChatGPT login |
| Qwen3.6-35B-A3B | `Qwen3.6-35B-A3B-UD-Q4_K_M.gguf` | `llama-server` on one RTX 3070 (8 GB), 64K context |

Qwen3.6-35B-A3B is a mixture-of-experts model with about 3 billion active parameters per token ([model card](https://huggingface.co/Qwen/Qwen3.6-35B-A3B)). The file size, SHA256, `llama.cpp` build, and serving settings are in [`docs/model-comparison.md`](model-comparison.md). The local model incurs no API token charges. Operating cost was not measured.

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

The wrapper ran in two configurations, with and without its loop. That makes nine configurations per model: 3 models × 9 configurations × 5 tasks × 3 repetitions = 405 runs.

### Tasks and grading

Five small tasks:

- Write `parse_duration` from a spec.
- Write `merge_intervals` from a spec.
- Fix a bug in a discount calculation.
- Change a function signature and update its caller.
- Rename a function across a small project.

The runner copies the starter files into a temp directory, calls the harness headless, and runs the grading check itself. A self-reported pass counts for nothing. The checks include edge cases the prompt does not mention and stay outside the task directory. Nothing enforces their secrecy: a harness with a shell tool could search the filesystem for them.

### The retry loop

After each agent invocation, the wrapper runs a test command. On failure, it starts another invocation with the original task and the filtered failure lines, up to eight invocations. In this benchmark the test command is the grading check, so the loop sees the strongest feedback available. The wrapper can also consult Gemini after the same test fails three times, but that trigger needs named failures (`not ok` or `✖` lines). The Python check emits a traceback, so diagnosis did not fire.

## Results

### Local Qwen: retries against a single pass

| Configuration | Passed | Median time | Mean time |
| --- | --- | --- | --- |
| Wrapper, no loop | 8/15 | 40 s | 41.1 s |
| Wrapper, loop | 15/15 | 54 s | 92.8 s |
| Haiku 5.5, wrapper loop | 15/15 | 8 s | |
| Luna, wrapper loop | 15/15 | 16 s | |

The median wall time rose from 40 to 54 seconds, but the mean rose from 41.1 to 92.8 seconds. The three loop runs on `merge_intervals` took 133, 179, and 406 seconds. The local model's median in the loop configuration was about 3.4 times Luna's and 6.8 times Haiku's.

The results show that test-guided retries repaired these tasks. They do not separate the value of the feedback from the value of extra attempts.

### Local Qwen: eight harnesses without a loop

| Harness | Passed | Median time |
| --- | --- | --- |
| Codex CLI | 12/15 | 76 s |
| Qwen Code | 12/15 | 86 s |
| DeepSeek Harness | 11/15 | 75 s |
| OpenCode | 10/15 | 157 s |
| Hermes | 10/15 | 44 s |
| OpenClaw | 9/15 | 147 s |
| Wrapper, no loop | 8/15 | 40 s |
| Deep Agents Code | 4/15 | 109 s |

Across the 120 local no-loop runs, the tasks differ sharply:

| Task | Passed |
| --- | --- |
| `fix_bug` | 22/24 |
| `search_refactor` | 21/24 |
| `two_file_edit` | 21/24 |
| `parse_duration` | 12/24 |
| `merge_intervals` | 0/24 |

`merge_intervals` accounts for 24 of the 44 failures, but it fails everywhere, so it adds nothing to the differences between harnesses. Those come from the other four tasks, mainly `parse_duration`. The cause of the remaining spread was not diagnosed.

### A diagnosed failure: `merge_intervals`

Of the 24 failed `merge_intervals` runs, 22 stop at the same assertion: input given as lists, `[[1, 2], [4, 5]]`, must return the tuples `[(1, 2), (4, 5)]`. The other two never produced an importable `intervals` module. The prompt asks for tuples and never shows list input. The logs do not establish which tests each agent ran. A harness that only relays tool calls adds no information the model lacks. A retry that includes the failing assertion does.

### Hosted models

Haiku 5.5 and Luna passed 269 of 270 runs. Without the wrapper's loop, they passed 239 of 240. The one failure was Codex CLI on Luna.

Median wall time for Haiku ranged from 6 seconds (wrapper, no loop) to 26 seconds (OpenClaw). The timing includes startup, and its components were not measured.

## Recommendations

1. **Add a verification step before you change the model.** From the wrapper's 8/15 baseline, grading feedback and retries added seven passes. Switching to either top-scoring no-loop harness added four.
2. **Measure with your own tests.** This benchmark used the grading check as the loop's test command. The effect of ordinary project tests is unmeasured. Evaluate it against separate held-out checks.
3. **Compare latency when correctness is similar.** Hosted-model pass rates were within one run of each other, so latency and ergonomics are the remaining differences on this suite.
4. **Test a harness against your serving stack.** Deep Agents Code needed a proxy to repair `llama-server` Responses API output and scored 4/15. The proxy's independent effect was not measured, so treat that score as confounded by the integration.

## Limitations and next experiments

- **Suite size.** Each cell has three repetitions of five distinct tasks. One failure changes a pass rate by 6.7 percentage points. The suite establishes neither statistical significance nor general model equivalence.
- **Task size.** Each task fits in one prompt and a few files. The results say nothing about large repositories or long sessions.
- **Altered cells.** Qwen Code on Luna ran with reasoning off, because OpenAI rejects `reasoning_effort` together with tools. Codex CLI on Haiku and the wrapper on Luna ran through a LiteLLM proxy that translates protocols.
- **Cost.** API spend per cell was not recorded, and token counts are blank for most harnesses.
- **Next.** Run the loop with equal attempt budgets for every harness, with ordinary project tests as feedback and separate held-out grading.

## Reproduce

The runner, adapters, tasks, and checks are in the repository. `bench/selftest.sh` checks that each grader rejects the starter and accepts the reference solution. A hosted-model subset:

```bash
COLS="A C@luna I" RUNS=3 bench/run.sh
bench/matrix.sh
```

The local comparison, with separate result files:

```bash
export RESULTS=$(mktemp) LOGDIR=$(mktemp -d)
COLS="B C D" RUNS=3 bash bench/run.sh
bash bench/matrix.sh --tsv "$RESULTS"
```

A column is a harness letter with an optional `@haiku`, `@luna`, or `@local` suffix. The full matrix is in [`docs/harness-comparison.md`](harness-comparison.md).
