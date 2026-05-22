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
  { desc = "Open a cursor.nvim chat sidebar" }
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
  { desc = "Send a one-shot prompt to a cursor agent", nargs = "+" }
)

vim.api.nvim_create_user_command(
  "CursorStop",
  lazy("cursor", function(mod)
    mod.stop()
  end),
  { desc = "Stop the running cursor agent run" }
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
  { desc = "Print cursor.nvim status" }
)

vim.api.nvim_create_user_command(
  "CursorVersion",
  lazy("cursor", function(mod)
    vim.api.nvim_echo({
      { "cursor.nvim v" .. tostring(mod.version()), "Normal" },
    }, true, {})
  end),
  { desc = "Print cursor.nvim version" }
)

vim.api.nvim_create_user_command(
  "CursorToggle",
  lazy("cursor", function(mod)
    mod.toggle()
  end),
  { desc = "Toggle cursor.nvim sidebar" }
)

vim.api.nvim_create_user_command(
  "CursorFocus",
  lazy("cursor", function(mod)
    mod.focus()
  end),
  { desc = "Toggle focus between sidebar and code" }
)

vim.api.nvim_create_user_command(
  "CursorNew",
  lazy("cursor", function(mod)
    mod.new_chat()
  end),
  { desc = "Start a new cursor.nvim conversation" }
)

vim.api.nvim_create_user_command(
  "CursorEdit",
  lazy("cursor", function(mod)
    mod.edit()
  end),
  { desc = "Edit visual selection with cursor agent", range = true }
)

vim.api.nvim_create_user_command(
  "CursorHistory",
  lazy("cursor", function(mod)
    mod.history()
  end),
  { desc = "Browse cursor.nvim conversation history" }
)

vim.api.nvim_create_user_command(
  "CursorModel",
  lazy("cursor", function(mod)
    mod.select_model()
  end),
  { desc = "Select cursor agent model" }
)

vim.api.nvim_create_user_command(
  "CursorZen",
  lazy("cursor", function(mod)
    mod.zen()
  end),
  { desc = "Toggle cursor.nvim zen mode" }
)

vim.api.nvim_create_user_command(
  "CursorApply",
  lazy("cursor.diff", function(mod)
    local buf = vim.api.nvim_get_current_buf()
    mod.resolve_at_cursor(buf, "theirs")
  end),
  { desc = "Apply cursor suggestion at cursor" }
)

vim.api.nvim_create_user_command(
  "CursorApplyAll",
  lazy("cursor.diff", function(mod)
    local buf = vim.api.nvim_get_current_buf()
    mod.resolve_all(buf, "theirs")
  end),
  { desc = "Apply all cursor suggestions" }
)
