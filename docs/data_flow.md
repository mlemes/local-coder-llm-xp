# Data flow

## Chat request path

1. A client sends a chat request with tool definitions to `http://127.0.0.1:8080/v1/chat/completions`. The request carries the API key from `~/.config/local-coder.env` (`API_KEY`). The server binds to localhost, so the key and the request stay on the machine.
2. `llama-server` applies the Jinja chat template, reuses the cached prompt prefix (host cache capped at 2 GB), and generates tokens.
3. The server returns text and tool calls in OpenAI format. The client runs the tools locally and sends the results back as the next request.

Nothing is stored by the server except the in-memory prompt cache.

## Benchmark path

1. `bench/run.sh` reads the task list from `bench/tasks/` and the column list from `COLS`. For local columns it reads `HOST`, `PORT`, and `API_KEY` from `~/.config/local-coder.env` and checks `/health`.
2. For each run, it copies `bench/tasks/<name>/starter/` into a temp directory. This is the only data the agent receives besides `prompt.md`.
3. It calls an adapter in `bench/adapters/` with the prompt path, the workdir, and a usage file. The adapter runs the harness headless. The harness edits files in the workdir and talks to either the Anthropic API (column A) or the local server (columns B, C, D).
4. After the adapter exits or the timeout kills it, the runner runs `bench/tasks/<name>/check.sh <workdir>`. The check is a Python script over the workdir contents. Its exit status is the score.
5. The runner appends one row to `bench/results.tsv` (tab-separated: task, column, run, mode, pass, seconds, status, input tokens, output tokens) and writes the adapter log and check output to `bench/logs/`.
6. For column A, the runner also records the 7-day quota utilization before and after in `bench/logs/quota.txt`.
7. `bench/report.sh` reads `bench/results.tsv` and prints the markdown table that goes into `docs/harness-comparison.md`.

The temp workdir is deleted after each run. `bench/results.tsv`, `bench/logs/`, and `bench/.tools/` are gitignored.
