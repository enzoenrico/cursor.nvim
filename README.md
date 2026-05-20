# cursor.nvim

A Neovim extension for the [Cursor SDK](https://www.npmjs.com/package/@cursor/sdk) — chat with Cursor agents without leaving Neovim.

> v0.1: this is a working baseline. See [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) for scope, public API, and the v0.2+ roadmap.

## Requirements

- Neovim 0.10+
- The [`cursor-agent`](https://docs.cursor.com) CLI on your `$PATH`

The plugin shells out to `cursor-agent --print --output-format=stream-json -p <prompt>` and parses the resulting JSON-line stream. No Node embedding or build step required.

## Installation

### lazy.nvim

```lua
{
  "enzoenrico/cursor.nvim",
  cmd = { "CursorChat", "CursorAsk", "CursorStop", "CursorStatus" },
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

## Usage

```vim
:CursorChat              " open a transcript + prompt window
:CursorAsk explain this  " one-shot prompt
:CursorStop              " cancel the running agent
:CursorStatus            " print { running, agent_id, model }
:checkhealth cursor      " verify cursor-agent / Node availability
```

When `setup({ keymaps = true })` is set:

| Keymap        | Action            |
| ------------- | ----------------- |
| `<leader>cc`  | `:CursorChat`     |
| `<leader>ca`  | prompt + `:CursorAsk` |
| `<leader>cs`  | `:CursorStop`     |
| `<leader>c?`  | `:CursorStatus`   |

## Configuration

```lua
require("cursor").setup({
  cmd     = "cursor-agent",   -- override path or args, e.g. "node bin/agent.js"
  model   = nil,              -- nil = SDK default; e.g. "gpt-5.5-high"
  keymaps = false,            -- true installs the table above
  ui      = {
    layout              = "vsplit", -- "vsplit" | "float" | "tab"
    transcript_filetype = "markdown",
    prompt_height       = 6,
  },
  notify  = true,             -- vim.notify on errors
})
```

## Lua API

```lua
local cursor = require("cursor")

cursor.ask("explain this function")
cursor.chat()
cursor.stop()
cursor.status()  --> { running = bool, agent_id = string|nil, model = string|nil }
```

The lower-level `cursor.agent` module exposes `start({prompt, on_chunk, on_event, on_done, on_error})` for scripting your own UI.

## Development

```sh
make lint    # stylua --check + luacheck
make test    # plenary busted suite
```

CI runs the same on push and pull request via `.github/workflows/ci.yml`.

## Roadmap

See [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) for v0.2+ ideas: ACP integration, inline completions, multiple chats, MCP server discovery, telescope/snacks integrations.

## License

Apache-2.0. See [`LICENSE`](LICENSE).
