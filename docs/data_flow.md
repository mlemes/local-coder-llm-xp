# Data flow

## Chat request path

1. A client sends a chat request with tool definitions to `http://127.0.0.1:8080/v1/chat/completions`. The request carries the API key from `~/.config/local-coder.env` (`API_KEY`). The server binds to localhost, so the key and the request stay on the machine.
2. `llama-server` applies the Jinja chat template, reuses the cached prompt prefix (host cache capped at 2 GB), and generates tokens.
3. The server returns text and tool calls in OpenAI format. The client runs the tools locally and sends the results back as the next request.

Nothing is stored by the server except the in-memory prompt cache.

## Benchmark path

1. `bench/run.sh` reads the task list from `bench/tasks/` and the column list from `COLS`. For each column, `adapter_for`, `backend_for`, and `modes_for` pick the adapter, the model backend (`haiku`, `luna`, or `local`), and the modes (`no-loop`, plus `loop` for A and B).
2. For a local backend, the runner reads `HOST`, `PORT`, and `API_KEY` from `~/.config/local-coder.env`, checks `/health`, and starts `local-coder.service` if needed.
3. For each run, it copies `bench/tasks/<name>/starter/` into a temp directory. This is the only data the agent receives besides `prompt.md`.
4. It calls the adapter with the prompt path, the workdir, and a usage file, and sets `BACKEND`, `MODE`, and `TEST_CMD` in the environment. The adapter runs the harness headless. The model request goes one of four ways:
   - to `llama-server` on `127.0.0.1:8080`, directly or through `fix_empty_content.py`;
   - to the Anthropic or OpenAI API with a key that `_remote.sh` reads from `bench/.keys.env`, directly or through `fix_empty_content.py`;
   - to a LiteLLM proxy on `127.0.0.1:4000` that `_litellm.sh` starts, which translates Responses or Messages calls to the vendor API;
   - to the ChatGPT login, for column I on Luna.
5. After the adapter exits or the 900 s timeout kills it, the runner runs `bench/tasks/<name>/check.sh <workdir>`. The check is a Python script over the workdir contents. Its exit status is the score.
6. The runner appends one row to `bench/results.tsv` (tab-separated: task, column, run, mode, pass, seconds, status, input tokens, output tokens) and writes the adapter log and check output to `bench/logs/`.
7. For column A, the runner also records the 7-day quota utilization before and after in `bench/logs/quota.txt`.
8. `bench/matrix.sh` reads `bench/results.tsv`, groups rows by harness, model, and mode, and prints pass rate and median seconds. With `--tsv`, it writes `bench/matrix.tsv`.

The temp workdir is deleted after each run. `bench/results.tsv`, `bench/logs/`, `bench/.tools/`, `bench/.home/`, and `bench/.keys.env` are gitignored. `bench/matrix.tsv` is committed.
