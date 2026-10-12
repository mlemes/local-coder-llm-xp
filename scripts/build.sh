#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${LOCAL_CODER_ENV:-$HOME/.config/local-coder.env}"
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
SRC="$ROOT/vendor/llama.cpp"
if [ -d "$SRC/.git" ]; then
  git -C "$SRC" fetch --tags origin
else
  mkdir -p "$ROOT/vendor"
  git clone https://github.com/ggml-org/llama.cpp "$SRC"
fi
git -C "$SRC" checkout "$LLAMA_CPP_REF"
cmake -S "$SRC" -B "$SRC/build" -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
cmake --build "$SRC/build" --target llama-server -j "$(nproc)"
