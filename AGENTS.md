# Agent instructions

- Implement the tasks in `docs/plan.md` in order. Mark each task done in that file when its check passes.
- Keep the repository small: shell scripts, one env file, and one systemd unit. Do not add Docker, Python services, or a proxy unless the plan says so.
- Do not download models or start the service in CI-like checks. Use `bash -n` and `shellcheck` for static checks.
- Do not commit model files, `.env`, or build output.
