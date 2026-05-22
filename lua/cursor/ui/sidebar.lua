local config = require("cursor.config")
local agent = require("cursor.agent")
local spinner = require("cursor.spinner")
local history = require("cursor.history")
local selection = require("cursor.selection")
local ui_util = require("cursor.ui.util")

local M = {}

local sidebars = {}

local function define_highlights()
  local hi = vim.api.nvim_set_hl
  hi(0, "CursorSidebarHeader", { fg = "#61afef", bold = true, default = true })
  hi(0, "CursorSidebarBorder", { fg = "#3e4452", default = true })
  hi(0, "CursorPromptPrefix", { fg = "#61afef", bold = true, default = true })
  hi(0, "CursorRoleSeparator", { fg = "#565c64", default = true })
  hi(0, "CursorRoleUser", { fg = "#e5c07b", bold = true, default = true })
  hi(0, "CursorRoleAssistant", { fg = "#98c379", bold = true, default = true })
  hi(0, "CursorThinking", { fg = "#c678dd", italic = true, default = true })
  hi(0, "CursorWelcome", { fg = "#5c6370", italic = true, default = true })
  hi(0, "CursorWinbar", { fg = "#abb2bf", bg = "#2c323c", bold = true, default = true })
  hi(0, "CursorWinbarSpinner", { fg = "#c678dd", bg = "#2c323c", bold = true, default = true })
end

define_highlights()

pcall(function()
  vim.treesitter.language.register("markdown", "CursorChat")
end)

local function tab_id()
  return vim.api.nvim_get_current_tabpage()
end

local function calc_width()
  local cfg = config.get()
  local pct = (cfg.ui and cfg.ui.width) or 30
  return math.ceil(vim.o.columns * (pct / 100))
end

local function is_horizontal(layout)
  return layout == "top" or layout == "bottom"
end

local function split_cmd(layout, size)
  if layout == "left" then
    return string.format("topleft %dvsplit", size)
  elseif layout == "top" then
    return string.format("topleft %dsplit", size)
  elseif layout == "bottom" then
    return string.format("botright %dsplit", size)
  else
    return string.format("botright %dvsplit", size)
  end
end

local function set_winbar(win, text)
  if vim.api.nvim_win_is_valid(win) then
    pcall(function()
      vim.wo[win].winbar = text
    end)
  end
end

local function update_winbar(s)
  if not s or not s.transcript_win or not vim.api.nvim_win_is_valid(s.transcript_win) then
    return
  end
  local cfg = config.get()
  if not (cfg.ui and cfg.ui.sidebar_header and cfg.ui.sidebar_header.enabled) then
    set_winbar(s.transcript_win, "")
    return
  end
  local model = cfg.model or "default"
  local status_text = ""
  if s.spinner_frame then
    status_text = string.format(" %%#CursorWinbarSpinner#%s%%#CursorWinbar#", s.spinner_frame)
  end
  local bar = string.format("%%#CursorWinbar# cursor.nvim │ %s%s ", model, status_text)
  set_winbar(s.transcript_win, bar)
end

local function render_welcome(buf, win)
  local cfg = config.get()
  if not (cfg.ui and cfg.ui.welcome) then
    return
  end
  local width = 40
  if win and vim.api.nvim_win_is_valid(win) then
    width = vim.api.nvim_win_get_width(win)
  end
  local logo = {
    "",
    "",
    ui_util.center_text(
      "┌─────────────────────┐",
      width
    ),
    ui_util.center_text("│   cursor.nvim v0.1  │", width),
    ui_util.center_text(
      "└─────────────────────┘",
      width
    ),
    "",
    ui_util.center_text("Ask anything or paste code.", width),
    ui_util.center_text("Type in the prompt below.", width),
    "",
    ui_util.center_text("/clear  - clear chat", width),
    ui_util.center_text("/new    - new conversation", width),
    ui_util.center_text("/compact - compact history", width),
    "",
  }
  local was_modifiable = vim.bo[buf].modifiable
  if not was_modifiable then
    vim.bo[buf].modifiable = true
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, logo)
  if not was_modifiable then
    vim.bo[buf].modifiable = false
  end
  local ns = vim.api.nvim_create_namespace("cursor_welcome")
  for i = 0, #logo - 1 do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, i, 0, {
      end_row = i + 1,
      hl_group = "CursorWelcome",
    })
  end
