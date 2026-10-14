# Local coder LLM

Run a local LLM for agentic coding on one machine with an 8 GB GPU and up to 24 GB of system RAM. Then measure which coding agent harness works best with it.

The repository has two parts:

- **Serving:** shell scripts that build `llama.cpp`, run Qwen3.6-35B-A3B as a systemd user service, and expose an OpenAI-compatible endpoint on `127.0.0.1:8080`.
- **Benchmark:** `bench/`, a shell-only runner that scores eight coding agent harnesses on five tasks with three models (Claude Haiku, OpenAI Luna, and the local Qwen).

## Results

Short version: a strong model passes almost everything in any harness. A weak local model passes between 4/15 and 12/15 depending on the harness, and a test loop lifts it to 15/15. See [harness comparison](docs/harness-comparison.md) for the matrix, or read the [article](docs/article.md).

## Documentation

- [Architecture](docs/architecture.md)
- [Data flow](docs/data_flow.md)
- [Setup and deployment](docs/setup-and-deploy.md)
- [Harness comparison](docs/harness-comparison.md)
- [Article: eight harnesses, three models, 405 runs](docs/article.md)
- [Local model tests and tuning](docs/model-comparison.md)
- [Qwen3.6 code generation results](docs/qwen36-optimization.md)
- [Token-saving research](docs/token-saving-research.md)
- [Original implementation plan](docs/plan.md)

## Run the benchmark

1. Run `bash bench/selftest.sh`. It needs no model and no network.
2. Put `ANTHROPIC_API_KEY` and `OPENAI_API_KEY` in `bench/.keys.env` if you run the Haiku or Luna columns.
3. Run `COLS="A C@luna I" RUNS=3 bench/run.sh`.
4. Run `bench/matrix.sh` for the table, or `bench/matrix.sh --tsv` for tab-separated output.

## License

MIT. See [LICENSE](LICENSE).
