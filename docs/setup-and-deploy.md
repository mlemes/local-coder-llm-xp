# Set up and deploy

Follow these steps to build `llama-server`, download the model, and run it as a systemd user service.

## Before you begin

You need:

- Linux with an NVIDIA driver installed (`nvidia-smi` works).
- The CUDA toolkit (`nvcc --version` works).
- `git`, `cmake`, `build-essential`, and `curl`.
- About 25 GB of free disk space.

## Configure the service

1. Copy the example environment file:

   ```bash
   cp config/local-coder.env.example ~/.config/local-coder.env
   ```

1. Edit `~/.config/local-coder.env`. Set `API_KEY` to a random value:

   ```bash
   openssl rand -hex 24
   ```

## Build llama.cpp

Run:

```bash
scripts/build.sh
```

The script clones llama.cpp into `vendor/llama.cpp` at the tag set in `LLAMA_CPP_REF` and builds `llama-server` with `-DGGML_CUDA=ON`.

## Download the model

Run:

```bash
scripts/download-model.sh
```

The script downloads the GGUF file set in `MODEL_REPO` and `MODEL_FILE` into `models/`.

## Tune GPU offload

1. Run the tuner:

   ```bash
   scripts/tune.sh
   ```

1. Copy the reported `N_CPU_MOE` value into `~/.config/local-coder.env`.

The tuner starts the server with decreasing `--n-cpu-moe` values and keeps the lowest value that leaves at least 500 MB of free VRAM.

## Install the service

1. Install and start the unit:

   ```bash
   scripts/install-service.sh
   ```

1. Check the status:

   ```bash
   systemctl --user status local-coder
   ```

1. To keep the service running after you log out, run:

   ```bash
   sudo loginctl enable-linger "$USER"
   ```

## Verify the service

Run:

```bash
scripts/smoke-test.sh
```

The test checks `/health`, sends one chat request, and sends one request with a tool definition. It fails if the response has no tool call.

## Connect a coding agent

### OpenCode

Copy `clients/opencode.json` to `~/.config/opencode/opencode.json`, then set `LOCAL_CODER_API_KEY` in your shell.

### Codex CLI

Add a provider to `~/.codex/config.toml`:

```toml
[model_providers.local]
name = "local-coder"
base_url = "http://127.0.0.1:8080/v1"
env_key = "LOCAL_CODER_API_KEY"
wire_api = "chat"
```

Run `codex --config model_provider=local --model qwen3.6-35b-a3b`.

## Update or roll back

1. Change `LLAMA_CPP_REF` or the model variables in `~/.config/local-coder.env`.
1. Run `scripts/build.sh` or `scripts/download-model.sh`.
1. Run `systemctl --user restart local-coder`.

To roll back, restore the previous values and repeat the steps.

## Troubleshoot

- **`CUDA error: out of memory`:** raise `N_CPU_MOE` by 2, or lower `CTX_SIZE` to 32768.
- **Service killed by the OOM killer:** the 24 GB `MemoryMax` cap was hit. Lower `CTX_SIZE` or use a smaller quantization.
- **The agent never calls tools:** confirm `--jinja` is in the unit and the model file is an Instruct build.
- **Logs:** run `journalctl --user -u local-coder -f`.
