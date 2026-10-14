# Agent instructions

- Keep the repository small: shell scripts, one env file, and one systemd unit. Do not add Docker or a framework.
- The only Python allowed is `bench/adapters/fix_empty_content.py`, a stdlib proxy that fixes `llama-server` Responses API output for the benchmark. Do not add other services.
- Do not download models or start the service in CI-like checks. Use `bash -n` and `shellcheck` for static checks, and `bash bench/selftest.sh` for the benchmark.
- Do not commit model files, `.env`, `bench/.keys.env`, `bench/.home/`, `bench/.tools/`, or build output.
- Update `docs/architecture.md` and `docs/data_flow.md` in the same change as the code.
- `docs/plan.md` is the original serving plan and is complete.
