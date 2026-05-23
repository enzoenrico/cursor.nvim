#!/usr/bin/env bash
# Stand-in for `cursor-agent` used by the test suite. Reads any -p prompt
# and emits a deterministic stream-json payload so tests can exercise the
# real parser without network access.

prompt=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p)
      shift
      prompt="$1"
      ;;
    --print|--output-format=*|--model)
      :
      ;;
    *)
      :
      ;;
  esac
  shift || true
done

cat <<EOF
{"type":"agent_created","agent_id":"bc-fake-1","model":"fake-model"}
{"type":"assistant","text":"echo: ${prompt}"}
{"type":"task","text":"done"}
EOF
