#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

NVIM="${NVIM:-nvim}"

OUT="$("$NVIM" --headless --noplugin -u tests/minimal_init.lua \
  -c "lua local s = require('cursor.ui.sidebar').open(); local lines = vim.api.nvim_buf_get_lines(s.transcript_buf, 0, 12, false); print(table.concat(lines, '\n')); require('cursor.ui.sidebar').close()" \
  -c "qa!" 2>&1)"

if ! echo "$OUT" | grep -q 'cursor.nvim'; then
  echo "sidebar-smoke: expected welcome to mention cursor.nvim" >&2
  echo "$OUT" >&2
  exit 1
fi

echo "sidebar-smoke: OK"