end

local function create_transcript(cfg)
  local ft = (cfg.ui and cfg.ui.transcript_filetype) or "CursorChat"
  local buf = ui_util.scratch_buf({ filetype = ft, modifiable = false })
  vim.bo[buf].bufhidden = "hide"
  return buf
end

local function create_input(cfg)
  local buf = ui_util.scratch_buf({ filetype = "markdown" })
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].modifiable = true
  local prefix = (cfg.ui and cfg.ui.prompt_prefix) or "> "
  vim.fn.sign_define("CursorPromptSign", { text = prefix, texthl = "CursorPromptPrefix" })
  vim.fn.sign_place(0, "CursorPromptSigns", "CursorPromptSign", buf, { lnum = 1 })
  local placeholder = "Type a message... (<C-s> to send, /clear, /new)"
  ui_util.setup_placeholder_autocmds(buf, placeholder)
  return buf
end

local function create_selected_code(cfg)
  local buf = ui_util.scratch_buf({ filetype = "markdown", modifiable = false })
  vim.bo[buf].bufhidden = "hide"
  return buf
end

local function update_selected_code(s, sel_data)
  if not s.selected_code_buf or not vim.api.nvim_buf_is_valid(s.selected_code_buf) then
    return
  end
  local was_modifiable = vim.bo[s.selected_code_buf].modifiable
  vim.bo[s.selected_code_buf].modifiable = true
  if not sel_data then
    vim.api.nvim_buf_set_lines(s.selected_code_buf, 0, -1, false, {})
  else
    local header = "Selected code"
    if sel_data.filepath and sel_data.filepath ~= "" then
      header = header .. " (" .. vim.fn.fnamemodify(sel_data.filepath, ":.") .. ")"
    end
    local lines = { "**" .. header .. "**", "" }
    local code_lines = vim.split(sel_data.content, "\n", { plain = true })
    table.insert(lines, "```" .. (sel_data.filetype or ""))
    vim.list_extend(lines, code_lines)
    table.insert(lines, "```")
    vim.api.nvim_buf_set_lines(s.selected_code_buf, 0, -1, false, lines)
  end
  vim.bo[s.selected_code_buf].modifiable = was_modifiable
end

local function show_selected_code_win(s)
  if s.selected_code_win and vim.api.nvim_win_is_valid(s.selected_code_win) then
    return
  end
  if not s.transcript_win or not vim.api.nvim_win_is_valid(s.transcript_win) then
    return
  end
  local save_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(s.transcript_win)
  vim.cmd("belowright 6split")
  s.selected_code_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(s.selected_code_win, s.selected_code_buf)
  vim.wo[s.selected_code_win].wrap = true
  vim.wo[s.selected_code_win].number = false
  vim.wo[s.selected_code_win].relativenumber = false
  vim.wo[s.selected_code_win].signcolumn = "no"
  vim.wo[s.selected_code_win].winfixheight = true
  vim.api.nvim_set_current_win(save_win)
end

local function hide_selected_code_win(s)
  if s.selected_code_win and vim.api.nvim_win_is_valid(s.selected_code_win) then
    pcall(vim.api.nvim_win_close, s.selected_code_win, true)
  end
  s.selected_code_win = nil
end

