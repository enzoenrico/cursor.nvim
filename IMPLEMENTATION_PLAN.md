# cursor.nvim — Implementation Plan v1

`cursor.nvim` is a Neovim plugin that wraps the [Cursor SDK](https://www.npmjs.com/package/@cursor/sdk) (and the `cursor-agent` CLI it ships) so a Neovim user can create, observe, and chat with Cursor cloud or local agents from inside the editor.

This plan is the source of truth for the orchestrate workers building v0.1. It was authored by the root planner (orchestrate run `cursor-nvim`) before any worker was spawned, so workers do not have to re-discover scope.

## North star

```
:CursorChat                 -- open a chat buffer wired to a fresh Cursor agent
:CursorAsk "<prompt>"       -- one-shot prompt; output streams into a scratch buffer
:CursorStop                 -- cancel the in-flight run
:checkhealth cursor         -- verify cursor-agent / Node availability
```

Default keymaps (under `<leader>c`) are registered only if the user opts in via `setup({ keymaps = true })`.

## Architecture

### Backend: `cursor-agent` CLI subprocess

The Cursor SDK's official entry point for terminal use is the `cursor-agent` binary (`npm i -g cursor-agent`). The plugin shells out to it via `vim.fn.jobstart`, streams stdout/stderr back into Neovim, and parses the streamed JSON envelope it emits.

Why CLI rather than embedding `@cursor/sdk` directly:

- The SDK is a Node library; embedding would require shipping a Node helper script and a `package.json` inside the plugin. The CLI already does that for us.
- The CLI is the SDK's own supported shell-out boundary.
- It keeps `cursor.nvim` runtime-pure Lua + `vim.system` / `jobstart`. No bundled Node, no build step.

Concretely, the plugin runs:

```
cursor-agent --print --output-format=stream-json --model=<model> -p <prompt>
```

…and consumes the JSON-lines stream. `--output-format=stream-json` is the public flag for machine-readable streaming output.

The plugin must degrade gracefully when `cursor-agent` is not on `$PATH`: every command surfaces a friendly `:checkhealth cursor` reminder and returns without erroring.

### Lua layout

```
lua/cursor/
  init.lua          -- public API: setup, ask, chat, stop, status
  config.lua        -- defaults + user-supplied overrides; vim.tbl_deep_extend
  health.lua        -- :checkhealth cursor
  agent.lua         -- spawn cursor-agent, parse stream-json, emit events
  ui/
    chat.lua        -- chat buffer + prompt + window layout
    util.lua        -- shared buffer/window helpers
plugin/cursor.lua   -- ex commands + autocmd group
doc/cursor.txt      -- :help cursor
```

`plugin/cursor.lua` only registers commands. Everything else is loaded lazily on first call. This keeps startup time below the 1ms guideline lazy-loaders care about.

### Public Lua API (in `lua/cursor/init.lua`)

```lua
local cursor = require("cursor")

cursor.setup({
  cmd      = "cursor-agent",   -- override path or args
  model    = nil,              -- nil = SDK default
  keymaps  = false,            -- true installs <leader>c* defaults
  ui       = { layout = "vsplit" },  -- vsplit | float | tab
})

cursor.ask("explain this function", { context = "buffer" })
cursor.chat()
cursor.stop()
cursor.status()  -- returns { running = bool, agent_id = str|nil, model = str|nil }
```

### Ex commands (in `plugin/cursor.lua`)

| Command            | Description                                             |
| ------------------ | ------------------------------------------------------- |
| `:CursorChat`      | Open a chat buffer + prompt window for a fresh agent.   |
| `:CursorAsk {arg}` | Quick one-shot prompt; output streams to a split panel. |
| `:CursorStop`      | Cancel the currently running agent run.                 |
| `:CursorStatus`    | Echo `cursor.status()` to `:messages`.                  |

### Streaming envelope handling

`cursor-agent --output-format=stream-json` emits one JSON object per line. The plugin must:

1. Buffer stdout into newline-delimited records (jobstart can split on newline natively, but parse defensively).
2. Decode each record with `vim.json.decode` inside `pcall`.
3. Dispatch on the `type` field (`assistant`, `tool_call`, `status`, `task`, `thinking`).
4. Append `assistant.text` to the chat buffer, scroll-to-end after each chunk.
5. On terminal events, mark the run done and refresh status.

Chat UI redraws on `vim.schedule` so `vim.api` calls happen on the main loop.

### `:checkhealth cursor`

`lua/cursor/health.lua` reports:

- Whether `cursor-agent` is on `$PATH` (`vim.fn.executable("cursor-agent") == 1`).
- The CLI version (`cursor-agent --version`, captured via `vim.system`).
- Whether `vim.json` is available (it is on Neovim ≥ 0.10, our floor).
- The currently configured `cmd` and `model`.

## Acceptance criteria for v0.1

A v0.1 ship requires every item below:

1. `require("cursor").setup({})` succeeds in a headless Neovim with no errors.
2. `:CursorChat` registers and is callable. With `cursor-agent` absent it surfaces a single warning notification (no Lua stack traces).
3. `:CursorAsk "ping"` runs to a clean exit when `cursor-agent` is mocked to `cat`. Streamed text lands in a buffer.
4. `:checkhealth cursor` produces structured `vim.health` output (`ok`/`warn`/`error`) for the CLI presence check.
5. `doc/cursor.txt` is real `:help cursor` content (tag, brief, commands list).
6. `README.md` documents lazy.nvim, packer, and vim-plug installation snippets and the `setup()` shape.
7. `stylua` and `luacheck` pass on the plugin's Lua sources (config in repo).
8. CI (GitHub Actions) runs stylua + luacheck + busted/plenary on push and PR.

## Out of scope for v0.1 (named so workers don't try)

- ACP (Agent Client Protocol) integration.
- Tab/inline completions.
- Multiple concurrent chats.
- Persistent chat history.
- MCP server discovery.
- Telescope/snacks integrations beyond a hook the user can wire up.

These are reserved for v0.2+. v0.1 is a deliberately small, working baseline that makes adding the rest mechanical.

## Worker decomposition

| Worker         | Owns                                                 | Output branch placeholder         |
| -------------- | ---------------------------------------------------- | --------------------------------- |
| `core-plugin`  | Scaffold + commands + agent backend + README + docs  | `orch/cursor-nvim/core-plugin`    |
| `chat-ui`      | `lua/cursor/ui/*` and chat-rendering wiring          | `orch/cursor-nvim/chat-ui`        |
| `tests-and-ci` | `lua/cursor/_spec/` and `.github/workflows/ci.yml`   | `orch/cursor-nvim/tests-and-ci`   |
| `merge-v0-1`   | Merge the three above into a single deliverable      | `orch/cursor-nvim/merge-v0-1`     |
| `verify-v0-1`  | Verifier — runs acceptance criteria above            | `orch/cursor-nvim/verify-v0-1`    |

`merge-v0-1` is gated on all three feature workers; `verify-v0-1` runs against `merge-v0-1`.

`chat-ui` builds on top of `core-plugin`'s `lua/cursor/agent.lua`, so it `dependsOn: ["core-plugin"]` and starts from `orch/cursor-nvim/core-plugin`. `tests-and-ci` is independent and starts from `main`.
