# Save tokens with a local model and keep code quality

Last updated October 12, 2026. This page summarizes research on splitting coding work between a strong hosted model and a cheaper local model, and it maps the findings to this repository.

## Summary

Use the strong model for decisions and the local model for volume. Verify every local result with a deterministic check, not with another model call.

1. Write a precise spec with the strong model.
2. Send the edit to the local model through `local-coder`.
3. Run tests, linters, and type checks yourself.
4. Escalate to the strong model only when the check fails twice.

Published numbers come from different tasks and mostly from secondary sources. Treat them as direction, not as promises. Measure on your own tasks before you rely on them.

## What the research shows

### Planner and editor split

Aider separates an Architect model that solves the problem from an Editor model that writes the file edits. In Aider's [architect mode benchmark](https://aider.chat/2024/09/26/architect.html), the pairing improved every solo baseline that the post reports:

| Model | Solo | Paired |
| --- | ---: | ---: |
| o1-mini | 61.1% | 71.4% (DeepSeek as Editor) |
| Claude 3.5 Sonnet | 77.4% | 80.5% (itself as Editor) |
| GPT-4o | 71.4% | 75.2% (itself as Editor) |
| GPT-4o-mini | 55.6% | 60.2% (itself as Editor) |

The post explains the gain: reasoning models solve problems well but often produce badly formatted edits. A separate Editor turns a plain description into valid edits. The split helps quality even before you count cost.

Vendor reports describe the same pattern for agents. [Morph](https://www.morphllm.com/multi-agent-model-routing) claims 4x lower execution cost, and [Blackbox](https://www.blackbox.ai/blog/orchestrator-executor-multi-agent-system-for-swe-tasks) reports a gain on Terminal-Bench 2.0. These are vendor numbers and are not independently confirmed.

### Routing and cascades

[RouteLLM](https://lmsys.org/blog/2024-07-01-routellm/) sends each query to a strong or weak model before generation. At 95% of GPT-4 quality it reported these cost reductions:

| Benchmark | Cost reduction | Strong-model call share |
| --- | ---: | ---: |
| MT Bench | over 85% | 14% (with augmented training) |
| MMLU | over 45% | 54% |
| GSM8K | 35% | not stated |

These benchmarks are chat, knowledge, and math tasks. The sources I found did not report coding results. A cascade, such as [FrugalGPT](https://www.generalcompute.com/blog/cascade-inference-using-small-models-to-route-to-big-ones), tries the cheap model first and escalates when a scorer rejects the answer. The scorer must cost far less than the stage it gates. For code, the best scorer is a test run.

### Where the savings come from

- Planning is a small share of tokens, about 20% by one [estimate](https://www.datallmlab.com/blog/orchestrator-executor-llm-pattern.html). File reads and mechanical edits make up most of the rest, and they do not need a frontier model.
- Context is the other cost. [Cursor's agent swarm](https://the-decoder.com/cursors-agent-swarm-suggests-cheaper-models-can-handle-most-coding-when-frontier-models-plan-the-work/) gives each worker a narrow task, so no agent carries the whole tree.

### Failure modes

- **Replanning loops.** If the cheap executor fails on an ambiguous step, the loop calls the strong model again and the savings shrink. A [source](https://tianpan.co/blog/2026-04-12-the-planning-tax-why-your-agent-spends-more-tokens-thinking-than-doing) notes that small planners replan often.
- **Mixed setups can lose.** One [report](https://www.datallmlab.com/blog/orchestrator-executor-llm-pattern.html) found a solo strong model beating mixed setups on a benchmark, and said mixing was sometimes slower and costlier.
- **Misrouted hard code.** Routers are weakest on hard reasoning and code generation. Do not route by prompt text alone.

### Speculative decoding is a different tool

Speculative decoding speeds up one model with a small draft model. It saves time, not hosted tokens. Recent work such as [MARS](https://www.emergentmind.com/papers/2606.01019) and [SpecPV](https://arxiv.org/abs/2512.02337v1) targets latency. This repository tested ngram speculation, and it did not help (see `docs/qwen36-optimization.md`).

## Apply this to this repository

The local model is Qwen3.6-35B-A3B at about 43 tokens per second. The `local-coder` subagent and `claude-local-code` already implement the Editor role.

### Delegate to the local model

Delegate when all of these are true:

- The task names the files.
- The spec is clear and the change is small or mechanical.
- A deterministic check exists, such as a test, `bash -n`, or a type check.

Examples: add a function from a signature, rename across files, write tests from a written spec, convert formats, apply a described refactor.

### Keep on the strong model

- Design choices, ambiguous requirements, and debugging with unknown causes.
- Security-sensitive code and anything you cannot check automatically.
- Review of the final diff.

### Write a spec the local model can follow

A small model fails on missing detail. Put these in the task string:

1. The exact file paths.
2. The function signature and the expected behavior, including edge cases.
3. The existing helper to reuse, if one exists.
4. The constraint that matters most, such as "do not change public names".

Skip long background. Every extra token costs prompt processing locally and tokens in the strong model.

### Verify without a second model

1. Run the project's tests or static checks after each delegated edit.
2. Read the diff, not the whole file.
3. On failure, send the exact error output back to the local model once.
4. If it fails again, take the task back to the strong model.

This is the cheap cascade scorer. It costs no model tokens.

### Reduce what the strong model sees

- Pass file paths, not file contents, in prompts to subagents.
- Ask subagents to return only the result.
- Do not paste local-model output back into the strong model's context. Check it with commands.

### Measure

The research gives no numbers for this setup, so record your own. For each delegated task, log:

- Strong-model tokens saved against doing the task directly.
- First-attempt pass rate of the check.
- Escalation rate.
- Local wall-clock time.

If escalations exceed about one in three, tighten the specs or stop delegating that task type. A first run shows a 1-file edit finishing in about 11 seconds once the service is warm.

## Open questions

- No coding-specific routing benchmark was found for Qwen3.6-class local models. Build a small task set from this repository and compare pass rates.
- Aider's published pairings use hosted models. Whether Qwen3.6 as Editor matches them is untested here.
- The `--bare` run loads no `CLAUDE.md`. Check whether adding a short style note raises the first-attempt pass rate.

## Sources

- [Aider: separating code reasoning and editing](https://aider.chat/2024/09/26/architect.html)
- [LMSYS: RouteLLM](https://lmsys.org/blog/2024-07-01-routellm/)
- [Cascade inference with small models](https://www.generalcompute.com/blog/cascade-inference-using-small-models-to-route-to-big-ones)
- [Orchestrator and executor LLM pattern](https://www.datallmlab.com/blog/orchestrator-executor-llm-pattern.html)
- [Multi-agent model routing](https://www.morphllm.com/multi-agent-model-routing)
- [Orchestrator and executor for SWE tasks](https://www.blackbox.ai/blog/orchestrator-executor-multi-agent-system-for-swe-tasks)
- [Cursor's agent swarm](https://the-decoder.com/cursors-agent-swarm-suggests-cheaper-models-can-handle-most-coding-when-frontier-models-plan-the-work/)
- [The planning tax](https://tianpan.co/blog/2026-04-12-the-planning-tax-why-your-agent-spends-more-tokens-thinking-than-doing)
- [Hybrid Verified Decoding](https://www.emergentmind.com/papers/2606.01019)
- [SpecPV](https://arxiv.org/abs/2512.02337v1)
