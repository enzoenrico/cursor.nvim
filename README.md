# cursor.nvim

A Neovim sidebar for the [Cursor agent CLI](https://docs.cursor.com) — chat with Cursor agents, edit selections, apply diffs, and browse history without leaving Neovim.

The plugin shells out to `cursor-agent --print --output-format=stream-json -p <prompt>` and parses the resulting JSON-line stream. No Node embedding or build step required.

## Requirements

- Neovim 0.10+
- The [`cursor-agent`](https://docs.cursor.com) CLI on your `$PATH`
- Optional: [`render-markdown.nvim`](https://github.com/MeanderingProgrammer/render-markdown.nvim) for richer transcript rendering (`CursorChat` filetype uses markdown treesitter)

## Installation

### lazy.nvim

```lua
{
  "enzoenrico/cursor.nvim",
  cmd = {
    "CursorChat",
    "CursorAsk",
    "CursorStop",
    "CursorStatus",
    "CursorVersion",
    "CursorToggle",
    "CursorFocus",
    "CursorNew",
    "CursorEdit",
    "CursorHistory",
    "CursorModel",
    "CursorZen",
    "CursorApply",
    "CursorApplyAll",
    "CursorDebug",
    "CursorLog",
    "CursorLogClear",
  },
  opts = {
    keymaps = true,
  },
}
```

### packer.nvim

```lua
use({
  "enzoenrico/cursor.nvim",
  config = function()
    require("cursor").setup({ keymaps = true })
  end,
})
```

### vim-plug

```vim
Plug 'enzoenrico/cursor.nvim'

lua << EOF
require("cursor").setup({ keymaps = true })
EOF
```

## Setup

1. Install the plugin with your package manager (see above).
2. Ensure `cursor-agent` is on your `$PATH`.
3. Call `setup()` once during startup (lazy.nvim `opts` handles this automatically).

```lua
require("cursor").setup({
  cmd = "cursor-agent",
  keymaps = true,
})
```

Verify everything is wired up:

```vim
:checkhealth cursor
:CursorToggle
```

## Usage

### Sidebar

Open the sidebar with `:CursorToggle` or `:CursorChat`. The sidebar shows a transcript, a prompt input, and a winbar with the active model and run status.

In the prompt input:

- `<C-s>` submits in insert mode; `<CR>` submits in normal mode
- `@` opens a file picker to attach file context
- `<Tab>` switches focus between transcript and input
- `q` or `<C-c>` cancels input
- `/clear`, `/new`, and `/compact` are slash commands for chat management

Project instructions from `.cursor.md` or `.cursorcontext` in the repo root are included automatically when present.

### Commands

| Group | Command | Description |
| --- | --- | --- |
| Sidebar | `:CursorToggle` | Toggle the sidebar |
| Sidebar | `:CursorChat` | Open the sidebar |
| Sidebar | `:CursorFocus` | Toggle focus between sidebar and code |
| Sidebar | `:CursorNew` | Start a new conversation |
| Sidebar | `:CursorZen` | Toggle zen mode (hide other windows) |
| Prompting | `:CursorAsk {prompt}` | Open sidebar and send a one-shot prompt |
| Prompting | `:CursorEdit` | Edit the current visual selection (visual range) |
| Agent | `:CursorStop` | Cancel the running agent |
| Agent | `:CursorStatus` | Print `{ running, agent_id, model }` |
| Agent | `:CursorModel` | Pick a model |
| History | `:CursorHistory` | Browse saved conversations |
| Diff | `:CursorApply` | Apply the cursor suggestion at the cursor |
| Diff | `:CursorApplyAll` | Apply all cursor suggestions in the buffer |
| Debug | `:CursorDebug` | Toggle debug logging |
| Debug | `:CursorLog` | Open the debug log in a split |
| Debug | `:CursorLogClear` | Clear the debug log |
| Meta | `:CursorVersion` | Print `cursor.nvim v<version>` |
| Meta | `:checkhealth cursor` | Verify CLI and Neovim requirements |

### Keymaps

When `setup({ keymaps = true })` is set:

| Keymap | Action |
| --- | --- |
| `<leader>ct` | Toggle sidebar |
| `<leader>cf` | Toggle focus |
| `<leader>cc` | Open chat |
| `<leader>ca` | Prompt for input, then ask |
| `<leader>cn` | New conversation |
| `<leader>ce` | Edit visual selection |
| `<leader>ch` | Conversation history |
| `<leader>cm` | Model picker |
| `<leader>cz` | Zen mode |
| `<leader>cb` | Add current buffer to context |
| `<leader>cs` | Stop agent |
| `<leader>c?` | Status |

In visual mode, inline hints show `<leader>ca` (ask) and `<leader>ce` (edit) when `ui.show_hints` is enabled.

Inside the sidebar transcript:

| Keymap | Action |
| --- | --- |
| `]]` | Next message |
| `[[` | Previous message |
| `a` | Apply suggestion |
| `A` | Apply all suggestions |

When the agent inserts git-style conflict markers (`<<<<<<< HEAD` / `=======` / `>>>>>>> Cursor`):

| Keymap | Action |
| --- | --- |
| `co` | Keep current (ours) |
| `ct` | Keep incoming (theirs) |
| `ca` | Accept all incoming |
| `cb` | Keep both sides |
| `]x` | Next conflict |
| `[x` | Previous conflict |

All diff keymaps are configurable under `diff` in setup (see below).

## Configuration

```lua
require("cursor").setup({
  cmd = "cursor-agent",   -- override path or args, e.g. "node bin/agent.js"
  model = nil,              -- nil = SDK default; e.g. "gpt-5.5-high"
  keymaps = true,           -- install the default <leader>c* maps
  debug = false,            -- toggle at runtime with :CursorDebug
  notify = true,            -- vim.notify on errors
  ui = {
    layout = "right",       -- "right" | "left" | "top" | "bottom"
    width = 30,             -- sidebar width as a percentage
    prompt_height = 8,
    transcript_filetype = "CursorChat",
    prompt_prefix = "> ",
    show_hints = true,
    welcome = true,
  },
  history = {
    enabled = true,
    path = nil,               -- default: stdpath("data")/cursor_nvim/history/
  },
  diff = {
    ours = "co",
    theirs = "ct",
    all_theirs = "ca",
    both = "cb",
    next = "]x",
    prev = "[x",
  },
  selection = {
    hints = "delayed",        -- show visual-mode key hints after a short delay
  },
  mappings = {
    -- full override table; see lua/cursor/config.lua for all defaults
    toggle = "<leader>ct",
    submit = { normal = "<CR>", insert = "<C-s>" },
  },
})
```

Debug logs are written to `$(stdpath("log"))/cursor_nvim.log` when `debug = true`.

## Lua API

```lua
local cursor = require("cursor")

cursor.setup({ keymaps = true })
cursor.chat()              -- open sidebar
cursor.toggle()            -- toggle sidebar
cursor.focus()             -- toggle focus
cursor.new_chat()          -- new conversation
cursor.ask("explain this") -- open sidebar and submit prompt
cursor.edit()              -- edit visual selection
cursor.stop()
cursor.status()            --> { running, agent_id, model }
cursor.version()           --> "0.1.0"
cursor.history()           -- open history browser
cursor.select_model()      -- open model picker
cursor.zen()               -- toggle zen mode
```

The lower-level `cursor.agent` module exposes `start({ prompt, on_chunk, on_event, on_done, on_error })` for scripting your own UI.

## Development

```sh
make lint    # stylua --check + luacheck
make test    # plenary busted suite (16 tests)
```

CI runs the same on push and pull request via `.github/workflows/ci.yml`.

For Cursor Cloud agent development notes, see [`AGENTS.md`](AGENTS.md).

To exercise the plugin headless with the fake CLI:

```sh
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "CursorAsk hello" \
  -c "lua vim.defer_fn(function() vim.cmd('qa!') end, 500)"
```

## License

Apache-2.0. See [`LICENSE`](LICENSE).
