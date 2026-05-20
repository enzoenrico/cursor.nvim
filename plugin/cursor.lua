-- cursor.nvim entry point. Registers user commands; everything heavy is
-- loaded lazily on first call via require("cursor").

if vim.g.loaded_cursor_nvim == 1 then
  return
end
vim.g.loaded_cursor_nvim = 1

local function lazy(modname, fn)
  return function(opts)
    local ok, mod = pcall(require, modname)
    if not ok then
      vim.notify(
        "cursor.nvim: failed to load " .. modname .. ": " .. tostring(mod),
        vim.log.levels.ERROR
      )
      return
    end
    return fn(mod, opts)
  end
end

vim.api.nvim_create_user_command(
  "CursorChat",
  lazy("cursor", function(mod)
    mod.chat()
  end),
  {
    desc = "Open a cursor.nvim chat panel",
  }
)

vim.api.nvim_create_user_command(
  "CursorAsk",
  lazy("cursor", function(mod, opts)
    local prompt = (opts.args or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if prompt == "" then
      vim.notify("CursorAsk requires a prompt", vim.log.levels.WARN)
      return
    end
    mod.ask(prompt)
  end),
  {
    desc = "Send a one-shot prompt to a cursor agent",
    nargs = "+",
  }
)

vim.api.nvim_create_user_command(
  "CursorStop",
  lazy("cursor", function(mod)
    mod.stop()
  end),
  {
    desc = "Stop the running cursor agent run",
  }
)

vim.api.nvim_create_user_command(
  "CursorStatus",
  lazy("cursor", function(mod)
    local s = mod.status()
    vim.api.nvim_echo({
      { "cursor.nvim: ", "Title" },
      { "running=" .. tostring(s.running), "Normal" },
      { "  agent_id=" .. tostring(s.agent_id), "Normal" },
      { "  model=" .. tostring(s.model), "Normal" },
    }, false, {})
  end),
  {
    desc = "Print cursor.nvim status to :messages",
  }
)

vim.api.nvim_create_user_command(
  "CursorVersion",
  lazy("cursor", function(mod)
    vim.api.nvim_echo({
      { "cursor.nvim v" .. tostring(mod.version()), "Normal" },
    }, true, {})
  end),
  {
    desc = "Print cursor.nvim version to :messages",
  }
)
