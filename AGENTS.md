# AGENTS.md

## Cursor Cloud specific instructions

This is a **Neovim plugin** (pure Lua, no build step). The development loop is `make lint && make test`.

### Services

| Service | How to run | Notes |
|---|---|---|
| Lint | `make lint` | Runs `stylua --check lua/ plugin/` then `luacheck lua/ plugin/` |
| Tests | `make test` | Runs plenary busted suite headless via `nvim --headless` |

### Gotchas

- **plenary.nvim** must be cloned into `.deps/plenary.nvim` before tests will work. The update script handles this.
- `tests/fake-cursor-agent.sh` must be executable (`chmod +x`) before tests run. The update script handles this.
- The Neovim binary is installed at `/workspace/nvim-linux-x86_64/bin/nvim` and symlinked to `/usr/local/bin/nvim`. If the symlink breaks, re-link it.
- Tests emit expected `vim.notify` warnings (e.g., "ask() requires a prompt") to stderr — these are part of the test suite, not failures.
- There is no build step and no Node.js runtime required for development/testing. The `cursor-agent` CLI is only needed for real end-to-end usage and is mocked in tests.
- To exercise the plugin interactively headless: `nvim --headless --noplugin -u tests/minimal_init.lua -c "CursorAsk hello" -c "lua vim.defer_fn(function() vim.cmd('qa!') end, 500)"`
