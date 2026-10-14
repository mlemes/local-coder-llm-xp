# Qwen3.6 code generation tuning

Measured October 12, 2026 on the same Ryzen 5 5500X3D / RTX 3070 machine, llama.cpp b11559. Model: Qwen3.6-35B-A3B-UD-Q4_K_M.gguf on SSD32. Temporary benchmark units used MemoryMax=24G, MemorySwapMax=0 and port 8099. The main service was stopped during the benchmarks to avoid simultaneous model loads.

## Method

Same merge_intervals code-only prompt and correctness checker as the Qwen3.8 optimization experiment: temperature 0, seed 42, thinking disabled, max_tokens 512. Check syntax, required edge cases, invalid pairs, input immutability and 100 randomized coverage cases. Most settings emitted the same 254 tokens; the 34-CPU-layer placement emitted 362 tokens and the 37-layer repeat emitted 382 tokens, so its elapsed time is not directly comparable as a fixed-length decode test. Repeated profiles have three successive requests; later requests benefit from prompt caching. Rates below are decode timings, and request times include prompt processing. These are short local samples, not a broad quality benchmark.

| Configuration | Decode tokens/sec | Last output tokens | Last request seconds | Free VRAM MiB | Correctness |
| --- | ---: | ---: | ---: | ---: | --- |
| moe36-c64k-t6 | 36.48 | 254 | 7.877 | 1051 | pass |
| moe36-c8k-t6 | 43.43 | 254 | 6.725 | 1701 | pass |
| moe36-c8k-t4 | 36.78 | 254 | 7.818 | 1703 | pass |
| moe36-c8k-t8 | 41.23 | 254 | 7.062 | 1699 | pass |
| moe34-c8k-t6 | 44.59 | 362 | 8.917 | 732 | pass |
| moe35-c8k-t6 | 43.46 | 254 | 6.714 | 1196 | pass |
| moe36-c8k-t6-no-graphs | 33.40 | 254 | 8.519 | 1672 | pass |
| moe36-c8k-ngram | 42.75 | 254 | 6.814 | 1665 | pass |
| moe36-c64k-t6-repeat | 0.00 | — | — | 439 | less than 500 MB VRAM headroom |
| moe36-c8k-t6-repeat | 40.52–43.92 (median 43.58) | 254 | 5.858 | 2606 | pass |
| moe36-c64k-ub128-t6-repeat | 43.43–43.96 (median 43.87) | 254 | 5.864 | 2018 | pass |
| moe37-c64k-ub128-t6-repeat | 38.24–42.99 (median 40.51) | 382 | 8.964 | 2635 | pass |

## Decisions

Keep six CPU threads and CUDA graphs enabled. Four threads were slower; eight did not beat six. Disabling graphs hurt performance, unlike the Qwen3.8 MTP case. Ngram speculation did not improve this short prompt. More GPU experts gave a small per-token gain but reduced VRAM headroom; it did not consistently shorten the complete request.

The default remains Qwen3.6 with 64K context and 36 CPU expert layers, now using a smaller 128-token physical prompt-processing batch (-ub 128). The repeated 64K profile measured 43.4–44.0 tok/s on this short code prompt, essentially matching the repeated 8K profile. This preserves the larger context for agent sessions. Longer prompt processing with this smaller batch was not benchmarked; decode speed is the focus here. Desktop VRAM use changed during the sweep, so differences across configurations cannot all be attributed to the flags alone. One 64K repeat with the larger batch was skipped after falling below the 500 MiB headroom threshold. A separate short-generation profile is saved at `~/.config/local-coder-tests/run-qwen36-codegen.sh`: 8K context, six threads, 36 CPU expert layers, graphs enabled, thinking disabled by default. It binds localhost:8099 and sources the private qwen36.env for authentication. Stop the main service before running this alternate profile; this GPU cannot host both models concurrently.

The existing GGUF has qwen35moe.block_count=40 and no nextn/MTP metadata or tensors, verified by reading its GGUF header and tensor index. Therefore embedded MTP cannot be enabled on this file. [Unsloth publishes a separate MTP GGUF variant](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF/tree/main); it was not downloaded or substituted in this experiment.

Loading from SSD32 took about 67–73 seconds per run. Several cgroup memory peaks reached 24 GiB, including mapped file cache; all measured generations completed, but this is a tight RAM budget. The full earlier coding task passed 32 generated tests and 7 independent checks; this tuning experiment adds checks of a shorter code generation prompt only.

Artifacts and reproducible benchmark scripts: `<storage>/local-coder-llm/tests/qwen36-optimizations-2026-10-12/`. Logs contain earlier invocations of the reused unit; results.jsonl identifies the configurations. The main default service was restored after benchmarking.
