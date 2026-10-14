# Architecture

This service exposes one OpenAI-compatible HTTP endpoint on `127.0.0.1:8080`. Agentic coding clients, such as OpenCode, Codex CLI, or Aider, send chat requests with tool calls to that endpoint. The service does not provide autocomplete (fill-in-the-middle).

## Hardware budget

| Resource | Available | Budget |
| --- | --- | --- |
| GPU | NVIDIA RTX 3070, 8 GB | About 7.5 GB. Leave headroom for the desktop. |
| RAM | 30 GB | 24 GB maximum, enforced by systemd `MemoryMax`. |
| CPU | Ryzen 5 5500X3D, 6 cores, 12 threads | 6 threads for inference. |

## Components

- **Inference server:** `llama-server` from [llama.cpp](https://github.com/ggml-org/llama.cpp), built from source with CUDA. It serves `/v1/chat/completions` with tool calling through the model's Jinja chat template (`--jinja`).
- **Model:** Qwen3.6-35B-A3B, GGUF, `UD-Q4_K_M` (about 22.1 GB), stored on an external drive resolved through `MODEL_DRIVE_UUID`. It is a mixture-of-experts (MoE) model with about 3B active parameters per token, which keeps CPU-side decoding fast.
- **Process manager:** a systemd user unit, `local-coder.service`. It restarts the server on failure and caps memory.
- **Clients:** any agent that speaks the OpenAI Chat Completions API with tools. The repository ships a sample OpenCode config.

## Memory placement

`llama-server` places tensors as follows:

- **GPU:** attention, shared weights, router weights, the KV cache, and the expert weights of the first layers.
- **CPU RAM:** the expert (FFN) weights of the remaining layers, selected with `--n-cpu-moe N`.

You tune `N` once. Start high (all 40 layers on CPU), then lower it until VRAM use reaches about 7.5 GB.

## Context and KV cache

Agentic clients send long system prompts and tool output, so the service targets a 64K token context. The KV cache uses `q8_0` (`--cache-type-k q8_0 --cache-type-v q8_0`) with flash attention on, which halves cache size compared with `f16`. If VRAM is short, you lower the context to 32K before you move more experts to the CPU.

## Request flow

1. The agent sends a chat request with tool definitions to `http://127.0.0.1:8080/v1/chat/completions`.
2. `llama-server` applies the chat template, reuses the cached prompt prefix, and generates.
3. The server returns tool calls in OpenAI format. The agent runs the tools locally and sends the results back.

The server uses a 128-token physical prompt-processing batch (`-ub 128`) to limit compute buffer memory, with six inference threads and CUDA graphs enabled.

The server runs one slot (`--parallel 1`). One agent session gets the full context and prompt cache. The host prompt cache is capped at 2 GB (`--cache-ram 2048`) to stay under `MemoryMax`; the 8 GB default caused an OOM kill on 2026-10-12.

## Model alternatives

| Model | When to use |
| --- | --- |
| Qwen3-Coder-30B-A3B-Instruct `Q4_K_M` | Archived on HDD1; measured about 24.5 tok/s. |
| Qwen3.6-35B-A3B `UD-Q4_K_M` | Default; fastest tested code generation here, about 35–41 tok/s; 36 expert layers on CPU. |
| Qwen3.8-27B `UD-Q4_K_M` | Fits with CPU offload; see measured baseline and MTP tuning in the comparison. |
| Qwen2.5-Coder-7B-Instruct `Q4_K_M` | Fully on GPU. Use it if RAM is needed for other work. Weaker at tool use. |

Benchmark each model on your own tasks before you switch. Public speed figures for 8 GB setups come from single community reports.

## Harness benchmark

`bench/` compares coding agent harnesses on the same tasks. It is a set of shell scripts plus one stdlib Python proxy. It runs no service of its own.

- **Runner (`bench/run.sh`):** loops over tasks, columns, and runs. It owns the local model lifecycle: it starts `local-coder.service` only for local columns and stops it on exit, but only if it started it.
- **Columns:** a letter picks the harness (A and B `claude-local-code`, C OpenCode, D Qwen Code, E DeepSeek Harness, F Deep Agents Code, G Hermes, H OpenClaw, I Codex CLI). An optional `@haiku`, `@luna`, or `@local` suffix picks the model. Without a suffix, A is Haiku, I is Luna on the ChatGPT login, and the rest are local Qwen.
- **Adapters (`bench/adapters/`):** one script per harness. Each runs the harness headless in a temp workdir and never scores a run. `_remote.sh` resolves the vendor, model name, URL, and key for `@haiku` and `@luna`. `_litellm.sh` starts a LiteLLM proxy when a harness speaks a different protocol than the vendor (Codex on Haiku, `claude-local-code` on Luna).
- **Proxy (`bench/adapters/fix_empty_content.py`):** sits between a harness and `llama-server` (or an OpenAI host) for Deep Agents Code and Qwen Code. It drops empty reasoning items, moves tool arguments back to the function call, fills empty content, and, for OpenAI hosts, renames `max_tokens` and turns reasoning off when tools are present.
- **Tasks (`bench/tasks/`):** a prompt, a starter tree, a known-good solution, and a hidden `check.sh`. The runner runs the check after the adapter finishes and never copies it into the workdir.
- **Reports:** `bench/matrix.sh` prints the harness by model matrix (markdown, or tab-separated with `--tsv`). `bench/report.sh` prints the older per-column table. `bench/matrix.tsv` is the committed result.
- **Self-test (`bench/selftest.sh`):** proves every check fails on the starter and passes on the solution, dry-runs the runner with stub adapters, and checks the column mapping.
- **Trust boundary:** the agent sees the prompt and its workdir. It does not see `check.sh`, although a harness with a shell tool could search the filesystem for it. API keys live in `bench/.keys.env` (gitignored), and `_remote.sh` reads them on demand. The runner never exports the Anthropic key to the `claude` wrapper, because subscription tokens are barred in third-party harnesses and the wrapper uses the subscription.

Results are in [harness comparison](harness-comparison.md).

## Security

The server binds to `127.0.0.1` and requires an API key (`--api-key`). It does not listen on the network. Remote access, if needed later, goes through an SSH tunnel.

## Measured performance

The figures below describe the previous Qwen3-Coder default. The current Qwen3.6 measurements are in [model comparison](model-comparison.md).

End-to-end check: OpenCode `run` against the service added a Python function and a unittest in a scratch repo, then ran the test (it passed). Figures come from llama-server timings in `journalctl --user -u local-coder`.

| Metric | Value |
| --- | --- |
| Decode speed | about 24.5 tok/s (24.3 to 24.7 over 100 to 178 token replies) |
| Prompt processing | about 402 tok/s (cold 11,748 token prompt; small cached follow-ups are lower) |
| Peak RAM (`MemoryPeak`) | 22,539,694,080 bytes (about 21.0 GiB, under the 24 GB cap) |

Newer local model tests and optimization measurements: [model comparison](model-comparison.md).
