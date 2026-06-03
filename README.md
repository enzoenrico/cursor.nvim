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
    "CursorMode",
    "CursorPlan",
    "CursorSkill",
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
- `@` opens a context picker for files, the current buffer, selected code, and project instructions
- `:CursorSkill` inserts a configured Cursor skill slash command such as `/sdk`
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
| Agent | `:CursorMode` | Pick agent, plan, or ask mode |
| Agent | `:CursorPlan` | Toggle plan mode |
| Agent | `:CursorSkill` | Insert a configured skill slash command |
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
| `<leader>cM` | Mode picker |
| `<leader>cp` | Toggle plan mode |
| `<leader>c/` | Insert a configured skill |
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
  cmd = "cursor-agent",     -- override path or args, e.g. "node bin/agent.js"
  transport = "cli",        -- "cli" or "sdk" (sdk uses sdk.cmd below)
  model = nil,              -- nil = Cursor default; e.g. "gpt-5.5-high"
  model_params = {},        -- e.g. { { id = "thinking", value = "high" } }
  mode = "agent",           -- "agent" | "plan" | "ask"
  stream_partial_output = true,
  force = false,            -- pass --force / local.force
  sandbox = nil,            -- "enabled" | "disabled"
  trust = false,
  approve_mcps = false,
  workspace = nil,
  headers = {},             -- repeated --header values for the CLI
  plugin_dirs = {},         -- repeated --plugin-dir values for skills/plugins
  extra_args = {},          -- any additional cursor-agent args
  models = nil,             -- optional static model list for :CursorModel
  skills = {},              -- e.g. { { name = "sdk", description = "Use Cursor SDK" } }
  sdk = {
    cmd = nil,              -- e.g. "node scripts/cursor-sdk-bridge.mjs"
    runtime = "local",
    api_key_env = "CURSOR_API_KEY",
    force = false,
    extra_args = {},
  },
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
cursor.select_mode()       -- open mode picker
cursor.toggle_plan()       -- toggle plan mode
cursor.insert_skill()      -- insert a configured /skill
cursor.zen()               -- toggle zen mode
```

The lower-level `cursor.agent` module exposes `start({ prompt, on_chunk, on_event, on_done, on_error })` for scripting your own UI.

## Cursor SDK transport

The default transport remains the Cursor Agent CLI. To drive the same UI through the Cursor TypeScript SDK, install `@cursor/sdk` in an environment that can run Node, set `CURSOR_API_KEY`, and point `sdk.cmd` at the optional bridge:

```lua
require("cursor").setup({
  transport = "sdk",
  sdk = {
    cmd = "node /path/to/cursor.nvim/scripts/cursor-sdk-bridge.mjs",
  },
  model = "composer-2.5",
  model_params = { { id = "thinking", value = "high" } },
  mode = "plan",
})
```

Skills are discovered by Cursor from workspace skill directories and plugin directories. Configure `plugin_dirs` for CLI runs, and configure `skills` when you want `:CursorSkill` to insert explicit slash-command invocations.

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
