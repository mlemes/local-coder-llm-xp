# Eight coding agent harnesses, three models, 405 runs

I run a small local coding setup. A Qwen3.6 35B model on an 8 GB GPU, served by llama.cpp, with a wrapper script around Claude Code that sends the dull edits to a cheaper model and retries until the tests pass. It worked, but I had never checked whether the wrapper was the right harness. Everyone I read had a favorite, and nobody had numbers on the same tasks.

I built a benchmark and ran it. This is what came out, including the part where my own wrapper had a bug that made it look worse than it was.

## The setup

Five small tasks, each with a hidden check the agent never sees:

- write `parse_duration` from a spec
- write `merge_intervals` from a spec
- fix a bug in a discount calculation
- change a function signature and update its caller
- rename a function across a small project

The checks test edge cases the prompt does not mention. Empty input, touching intervals, a negative number. The runner copies the starter files into a temp directory, calls the harness headless, then runs the check itself. If an agent says it passed, I do not care.

Eight harnesses: my wrapper, OpenCode, Qwen Code, DeepSeek's harness, Deep Agents Code, Hermes, OpenClaw, and Codex CLI. The wrapper runs in two modes, with and without its retry loop. Three models: Claude Haiku, OpenAI's Luna, and the local Qwen. Each cell is five tasks times three runs, so 15 runs. The full matrix is 405 runs.

Everything is shell scripts. Each harness gets one adapter, a small script that takes a prompt file and a working directory. I did not want Docker or a benchmark framework for a question this small.

## The strong models told me nothing

Haiku and Luna passed 299 of 300 runs. The one miss was Codex on Luna, once.

The boring result almost got skipped. On tasks this small, a good model finishes the job whatever you put around it. The only difference was speed. My wrapper on Haiku took a median of 6 seconds. OpenClaw took 26 for the same correct answer. If you run a frontier model on short tasks, your harness choice is a latency and taste decision, not a quality one.

I would not have believed that before running it. Blog rankings of harnesses read as if they matter a lot.

## The local model is where it got interesting

Same Qwen model, same server, same tasks. Pass rates without any retry loop:

| Harness | Passed | Median time |
| --- | --- | --- |
| Codex CLI | 12/15 | 76 s |
| Qwen Code | 12/15 | 86 s |
| DeepSeek Harness | 11/15 | 75 s |
| OpenCode | 10/15 | 157 s |
| Hermes | 10/15 | 44 s |
| OpenClaw | 9/15 | 147 s |
| My wrapper, no loop | 8/15 | 40 s |
| Deep Agents Code | 4/15 | 109 s |

A spread from 4 to 12 out of 15 with one model. So the harness does matter, but only when the model is weak enough to need help.

Take the bottom row with a grain of salt. Deep Agents Code speaks the OpenAI Responses API, and llama.cpp's server gets two things wrong there: it turns empty reasoning items into empty messages, and it puts tool arguments in the reasoning item instead of the tool call. I wrote a small proxy that fixes both. The 4/15 is the harness plus my proxy, and I cannot fully separate them.

## My wrapper had a bug

The wrapper has a loop. It runs your test command, feeds the failures back to the agent, and tries again. On the first full run, the loop scored 9/15 on Qwen. Barely better than no loop.

The result made no sense, so I read the logs. After the first failed test the script exited. It pulled failing test names with `grep` under `set -euo pipefail`, and when `grep` found no match it returned 1, which killed the script before the retry. A `|| true` fixed it. Same wrapper, same model: 15/15.

I mention this because I was about to publish "the wrapper loses to Codex on local models." It would have been wrong. A benchmark that finds a bug in your own tool is doing its job, and a benchmark that confirms what you hoped is the one to distrust.

There is a catch. The loop's test command is the hidden check. In real use you would give the agent your own tests, so treat the 15/15 as an upper bound, not a fair comparison with the other rows.

## Things that cost me time

- **Subscription tokens.** I wanted to run Haiku through every harness on my Claude subscription. Anthropic bars subscription tokens in third-party tools. Only the wrapper, which runs the official `claude` binary, qualifies. Everything else used an API key. Read the terms before you build the plan around a login.
- **An API key with no workspace.** The first Anthropic key I made got rejected with a request for an `anthropic-workspace-id` header. Creating a new key inside a workspace fixed it.
- **Luna and tools.** OpenAI's chat completions endpoint rejects `reasoning_effort` together with tools, and wants `max_completion_tokens` instead of `max_tokens`. The Qwen Code cell on Luna runs with reasoning off because of this. I said so in the table notes. You should know about it before you compare that number.
- **A harness that hung.** `dcode` waited on stdin until I added `</dev/null`.
- **A proxy that translates between protocols.** Codex wants the Responses API, the Claude wrapper wants the Messages API. LiteLLM sits in the middle for the cells where the model's native API does not match.

## What I would do with this

Keep the wrapper with Haiku for daily work. It was the fastest perfect row and it already does what I need.

For a weak local model, put your effort into a test command with retries. That moved Qwen from 8/15 to 15/15, far more than any swap of harness did. If you cannot have a loop, Codex CLI and Qwen Code were the best of the eight.

Do not take any of this as a ranking. Five small tasks, three runs each. One failed run moves a cell by seven points. The tasks fit in one prompt and a handful of files, so nothing here says how a harness handles a 200-file repository or a two-hour session. I also did not record what the API runs cost.

## Run it yourself

The repository has the runner, the adapters, the tasks, and the checks. Start with `bench/selftest.sh`, which proves every check fails on the empty starter and passes on the reference solution. Then pick columns:

```bash
COLS="A C@luna I" RUNS=3 bench/run.sh
bench/matrix.sh
```

A column is a letter for the harness, with an optional `@haiku`, `@luna`, or `@local` for the model. Add your own tasks by dropping a folder under `bench/tasks/` with a prompt, a starter tree, a solution, and a `check.sh`. If your tasks are bigger than mine, I would like to see whether the strong-model result still holds.