local function open_windows(s, cfg)
  local layout = (cfg.ui and cfg.ui.layout) or "right"
  local size = calc_width()
  if is_horizontal(layout) then
    size = math.ceil(vim.o.lines * 0.35)
  end
  local prev_win = vim.api.nvim_get_current_win()
  s.code_win = prev_win
  vim.cmd(split_cmd(layout, size))
  s.transcript_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(s.transcript_win, s.transcript_buf)
  vim.wo[s.transcript_win].wrap = true
  vim.wo[s.transcript_win].number = false
  vim.wo[s.transcript_win].relativenumber = false
  vim.wo[s.transcript_win].signcolumn = "no"
  vim.wo[s.transcript_win].cursorline = false
  vim.wo[s.transcript_win].foldmethod = "manual"
  vim.wo[s.transcript_win].foldlevel = 99

  local prompt_height = (cfg.ui and cfg.ui.prompt_height) or 8
  vim.cmd(string.format("belowright %dsplit", prompt_height))
  s.input_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(s.input_win, s.input_buf)
  vim.wo[s.input_win].wrap = true
  vim.wo[s.input_win].number = false
  vim.wo[s.input_win].relativenumber = false
  vim.wo[s.input_win].winfixheight = true
  vim.wo[s.input_win].signcolumn = "yes"

  update_winbar(s)
end

local function parse_slash_command(text)
  local cmd = text:match("^/(%S+)")
  if cmd then
    return cmd, text:sub(#cmd + 2):gsub("^%s+", ""):gsub("%s+$", "")
  end
  return nil, text
end

local function handle_submit(s)
  local lines = vim.api.nvim_buf_get_lines(s.input_buf, 0, -1, false)
  local joined = vim.trim(table.concat(lines, "\n"))
  if joined == "" then
    return
  end

  local cmd, _ = parse_slash_command(joined)
  if cmd == "clear" then
    vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { "" })
    local cfg = config.get()
    local was = vim.bo[s.transcript_buf].modifiable
    vim.bo[s.transcript_buf].modifiable = true
    vim.api.nvim_buf_set_lines(s.transcript_buf, 0, -1, false, {})
    vim.bo[s.transcript_buf].modifiable = was
    s.conversation = { messages = {}, id = s.conversation.id }
    if cfg.ui and cfg.ui.welcome then
      render_welcome(s.transcript_buf, s.transcript_win)
    end
    return
  end

  if cmd == "new" then
    vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { "" })
    if s.conversation and s.conversation.id and #(s.conversation.messages or {}) > 0 then
      history.save(s.conversation.id, s.conversation)
    end
    s.conversation = { messages = {}, id = history.generate_id() }
    local was = vim.bo[s.transcript_buf].modifiable
    vim.bo[s.transcript_buf].modifiable = true
    vim.api.nvim_buf_set_lines(s.transcript_buf, 0, -1, false, {})
    vim.bo[s.transcript_buf].modifiable = was
    local cfg = config.get()
    if cfg.ui and cfg.ui.welcome then
      render_welcome(s.transcript_buf, s.transcript_win)
    end
    return
  end

  if cmd == "compact" then
    vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { "" })
    s.conversation = history.compact(s.conversation)
    vim.notify("cursor.nvim: conversation compacted", vim.log.levels.INFO)
    return
  end

  local sel_context = selection.format_context()
  local instructions = ui_util.get_project_instructions()
  local full_prompt = ""
  if instructions then
    full_prompt = full_prompt .. "[Project Instructions]\n" .. instructions .. "\n\n"
  end
  if sel_context then
    full_prompt = full_prompt .. "[Selected Code]\n" .. sel_context .. "\n\n"
  end

  if s.context_files and #s.context_files > 0 then
    for _, fp in ipairs(s.context_files) do
      local ok, file_lines = pcall(vim.fn.readfile, fp)
      if ok and file_lines then
        local ft = vim.filetype.match({ filename = fp }) or ""
        full_prompt = full_prompt
          .. string.format("[File: %s]\n```%s\n%s\n```\n\n", fp, ft, table.concat(file_lines, "\n"))
      end
    end
  end

  full_prompt = full_prompt .. joined

  local was = vim.bo[s.transcript_buf].modifiable
  vim.bo[s.transcript_buf].modifiable = true
  local buf_lines = vim.api.nvim_buf_get_lines(s.transcript_buf, 0, -1, false)
  local is_welcome = false
  for _, l in ipairs(buf_lines) do
    if l:match("cursor%.nvim") and l:match("v0%.1") then
      is_welcome = true
      break
    end
  end
  if is_welcome then
    vim.api.nvim_buf_set_lines(s.transcript_buf, 0, -1, false, {})
  end
  vim.bo[s.transcript_buf].modifiable = was

  ui_util.append_text(
    s.transcript_buf,
    "\n━━━ **You** ━━━\n" .. joined .. "\n\n━━━ **Cursor** ━━━\n"
  )
  ui_util.scroll_to_end(s.transcript_win, s.transcript_buf)
  vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { "" })

  table.insert(s.conversation.messages, {
    role = "user",
    content = joined,
    timestamp = os.time(),
  })

  s.spinner_frame = nil
  spinner.start("generating", function(frame, _)
    s.spinner_frame = frame
    update_winbar(s)
  end)

  agent.start({
    prompt = full_prompt,
    on_chunk = function(text)
      ui_util.append_text(s.transcript_buf, text)
      ui_util.scroll_to_end(s.transcript_win, s.transcript_buf)
    end,
    on_done = function(code)
      spinner.finish(code == 0, function(frame, _)
        s.spinner_frame = frame
        update_winbar(s)
        vim.defer_fn(function()
          s.spinner_frame = nil
          update_winbar(s)
        end, 3000)
      end)
      ui_util.append_text(s.transcript_buf, "\n")
      ui_util.scroll_to_end(s.transcript_win, s.transcript_buf)
      local response_lines = vim.api.nvim_buf_get_lines(s.transcript_buf, 0, -1, false)
      local response_text = table.concat(response_lines, "\n")
      table.insert(s.conversation.messages, {
        role = "assistant",
        content = response_text,
        timestamp = os.time(),
      })
      if s.conversation.id then
        pcall(history.save, s.conversation.id, s.conversation)
      end
    end,
    on_error = function(line)
      ui_util.append_text(s.transcript_buf, "\n[stderr] " .. line .. "\n")
    end,
  })
