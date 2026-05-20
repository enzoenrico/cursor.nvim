local config = require("cursor.config")
local agent = require("cursor.agent")

local M = {}

local function open_scratch_panel()
  local cfg = config.get()
  local layout = cfg.ui and cfg.ui.layout or "vsplit"
  if layout == "tab" then
    vim.cmd("tabnew")
  elseif layout == "float" then
    local width = math.floor(vim.o.columns * 0.6)
    local height = math.floor(vim.o.lines * 0.7)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2),
      style = "minimal",
      border = "rounded",
    })
    return buf
  else
    vim.cmd("vsplit")
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  return buf
end

local function setup_keymaps()
  local map = function(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { silent = true, desc = desc })
  end
  map("<leader>cc", "<cmd>CursorChat<cr>", "cursor.nvim: open chat")
  map("<leader>cs", "<cmd>CursorStop<cr>", "cursor.nvim: stop run")
  map("<leader>c?", "<cmd>CursorStatus<cr>", "cursor.nvim: status")
  map("<leader>ca", function()
    local prompt = vim.fn.input("CursorAsk> ")
    if prompt ~= "" then
      vim.cmd("CursorAsk " .. vim.fn.fnameescape(prompt))
    end
  end, "cursor.nvim: ask")
end

function M.setup(opts)
  config.setup(opts)
  if config.get().keymaps then
    setup_keymaps()
  end
  return M
end

function M.ask(prompt)
  if type(prompt) ~= "string" or prompt == "" then
    vim.notify("cursor.nvim: ask() requires a prompt", vim.log.levels.WARN)
    return
  end
  local buf = open_scratch_panel()
  vim.bo[buf].filetype = (config.get().ui or {}).transcript_filetype or "markdown"
  vim.bo[buf].buftype = "nofile"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# " .. prompt, "" })

  local function append(text)
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local lines = vim.split(text, "\n", { plain = true })
    local last = vim.api.nvim_buf_line_count(buf)
    local last_line = vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1] or ""
    lines[1] = last_line .. lines[1]
    vim.api.nvim_buf_set_lines(buf, last - 1, last, false, lines)
  end

  agent.start({
    prompt = prompt,
    on_chunk = function(text)
      append(text)
    end,
    on_done = function(code)
      append(string.format("\n\n_(run finished, exit=%s)_", tostring(code)))
    end,
    on_error = function(line)
      append("\n[stderr] " .. line)
    end,
  })
end

function M.chat()
  local ok, ui = pcall(require, "cursor.ui.chat")
  if not ok then
    vim.notify("cursor.nvim: chat UI unavailable: " .. tostring(ui), vim.log.levels.ERROR)
    return
  end
  ui.open()
end

function M.stop()
  if not agent.is_running() then
    vim.notify("cursor.nvim: no run to stop", vim.log.levels.INFO)
    return
  end
  agent.stop()
end

function M.status()
  return agent.status()
end

return M
