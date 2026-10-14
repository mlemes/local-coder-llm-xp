# Eight coding agent harnesses, three models, 405 runs

A coding agent is a model plus a harness: the program that sends prompts, runs tools, and decides when to stop. Published comparisons usually vary the model. This benchmark holds the model fixed and varies the harness, then repeats with three models to see when the harness matters.

## Method

Five small tasks, each with a hidden check the agent never sees:

- Write `parse_duration` from a spec.
- Write `merge_intervals` from a spec.
- Fix a bug in a discount calculation.
- Change a function signature and update its caller.
- Rename a function across a small project.

The checks cover edge cases the prompt omits: empty input, touching intervals, negative numbers. The runner copies the starter files into a temp directory, calls the harness headless, and runs the check itself. A self-reported pass counts for nothing.

The harnesses are `claude-local-code` (a wrapper around headless Claude Code with an optional test-and-retry loop), OpenCode, Qwen Code, DeepSeek Harness, Deep Agents Code, Hermes, OpenClaw, and Codex CLI. The models are Claude Haiku, OpenAI Luna, and a local Qwen3.6-35B-A3B served by `llama.cpp`. Each cell is five tasks times three runs, 15 runs. The matrix holds 405 runs.

Everything is shell. Each harness has one adapter that takes a prompt file and a working directory. The benchmark needs no Docker and no framework.

## Strong models hide the harness

Haiku and Luna passed 299 of 300 runs. The single miss was Codex CLI on Luna.

On tasks this small, a capable model finishes the job regardless of the harness. Only latency differs. The wrapper on Haiku took a median of 6 seconds. OpenClaw took 26 seconds for the same correct result. With a frontier model on short tasks, harness choice is a latency and ergonomics decision, not a quality one.

## The local model exposes the harness

Same Qwen model, same server, same tasks, no retry loop:

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

The spread is 4 to 12 out of 15 with one model. The harness matters when the model is weak enough to need help.

Treat the last row with care. Deep Agents Code uses the OpenAI Responses API, and `llama-server` mishandles two things there. It turns empty reasoning items into empty messages, and it puts tool arguments in the reasoning item instead of the tool call. A small stdlib proxy, `bench/adapters/fix_empty_content.py`, repairs both. The 4/15 reflects the harness plus the proxy, and the two cannot be fully separated.

## A bug in the retry loop

The wrapper runs a test command, feeds failures back to the agent, and retries. In the first full run the loop scored 9/15 on Qwen, barely above no loop.

The logs showed the script exiting after the first failed test. It extracts failing test names with `grep` under `set -euo pipefail`. When `grep` finds no match it returns 1, and the script dies before the retry. Appending `|| true` fixed it. The same wrapper and model then scored 15/15.

Two lessons follow. A benchmark that finds a bug in the tool under test is working. And a result that confirms the expected ranking deserves the same scrutiny as one that contradicts it.

The loop has a caveat. Its test command is the hidden check. In real use, the loop runs the project's own tests, so 15/15 is an upper bound and not a fair comparison with the other rows.

## Integration problems

- **Subscription tokens.** Anthropic bars subscription OAuth tokens in third-party harnesses. Only the wrapper, which runs the official `claude` binary, can use a subscription. Every other Haiku cell needs an API key.
- **Workspace-scoped keys.** An Anthropic API key created outside a workspace was rejected with a request for an `anthropic-workspace-id` header. A key created inside a workspace worked.
- **Luna with tools.** OpenAI chat completions reject `reasoning_effort` together with tools and require `max_completion_tokens` in place of `max_tokens`. The proxy sets reasoning to `none` for the Qwen Code cell on Luna. That cell is therefore not comparable with the others.
- **Stdin.** `dcode` waits on stdin in headless mode. Redirecting `</dev/null` fixes the hang.
- **Protocol mismatch.** Codex CLI speaks the Responses API and the Claude wrapper speaks the Messages API. A local LiteLLM proxy translates for the cells where the vendor API does not match.

## Conclusions

- **Daily use:** `claude-local-code` on Haiku was the fastest row with a perfect score.
- **Weak local model:** a test command with retries lifted Qwen from 8/15 to 15/15. No harness swap came close.
- **No loop available:** Codex CLI and Qwen Code scored highest on Qwen.
- **Limits:** five small tasks and three runs each. One failed run moves a cell by seven points. The tasks fit in one prompt and a few files, so the results say nothing about a 200-file repository or a two-hour session. API spend per cell was not recorded.

## Reproduce

The repository contains the runner, adapters, tasks, and checks. `bench/selftest.sh` proves that every check fails on the empty starter and passes on the reference solution. Then select columns:

```bash
COLS="A C@luna I" RUNS=3 bench/run.sh
bench/matrix.sh
```

A column is a harness letter with an optional `@haiku`, `@luna`, or `@local` suffix for the model. To add a task, create a folder under `bench/tasks/` with `prompt.md`, `starter/`, `solution/`, and `check.sh`. Larger tasks are the open question: whether the strong-model result holds on them is untested.
