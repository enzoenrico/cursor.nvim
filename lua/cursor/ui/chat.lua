local config = require("cursor.config")
local agent = require("cursor.agent")
local ui_util = require("cursor.ui.util")

local M = {}

local session = nil

local function open_layout()
  local cfg = config.get()
  local layout = (cfg.ui or {}).layout or "vsplit"
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
    return { kind = "float", host_buf = buf }
  else
    vim.cmd("vsplit")
  end
  return { kind = layout }
end

local function setup_session()
  local cfg = config.get()
  local prompt_height = (cfg.ui or {}).prompt_height or 6
  local layout = open_layout()

  local transcript = ui_util.scratch_buf({
    filetype = (cfg.ui or {}).transcript_filetype or "markdown",
    modifiable = false,
  })
  if layout.kind == "float" then
    vim.api.nvim_win_set_buf(0, transcript)
  else
    vim.api.nvim_win_set_buf(0, transcript)
  end
  local transcript_win = vim.api.nvim_get_current_win()
  vim.wo[transcript_win].wrap = true
  vim.wo[transcript_win].number = false
  vim.wo[transcript_win].relativenumber = false

  vim.cmd(string.format("belowright %dsplit", prompt_height))
  local prompt = ui_util.scratch_buf({ filetype = "markdown" })
  local prompt_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(prompt_win, prompt)
  vim.bo[prompt].buftype = "nofile"
  vim.bo[prompt].modifiable = true
  vim.api.nvim_buf_set_lines(prompt, 0, -1, false, {
    "<!-- type your prompt; submit with <CR> in normal mode or <C-CR> in insert -->",
    "",
  })

  return {
    transcript = transcript,
    transcript_win = transcript_win,
    prompt = prompt,
    prompt_win = prompt_win,
  }
end

local function teardown(s)
  if not s then
    return
  end
  if agent.is_running() then
    agent.stop()
  end
  for _, b in ipairs({ s.transcript, s.prompt }) do
    if b and vim.api.nvim_buf_is_valid(b) then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
end

local function submit(s)
  local lines = vim.api.nvim_buf_get_lines(s.prompt, 0, -1, false)
  local prompt_text = {}
  for _, line in ipairs(lines) do
    if not line:match("^<!%-%-.*%-%->%s*$") then
      table.insert(prompt_text, line)
    end
  end
  local joined = vim.trim(table.concat(prompt_text, "\n"))
  if joined == "" then
    return
  end
  ui_util.append_text(s.transcript, "## You\n" .. joined .. "\n\n## Cursor\n")
  ui_util.scroll_to_end(s.transcript_win, s.transcript)
  vim.api.nvim_buf_set_lines(s.prompt, 0, -1, false, { "" })

  agent.start({
    prompt = joined,
    on_chunk = function(text)
      ui_util.append_text(s.transcript, text)
      ui_util.scroll_to_end(s.transcript_win, s.transcript)
    end,
    on_done = function(code)
      ui_util.append_text(
        s.transcript,
        string.format("\n\n---\n_(run finished, exit=%s)_\n\n", tostring(code))
      )
      ui_util.scroll_to_end(s.transcript_win, s.transcript)
    end,
    on_error = function(line)
      ui_util.append_text(s.transcript, "\n[stderr] " .. line .. "\n")
    end,
  })
end

local function bind_keymaps(s)
  local opts = { buffer = s.prompt, silent = true }
  vim.keymap.set("n", "<CR>", function()
    submit(s)
  end, vim.tbl_extend("force", opts, { desc = "cursor.nvim: submit prompt" }))
  vim.keymap.set("i", "<C-CR>", function()
    submit(s)
  end, vim.tbl_extend("force", opts, { desc = "cursor.nvim: submit prompt" }))
  vim.keymap.set("i", "<C-Enter>", function()
    submit(s)
  end, vim.tbl_extend("force", opts, { desc = "cursor.nvim: submit prompt" }))

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = s.transcript,
    once = true,
    callback = function()
      teardown(s)
      session = nil
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = s.prompt,
    once = true,
    callback = function()
      teardown(s)
      session = nil
    end,
  })
end

function M.open()
  if session and vim.api.nvim_buf_is_valid(session.transcript) then
    if vim.api.nvim_win_is_valid(session.transcript_win) then
      vim.api.nvim_set_current_win(session.transcript_win)
      return session
    end
  end
  session = setup_session()
  bind_keymaps(session)
  return session
end

function M.close()
  teardown(session)
  session = nil
end

function M.__session()
  return session
end

return M
