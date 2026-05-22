local config = require("cursor.config")
local agent = require("cursor.agent")
local version = require("cursor.version")
local log = require("cursor.log")

local M = {}

local function setup_keymaps()
  local cfg = config.get()
  local maps = cfg.mappings or {}
  local ui_util = require("cursor.ui.util")
  local function smap(lhs, rhs, desc)
    if lhs then
      ui_util.safe_keymap_set("n", lhs, rhs, { silent = true, desc = "cursor.nvim: " .. desc })
    end
  end
  smap(maps.chat, "<cmd>CursorChat<cr>", "open chat")
  smap(maps.toggle, "<cmd>CursorToggle<cr>", "toggle sidebar")
  smap(maps.focus, "<cmd>CursorFocus<cr>", "toggle focus")
  smap(maps.stop, "<cmd>CursorStop<cr>", "stop run")
  smap(maps.status, "<cmd>CursorStatus<cr>", "status")
  smap(maps.new, "<cmd>CursorNew<cr>", "new conversation")
  smap(maps.history, "<cmd>CursorHistory<cr>", "history")
  smap(maps.model, "<cmd>CursorModel<cr>", "select model")
  smap(maps.zen, "<cmd>CursorZen<cr>", "zen mode")
  smap(maps.buffer_context, function()
    local sidebar = require("cursor.ui.sidebar")
    sidebar.add_current_buffer()
  end, "add buffer context")
  smap(maps.ask, function()
    local prompt = vim.fn.input("CursorAsk> ")
    if prompt ~= "" then
      vim.cmd("CursorAsk " .. vim.fn.fnameescape(prompt))
    end
  end, "ask")
  smap(maps.edit, function()
    M.edit()
  end, "edit selection")
end

function M.setup(opts)
  config.setup(opts)
  log.info(
    "init",
    "setup()",
    { keymaps = (config.get()).keymaps, model = (config.get()).model, cmd = (config.get()).cmd }
  )
  local cfg = config.get()
  if cfg.keymaps then
    setup_keymaps()
  end
  local sel = require("cursor.selection")
  sel.setup_autocmds()
  return M
end

function M.ask(prompt)
  log.info("init", "ask()", { prompt_len = prompt and #prompt or 0 })
  if type(prompt) ~= "string" or prompt == "" then
    vim.notify("cursor.nvim: ask() requires a prompt", vim.log.levels.WARN)
    return
  end
  local sidebar = require("cursor.ui.sidebar")
  local s = sidebar.open()
  if not s then
    return
  end
  vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, vim.split(prompt, "\n", { plain = true }))
  vim.cmd("doautocmd TextChanged")
  vim.api.nvim_set_current_win(s.input_win)
  vim.cmd("normal! G")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
end

function M.chat()
  local sidebar = require("cursor.ui.sidebar")
  sidebar.open()
end

function M.toggle(opts)
  local sidebar = require("cursor.ui.sidebar")
  sidebar.toggle(opts)
end

function M.focus()
  local sidebar = require("cursor.ui.sidebar")
  sidebar.focus()
end

function M.new_chat()
  local sidebar = require("cursor.ui.sidebar")
  sidebar.new_chat()
end

function M.edit()
  local sel = require("cursor.selection")
  local sel_data = sel.capture_from_range()
  if not sel_data then
    vim.notify("cursor.nvim: no visual selection", vim.log.levels.WARN)
    return
  end
  local sidebar = require("cursor.ui.sidebar")
  local buf = vim.api.nvim_get_current_buf()
  sel.highlight_selection(buf, sel_data.range)
  sidebar.open({ selection = sel_data })
end

function M.stop()
  log.info("init", "stop()", { running = agent.is_running() })
  if not agent.is_running() then
    vim.notify("cursor.nvim: no run to stop", vim.log.levels.INFO)
    return
  end
  agent.stop()
  local spinner = require("cursor.spinner")
  spinner.stop()
end

function M.status()
  return agent.status()
end

function M.version()
  return version
end

function M.history()
  local sidebar = require("cursor.ui.sidebar")
  sidebar.show_history()
end

function M.select_model()
  local sidebar = require("cursor.ui.sidebar")
  sidebar.select_model()
end

function M.zen()
  local sidebar = require("cursor.ui.sidebar")
  sidebar.toggle_zen()
end

return M
