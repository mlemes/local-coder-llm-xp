#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/.config/systemd/user"
mkdir -p "$DEST"
sed "s|@ROOT@|$ROOT|g" "$ROOT/systemd/local-coder.service" > "$DEST/local-coder.service"
systemctl --user daemon-reload
systemctl --user enable --now local-coder
