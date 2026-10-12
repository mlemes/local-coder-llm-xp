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
- **Model:** Qwen3-Coder-30B-A3B-Instruct, GGUF, `Q4_K_M` (about 18.6 GB). It is a mixture-of-experts (MoE) model with about 3B active parameters per token, which keeps CPU-side decoding fast.
- **Process manager:** a systemd user unit, `local-coder.service`. It restarts the server on failure and caps memory.
- **Clients:** any agent that speaks the OpenAI Chat Completions API with tools. The repository ships a sample OpenCode config.

## Memory placement

`llama-server` places tensors as follows:

- **GPU:** attention, shared weights, router weights, the KV cache, and the expert weights of the first layers.
- **CPU RAM:** the expert (FFN) weights of the remaining layers, selected with `--n-cpu-moe N`.

You tune `N` once. Start high (all 48 layers on CPU), then lower it until VRAM use reaches about 7.5 GB.

## Context and KV cache

Agentic clients send long system prompts and tool output, so the service targets a 64K token context. The KV cache uses `q8_0` (`--cache-type-k q8_0 --cache-type-v q8_0`) with flash attention on, which halves cache size compared with `f16`. If VRAM is short, you lower the context to 32K before you move more experts to the CPU.

## Request flow

1. The agent sends a chat request with tool definitions to `http://127.0.0.1:8080/v1/chat/completions`.
2. `llama-server` applies the chat template, reuses the cached prompt prefix, and generates.
3. The server returns tool calls in OpenAI format. The agent runs the tools locally and sends the results back.

The server runs one slot (`--parallel 1`). One agent session gets the full context and prompt cache.

## Model alternatives

| Model | When to use |
| --- | --- |
| Qwen3-Coder-30B-A3B-Instruct `Q4_K_M` | Default. Best speed for agent loops. |
| Qwen3.6-35B-A3B `Q4_K_M` | Stronger general reasoning. Needs a higher `--n-cpu-moe` value and fits only close to the 24 GB cap. |
| Qwen2.5-Coder-7B-Instruct `Q4_K_M` | Fully on GPU. Use it if RAM is needed for other work. Weaker at tool use. |

Benchmark each model on your own tasks before you switch. Public speed figures for 8 GB setups come from single community reports.

## Security

The server binds to `127.0.0.1` and requires an API key (`--api-key`). It does not listen on the network. Remote access, if needed later, goes through an SSH tunnel.
