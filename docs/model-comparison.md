# Local model comparison

Measured October 11–12, 2026 on Ryzen 5 5500X3D, RTX 3070 8 GiB, 30 GiB RAM. Evaluation units enforced MemoryMax=24G and MemorySwapMax=0. llama.cpp build: b11559, Release, CUDA, native CPU instructions. Desktop GPU usage remained present.

## Coding results

| Model and quantization | Decode tok/s | Cold agent prompt tok/s | Context | Peak RAM | Coding check |
| --- | ---: | ---: | ---: | ---: | --- |
| Qwen3-Coder-30B-A3B Q4_K_M | 24.3–24.7 | 402 | 64K | 21.0 GiB | Earlier function and unittest passed |
| Qwen3.6-35B-A3B UD-Q4_K_M | 35.5–40.6 | 342 | 64K | 22.72 GiB | 32 generated tests + 7 independent checks passed |
| Qwen3.8-27B UD-Q4_K_M | 2.7–3.3 | 306 | 32K | 23.19 GiB | 31 generated tests + 7 independent checks passed |

The original model figures come from the earlier documented Claude Code run. The two newer models implemented parse_duration and merge_intervals through OpenCode. Qwen3.6 corrected two incorrect expected values in its tests without changing its implementation. Qwen3.8 corrected implementation errors, including a misspelled constant and input parsing. Both passed independent edge cases and randomized checks afterward. Both newer models passed API chat and read_file tool calls with thinking enabled and disabled.

These are small local tasks, with different historical prompts and configurations; they do not establish a general quality ranking. Qwen3.6 is the fastest tested choice for code generation on this machine. Its tested placement was -ngl 99 --n-cpu-moe 36, with about 756 MiB free VRAM. Qwen3.8's full agent run used -ngl 18 and took about 18 minutes including repairs; Qwen3.6 took about 3 minutes 17 seconds including initial title generation.

## Code generation optimization

Every successful configuration generated 164 tokens for the same concise merge_intervals prompt: temperature 0, seed 42, thinking disabled, max_tokens 512. Outputs passed syntax checks, explicit edge cases, input immutability and 100 randomized coverage checks. Each row is one request, so small differences can be noise. Some earlier runs overlapped model storage activity. Memory peaks include mapped file/cache effects and varied between runs; one successful baseline reached the 24 GiB cap.

| Configuration | Decode tok/s | Request seconds | Result |
| --- | ---: | ---: | --- |
| layer18-t6 | 3.32 | 50.91 | Pass |
| ffn64-t6 | — | — | less than 500 MB VRAM headroom |
| ffn64-t4 | — | — | less than 500 MB VRAM headroom |
| ffn64-t8 | — | — | less than 500 MB VRAM headroom |
| ffn64-mtp2 | — | — | model did not load |
| ffn64-mtp2-no-graphs | — | — | model did not load |
| ffn64-ngram | — | — | less than 500 MB VRAM headroom |
| gpu60-ffn64-t6 | 3.47 | 48.60 | Pass |
| gpu60-ffn64-t4 | 3.44 | 49.03 | Pass |
| gpu60-ffn64-t8 | 3.33 | 50.73 | Pass |
| gpu48-ffn64-t6 | 3.27 | 51.55 | Pass |
| gpu48-ffn64-mtp2 | 5.15 | 33.70 | Pass |
| gpu48-ffn64-mtp2-no-graphs | 5.85 | 29.74 | Pass |
| gpu60-ffn64-ngram | 3.41 | 49.58 | Pass |
| gpu48-ffn64-mtp4-no-graphs | 4.86 | 35.65 | Pass |
| gpu48-ffn64-mtp6-no-graphs | 4.90 | 35.16 | Pass |

Best measured profile: **gpu48-ffn64-mtp2-no-graphs**, 5.85 tok/s, 29.74 seconds including prompt processing. Saved executable: `~/.config/local-coder-tests/run-qwen38-codegen.sh`. It sources the existing private qwen38.env for authentication and binds localhost port 8099.

The useful change was the embedded MTP draft head, with CUDA graphs disabled. FFN CPU placement alone brought only a small gain; 4/6/8 CPU threads were similar and ngram speculation did not help this prompt. More GPU layers with MTP failed allocation; the 64-layer non-MTP placement left less than our 500 MiB benchmark headroom threshold and was skipped. MTP needs extra rollback state, so GPU placement was reduced to 48 layers.

Best flags: `-ngl 48 --n-cpu-ffn 64 -c 8192 -ub 128 -t 6 --spec-type draft-mtp --spec-draft-n-max 2`, flash attention on, q8_0 K/V caches, one slot, batch threads 6, `GGML_CUDA_DISABLE_GRAPHS=1`, reasoning off. This **8K context profile was validated for short code generation**, not the earlier full agent task, which used more than 8K context. No additional draft model or vision projector is needed. Keep model weights on SSD to improve loading; storage changes do not guarantee improved resident decode speed.

## Storage and artifacts

- Original Qwen3-Coder: `<storage>/local-coder-llm/models/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf`.
- Qwen3.6: `<storage>/local-coder-llm/models/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf`, 22,134,528,992 bytes. SHA256 verified after moving: `ac0e2c1189e055faa36eff361580e79c5bd6f8e76bffb4ce547f167d53e31a61`.
- Qwen3.8: `<storage>/local-coder-llm/models/Qwen3.8-27B-UD-Q4_K_M.gguf`, linked from the repository models directory. SHA256: `322e194ff79741c7baa497c240f677f54b201b0efab44ca8e50f122b39123482`.
- Repository model links point to the current external locations.
- Full agent artifacts: `<storage>/local-coder-llm/tests/qwen36-2026-10-11/` and `qwen38-2026-10-11/`.
- Optimization measurements, generated code, checks and logs: `<storage>/local-coder-llm/tests/codegen-optimizations-2026-10-11/`. Logs include earlier invocations of the reused evaluation unit; JSON records identify each configuration.

All temporary evaluation services were stopped. After the tests, Qwen3.6 was selected as the default in local-coder.env and the sample OpenCode client. The main service is enabled and runs on localhost:8080 with the tested 64K context, 36 CPU expert layers, a 128-token physical batch, temperature 0.6, top-p 0.95, min-p 0, repeat penalty 1.0 and reasoning budget 2048. Qwen3.8 was moved to HDD1 with its SHA256 verified.

## References

- [Qwen3.6 model card](https://huggingface.co/Qwen/Qwen3.6-35B-A3B)
- [Qwen3.8 model card](https://huggingface.co/Qwen/Qwen3.8-27B)
- [llama.cpp speculative decoding](https://github.com/ggml-org/llama.cpp/blob/master/docs/speculative.md)
- [CPU FFN offload and CUDA graph discussion](https://github.com/ggml-org/llama.cpp/issues/27987)

Further tuning of the selected default: [Qwen3.6 code generation results](qwen36-optimization.md).
