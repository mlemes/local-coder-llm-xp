# Implementation plan

Implement the service described in `architecture.md` and `setup-and-deploy.md`. Do the tasks in order. Each task ends with a check that must pass.

## Target layout

```text
config/local-coder.env.example
scripts/build.sh
scripts/download-model.sh
scripts/run.sh
scripts/tune.sh
scripts/install-service.sh
scripts/smoke-test.sh
systemd/local-coder.service
clients/opencode.json
.gitignore
```

## Task 1: Add the config and ignore rules (done)

1. Create `config/local-coder.env.example` with these variables: `LLAMA_CPP_REF` (a pinned release tag), `MODEL_REPO=unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF`, `MODEL_FILE=Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf`, `HOST=127.0.0.1`, `PORT=8080`, `API_KEY=`, `CTX_SIZE=65536`, `N_CPU_MOE=48`, `THREADS=6`, `MODEL_ALIAS=qwen3-coder`.
1. Create `.gitignore` for `vendor/`, `models/`, and `.env`.

Check: `grep -c = config/local-coder.env.example` prints 10.

## Task 2: Build llama.cpp (done)

Write `scripts/build.sh`. It sources the env file (default `~/.config/local-coder.env`, overridable with `LOCAL_CODER_ENV`), clones or fetches llama.cpp into `vendor/llama.cpp`, checks out `LLAMA_CPP_REF`, and builds the `llama-server` target with `-DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release`. It is safe to run twice.

Check: `vendor/llama.cpp/build/bin/llama-server --version` succeeds.

## Task 3: Download the model (done)

Write `scripts/download-model.sh`. It downloads `https://huggingface.co/$MODEL_REPO/resolve/main/$MODEL_FILE` into `models/` with `curl -L -C -` so interrupted downloads resume. It skips the download if the file exists.

Check: `models/$MODEL_FILE` exists and is larger than 15 GB.

## Task 4: Write the run script (done)

Write `scripts/run.sh`. It sources the env file and `exec`s `llama-server` with:

```text
-m models/$MODEL_FILE --alias $MODEL_ALIAS --host $HOST --port $PORT
--api-key $API_KEY --jinja -ngl 99 --n-cpu-moe $N_CPU_MOE
-c $CTX_SIZE -fa on --cache-type-k q8_0 --cache-type-v q8_0
--parallel 1 --threads $THREADS -lm none
--temp 0.7 --top-p 0.8 --top-k 20 --repeat-penalty 1.05
```

The sampling values are the model card defaults. The script exits with an error if `API_KEY` is empty.

Check: `bash -n scripts/run.sh` and `shellcheck scripts/*.sh` pass.

## Task 5: Write the tuner (done)

Write `scripts/tune.sh`. For `N` from 48 down to 0 in steps of 4, it starts `run.sh` with `N_CPU_MOE=N` and a test port, waits for `/health`, reads free VRAM with `nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits`, then stops the server. It prints the lowest `N` that loads and leaves at least 500 MB free, plus decode speed from one 200-token request (`timings.predicted_per_second` in the response).

Check: it prints one `N_CPU_MOE=` line.

## Task 6: Add the systemd unit (done)

1. Write `systemd/local-coder.service` as a user unit. Set `ExecStart` to the absolute path of `scripts/run.sh` (the installer fills it in), `Restart=on-failure`, `MemoryMax=24G`, and `MemorySwapMax=0`.
1. Write `scripts/install-service.sh`. It renders the unit into `~/.config/systemd/user/`, runs `systemctl --user daemon-reload`, and runs `systemctl --user enable --now local-coder`.

Check: `systemd-analyze --user verify ~/.config/systemd/user/local-coder.service` passes.

## Task 7: Add the smoke test (done)

Write `scripts/smoke-test.sh`. With `curl` and `jq`, it:

1. Checks that `GET /health` returns `ok`.
1. Sends a chat request and checks for non-empty `choices[0].message.content`.
1. Sends a request with a `read_file` tool and the prompt "Read README.md". It checks that `choices[0].message.tool_calls[0].function.name` equals `read_file`.

It exits non-zero on any failure.

Check: the script passes against the running service.

## Task 8: Add the client config (done)

Write `clients/opencode.json` with one provider using `@ai-sdk/openai-compatible`, `baseURL` `http://127.0.0.1:8080/v1`, the API key from `{env:LOCAL_CODER_API_KEY}`, and model `qwen3-coder` with a 65536 context limit.

Check: `jq . clients/opencode.json` succeeds.

## Task 9: Run an end-to-end agent check (done)

Run OpenCode against the service in a scratch repository. Ask it to add a function and a test, then run the test. Record decode speed, prompt processing speed, and peak RAM (`systemctl --user show local-coder -p MemoryPeak`) in `docs/architecture.md` under a new "Measured performance" section.

Check: the agent edits files through tool calls and the test passes.

## Out of scope

- Autocomplete and fill-in-the-middle.
- Multiple concurrent users or slots.
- Docker, reverse proxies, and remote access.
