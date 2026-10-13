# Sourced by adapters. Sets PROV_* for BACKEND=haiku|luna (API keys from bench/.keys.env).
# Local runs set nothing. Keys are read here, never exported by the runner, so the
# claude wrapper keeps using the subscription login.
: "${BACKEND:=local}"
case $BACKEND in
  haiku) PROV_NAME=anthropic PROV_MODEL=claude-haiku-5-5 PROV_URL=https://api.anthropic.com/v1 KEYVAR=ANTHROPIC_API_KEY ;;
  luna) PROV_NAME=openai PROV_MODEL=gpt-6-luna PROV_URL=https://api.openai.com/v1 KEYVAR=OPENAI_API_KEY ;;
  *) PROV_NAME="" ;;
esac
if [ -n "$PROV_NAME" ]; then
  # shellcheck disable=SC1091
  PROV_KEY=$(sed -n "s/^$KEYVAR=//p" "$(dirname "${BASH_SOURCE[0]}")/../.keys.env")
  [ -n "$PROV_KEY" ] || { echo "missing $KEYVAR in bench/.keys.env" >&2; exit 1; }
fi