end

local function bind_keymaps(s)
  local cfg = config.get()
  local mappings = cfg.mappings or {}
  local submit_keys = mappings.submit or {}
  local cancel_keys = mappings.cancel or {}
  local sidebar_keys = mappings.sidebar or {}

  local input_opts = { buffer = s.input_buf, silent = true }
  vim.keymap.set("n", submit_keys.normal or "<CR>", function()
    handle_submit(s)
  end, vim.tbl_extend("force", input_opts, { desc = "cursor.nvim: submit prompt" }))

  vim.keymap.set("i", submit_keys.insert or "<C-s>", function()
    vim.cmd("stopinsert")
    handle_submit(s)
  end, vim.tbl_extend("force", input_opts, { desc = "cursor.nvim: submit prompt" }))

  local cancel_normal = cancel_keys.normal or { "<C-c>", "q" }
  if type(cancel_normal) == "string" then
    cancel_normal = { cancel_normal }
  end
  for _, key in ipairs(cancel_normal) do
    vim.keymap.set("n", key, function()
      M.close()
    end, vim.tbl_extend("force", input_opts, { desc = "cursor.nvim: close sidebar" }))
  end

  local cancel_insert = cancel_keys.insert or { "<C-c>" }
  if type(cancel_insert) == "string" then
    cancel_insert = { cancel_insert }
  end
  for _, key in ipairs(cancel_insert) do
    vim.keymap.set("i", key, function()
      vim.cmd("stopinsert")
    end, vim.tbl_extend("force", input_opts, { desc = "cursor.nvim: exit insert mode" }))
  end

  vim.keymap.set("n", "@", function()
    M.add_file_context(s)
  end, vim.tbl_extend("force", input_opts, { desc = "cursor.nvim: add file context" }))

  vim.keymap.set("n", "<Tab>", function()
    if vim.api.nvim_get_current_win() == s.input_win then
      if s.transcript_win and vim.api.nvim_win_is_valid(s.transcript_win) then
        vim.api.nvim_set_current_win(s.transcript_win)
      end
    else
      if s.input_win and vim.api.nvim_win_is_valid(s.input_win) then
        vim.api.nvim_set_current_win(s.input_win)
      end
    end
  end, vim.tbl_extend("force", input_opts, { desc = "cursor.nvim: switch focus" }))

  local transcript_opts = { buffer = s.transcript_buf, silent = true }
  vim.keymap.set("n", "<Tab>", function()
    if s.input_win and vim.api.nvim_win_is_valid(s.input_win) then
      vim.api.nvim_set_current_win(s.input_win)
    end
  end, vim.tbl_extend("force", transcript_opts, { desc = "cursor.nvim: focus input" }))

  vim.keymap.set("n", sidebar_keys.next_message or "]]", function()
    M.goto_next_message(s)
  end, vim.tbl_extend("force", transcript_opts, { desc = "cursor.nvim: next message" }))

  vim.keymap.set("n", sidebar_keys.prev_message or "[[", function()
    M.goto_prev_message(s)
  end, vim.tbl_extend("force", transcript_opts, { desc = "cursor.nvim: prev message" }))

  vim.keymap.set("n", sidebar_keys.apply or "a", function()
    vim.notify("cursor.nvim: apply not yet available for this response", vim.log.levels.INFO)
  end, vim.tbl_extend("force", transcript_opts, { desc = "cursor.nvim: apply suggestion" }))

  vim.keymap.set("n", sidebar_keys.apply_all or "A", function()
    vim.notify("cursor.nvim: apply all not yet available for this response", vim.log.levels.INFO)
  end, vim.tbl_extend("force", transcript_opts, { desc = "cursor.nvim: apply all suggestions" }))
