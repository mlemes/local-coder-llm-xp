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

### Separate Claude Code cloud and local commands

`claude` uses the existing claude.ai login and cloud model settings. `claude-local` uses local Qwen through the server's Anthropic-compatible `/v1/messages` endpoint.

Install the local launcher and its separate settings file:

```bash
install -m 755 scripts/claude-local.sh ~/.local/bin/claude-local
install -m 600 clients/claude-local.json ~/.config/local-coder-claude.json
```

Run `claude-local` from your project. It reads the API key from `~/.config/local-coder.env`, starts the service, waits for health, and launches Claude Code with the local endpoint and configured context window. Its `--settings` file adds “Qwen3.6 Local” to the picker only for the local launch. Endpoint and credentials apply only to that process, so ordinary `claude` retains its cloud configuration and claude.ai connectors.

Local sessions show a warning that claude.ai connectors are disabled because local credentials take precedence. That warning is expected for `claude-local`. Do not put the local endpoint, local apiKeyHelper, or Qwen default in global `~/.claude/settings.json` when using these separate commands. Each launch has one endpoint; switching local and cloud models within one session requires a routing gateway. [Claude Code custom model documentation](https://code.claude.com/docs/en/model-config#add-a-custom-model-option).

### Run code-only subagents from Claude Code

The `local-coder` subagent lets your normal Claude Code session hand coding tasks to the local model. It runs `claude-local-code`, a headless Claude Code run with these limits:

- `--bare` skips hooks, plugins, and `CLAUDE.md`, which keeps the prompt small for the 64K context.
- A short system prompt names the working directory, sets rules for exact-match edits, minimal diffs, and style matching, and asks for code changes only.
- Only the `Read`, `Edit`, `Write`, `Glob`, and `Grep` tools are available. The model cannot run commands.
- With `--test "<cmd>"`, the wrapper runs the test command after each edit and sends any failure back to the model. When the same test fails 3 times, Gemini (`agy -p --mode plan`, no edits) diagnoses the cause, and the next attempt gets that diagnosis. The wrapper stops when the tests pass or after `--max` attempts (default 8). You still verify the result.

Install it:

```bash
install -m 755 scripts/claude-local-code.sh ~/.local/bin/claude-local-code
install -m 644 clients/agents/local-coder.md ~/.claude/agents/local-coder.md
```

Ask Claude Code to use the `local-coder` agent, or run `claude-local-code [--test "<cmd>"] "task"` from a repository root.

### Start after reboot and login with a removable model drive

The enabled user service starts when you log in. If the model lives on a removable drive, set `MODEL_DRIVE_UUID` in the private environment file. Obtain it with `lsblk -f`. Optionally set `MODEL_DRIVE_RELATIVE_PATH` to the model file relative to the drive root; the default is `local-coder-llm/models/$MODEL_FILE`.

The runner resolves the mount by UUID, asks `udisksctl` to mount it when needed, and reads the model directly from the resulting mount point. This handles a changed mount path after reboot without relying on a repository symlink. The service retries every ten seconds if the drive is not ready. User-session mounting requires the drive to be connected and the desktop session to authorize UDisks mounting. Startup before login still requires administrator-configured drive mounting and lingering; this installation uses startup after login.

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
- **Service killed by the OOM killer:** the 24 GB `MemoryMax` cap was hit. The model takes about 17.7 GB resident, and llama.cpp's host prompt cache defaults to 8 GB, so `run.sh` caps it with `--cache-ram 2048`. If it still happens, lower `CTX_SIZE` or use a smaller quantization.
- **The agent never calls tools:** confirm `--jinja` is in the unit and the model file is an Instruct build.
- **Logs:** run `journalctl --user -u local-coder -f`.