end

local function setup_autocmds(s)
  local group = vim.api.nvim_create_augroup("CursorSidebar_" .. s.conversation.id, { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      M.resize(s)
    end,
  })
  for _, buf in ipairs({ s.transcript_buf, s.input_buf }) do
    vim.api.nvim_create_autocmd("BufWipeout", {
      group = group,
      buffer = buf,
      once = true,
      callback = function()
        M.close()
      end,
    })
  end
end

function M.get_sidebar(tid)
  tid = tid or tab_id()
  return sidebars[tid]
end

function M.open(opts)
  opts = opts or {}
  local tid = tab_id()
  local s = sidebars[tid]

  if s and s.transcript_win and vim.api.nvim_win_is_valid(s.transcript_win) then
    vim.api.nvim_set_current_win(s.input_win or s.transcript_win)
    if opts.selection then
      update_selected_code(s, opts.selection)
      show_selected_code_win(s)
    end
    return s
  end

  local cfg = config.get()
  if not s then
    s = {
      transcript_buf = create_transcript(cfg),
      input_buf = create_input(cfg),
      selected_code_buf = create_selected_code(cfg),
      conversation = { messages = {}, id = history.generate_id() },
      context_files = {},
      spinner_frame = nil,
      zen = false,
    }
    sidebars[tid] = s
  end

  open_windows(s, cfg)
  bind_keymaps(s)
  setup_autocmds(s)

  if cfg.ui and cfg.ui.welcome and #s.conversation.messages == 0 then
    render_welcome(s.transcript_buf, s.transcript_win)
  end

  if opts.selection then
    update_selected_code(s, opts.selection)
    show_selected_code_win(s)
  end

  if cfg.ui and cfg.ui.show_hints and s.input_win and vim.api.nvim_win_is_valid(s.input_win) then
    local hint = "Submit: <CR> (n) / <C-s> (i) │ @: add file │ <Tab>: switch │ q: close"
    set_winbar(s.input_win, "%#Comment# " .. hint .. " ")
  end

  vim.api.nvim_set_current_win(s.input_win)
  return s
end

function M.close()
  local tid = tab_id()
  local s = sidebars[tid]
  if not s then
    return
  end
  if agent.is_running() then
    agent.stop()
  end
  spinner.stop()
  if s.conversation and s.conversation.id and #(s.conversation.messages or {}) > 0 then
    pcall(history.save, s.conversation.id, s.conversation)
  end
  for _, win in ipairs({ s.input_win, s.selected_code_win, s.transcript_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  s.transcript_win = nil
  s.input_win = nil
  s.selected_code_win = nil
end

function M.toggle(opts)
  local tid = tab_id()
  local s = sidebars[tid]
  if s and s.transcript_win and vim.api.nvim_win_is_valid(s.transcript_win) then
    M.close()
  else
    M.open(opts)
  end
end

function M.focus()
  local tid = tab_id()
  local s = sidebars[tid]
  if not s or not s.transcript_win or not vim.api.nvim_win_is_valid(s.transcript_win) then
    M.open()
    return
  end
  local cur = vim.api.nvim_get_current_win()
  if cur == s.input_win or cur == s.transcript_win or cur == s.selected_code_win then
    if s.code_win and vim.api.nvim_win_is_valid(s.code_win) then
      vim.api.nvim_set_current_win(s.code_win)
    end
  else
    vim.api.nvim_set_current_win(s.input_win or s.transcript_win)
  end
end

function M.new_chat()
  local tid = tab_id()
  local s = sidebars[tid]
  if s then
    if s.conversation and s.conversation.id and #(s.conversation.messages or {}) > 0 then
      pcall(history.save, s.conversation.id, s.conversation)
    end
    s.conversation = { messages = {}, id = history.generate_id() }
    s.context_files = {}
    selection.clear()
    hide_selected_code_win(s)
    local was = vim.bo[s.transcript_buf].modifiable
    vim.bo[s.transcript_buf].modifiable = true
    vim.api.nvim_buf_set_lines(s.transcript_buf, 0, -1, false, {})
    vim.bo[s.transcript_buf].modifiable = was
    vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { "" })
    local cfg = config.get()
    if cfg.ui and cfg.ui.welcome then
      render_welcome(s.transcript_buf, s.transcript_win)
    end
  end
  M.open()
end

function M.resize(s)
  s = s or M.get_sidebar()
  if not s or not s.transcript_win or not vim.api.nvim_win_is_valid(s.transcript_win) then
    return
  end
  local cfg = config.get()
  local layout = (cfg.ui and cfg.ui.layout) or "right"
  if is_horizontal(layout) then
    return
  end
  local width = calc_width()
  pcall(vim.api.nvim_win_set_width, s.transcript_win, width)
  if s.input_win and vim.api.nvim_win_is_valid(s.input_win) then
    pcall(vim.api.nvim_win_set_width, s.input_win, width)
  end
end

function M.toggle_zen()
  local tid = tab_id()
  local s = sidebars[tid]
  if not s then
    M.open()
    s = sidebars[tid]
  end
  if not s or not s.transcript_win or not vim.api.nvim_win_is_valid(s.transcript_win) then
    return
  end
  if s.zen then
    if s.code_win and vim.api.nvim_win_is_valid(s.code_win) then
      vim.api.nvim_win_set_width(s.code_win, s._saved_code_width or 80)
    end
    s.zen = false
  else
    if s.code_win and vim.api.nvim_win_is_valid(s.code_win) then
      s._saved_code_width = vim.api.nvim_win_get_width(s.code_win)
      vim.api.nvim_win_set_width(s.code_win, 1)
    end
    s.zen = true
  end
end

function M.goto_next_message(s)
  s = s or M.get_sidebar()
  if not s or not s.transcript_buf or not vim.api.nvim_buf_is_valid(s.transcript_buf) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(s.transcript_buf, 0, -1, false)
  local cursor_line = vim.api.nvim_win_get_cursor(s.transcript_win)[1]
  for i = cursor_line + 1, #lines do
    if lines[i]:match("^━━━") then
      vim.api.nvim_win_set_cursor(s.transcript_win, { i, 0 })
      return
    end
  end
end

function M.goto_prev_message(s)
  s = s or M.get_sidebar()
  if not s or not s.transcript_buf or not vim.api.nvim_buf_is_valid(s.transcript_buf) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(s.transcript_buf, 0, -1, false)
  local cursor_line = vim.api.nvim_win_get_cursor(s.transcript_win)[1]
  for i = cursor_line - 1, 1, -1 do
    if lines[i]:match("^━━━") then
      vim.api.nvim_win_set_cursor(s.transcript_win, { i, 0 })
      return
    end
  end
end

function M.add_file_context(s)
  s = s or M.get_sidebar()
  if not s then
    return
  end
  local cwd = vim.fn.getcwd()
  local files = vim.fn.glob(cwd .. "/**/*", false, true)
  local choices = {}
  for _, f in ipairs(files) do
    if vim.fn.isdirectory(f) == 0 then
      table.insert(choices, vim.fn.fnamemodify(f, ":."))
    end
  end
  table.sort(choices)
  vim.ui.select(choices, { prompt = "Add file context:" }, function(choice)
    if choice then
      local abs = cwd .. "/" .. choice
      s.context_files = s.context_files or {}
      for _, existing in ipairs(s.context_files) do
        if existing == abs then
          vim.notify("cursor.nvim: file already in context", vim.log.levels.INFO)
          return
        end
      end
      table.insert(s.context_files, abs)
      vim.notify("cursor.nvim: added " .. choice .. " to context", vim.log.levels.INFO)
    end
  end)
end

function M.add_current_buffer()
  local s = M.get_sidebar()
  if not s then
    M.open()
    s = M.get_sidebar()
  end
  if not s then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    vim.notify("cursor.nvim: buffer has no file", vim.log.levels.WARN)
    return
  end
  s.context_files = s.context_files or {}
  for _, existing in ipairs(s.context_files) do
    if existing == name then
      vim.notify("cursor.nvim: file already in context", vim.log.levels.INFO)
      return
    end
  end
  table.insert(s.context_files, name)
  vim.notify(
    "cursor.nvim: added " .. vim.fn.fnamemodify(name, ":.") .. " to context",
    vim.log.levels.INFO
  )
end

function M.select_model()
  local models = {
    "default",
    "gpt-4",
    "gpt-4o",
    "gpt-3.5-turbo",
    "claude-sonnet-4-20250514",
    "claude-opus-4-20250514",
  }
  vim.ui.select(models, { prompt = "Select model:" }, function(choice)
    if choice then
      local cfg = config.get()
      if choice == "default" then
        cfg.model = nil
      else
        cfg.model = choice
      end
      local s = M.get_sidebar()
      if s then
        update_winbar(s)
      end
      vim.notify("cursor.nvim: model set to " .. choice, vim.log.levels.INFO)
    end
  end)
end

function M.show_history()
  local entries = history.list()
  if #entries == 0 then
    vim.notify("cursor.nvim: no conversation history", vim.log.levels.INFO)
    return
  end
  local choices = {}
  for _, entry in ipairs(entries) do
    local label = entry.id .. " (" .. os.date("%Y-%m-%d %H:%M", entry.mtime) .. ")"
    table.insert(choices, label)
  end
  vim.ui.select(choices, { prompt = "Conversation history:" }, function(_, idx)
    if idx then
      local entry = entries[idx]
      local conv = history.load(entry.id)
      if conv then
        local s = M.get_sidebar() or M.open()
        s.conversation = conv
        s.conversation.id = entry.id
        local was = vim.bo[s.transcript_buf].modifiable
        vim.bo[s.transcript_buf].modifiable = true
        vim.api.nvim_buf_set_lines(s.transcript_buf, 0, -1, false, {})
        for _, msg in ipairs(conv.messages or {}) do
          local role_label = msg.role == "user" and "You" or "Cursor"
          ui_util.append_text(
            s.transcript_buf,
            "\n━━━ **" .. role_label .. "** ━━━\n" .. (msg.content or "") .. "\n"
          )
        end
        vim.bo[s.transcript_buf].modifiable = was
        ui_util.scroll_to_end(s.transcript_win, s.transcript_buf)
      end
    end
  end)
end

return M
