local config = require("cursor.config")
local agent = require("cursor.agent")
local spinner = require("cursor.spinner")
local history = require("cursor.history")
local selection = require("cursor.selection")
local ui_util = require("cursor.ui.util")
local render = require("cursor.ui.render")
local skills = require("cursor.skills")
local version = require("cursor.version")
local log = require("cursor.log")

local M = {}

local sidebars = {}

local function define_highlights()
  local cfg = config.get()
  local ui = cfg.ui or {}
  local hi = vim.api.nvim_set_hl
  if ui.use_colorscheme then
    hi(0, "CursorRoleUser", { link = "Identifier", default = true })
    hi(0, "CursorRoleAssistant", { link = "String", default = true })
    hi(0, "CursorRoleSeparator", { link = "Comment", default = true })
    hi(0, "CursorPromptPrefix", { link = "Function", default = true })
    hi(0, "CursorThinking", { link = "Special", default = true })
    hi(0, "CursorWelcome", { link = "Comment", default = true })
    hi(0, "CursorWinbar", { link = "StatusLine", default = true })
    hi(0, "CursorWinbarSpinner", { link = "Special", default = true })
    hi(0, "CursorWinbarModel", { link = "Function", default = true })
    hi(0, "CursorWinbarDone", { link = "String", default = true })
    hi(0, "CursorWinbarFailed", { link = "ErrorMsg", default = true })
    hi(0, "CursorError", { link = "ErrorMsg", default = true })
    hi(0, "CursorLoading", { link = "Special", default = true })
    hi(0, "CursorSidebarBorder", { link = "VertSplit", default = true })
    return
  end
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
  hi(0, "CursorWinbarModel", { fg = "#61afef", bg = "#2c323c", bold = true, default = true })
  hi(0, "CursorWinbarDone", { fg = "#98c379", bg = "#2c323c", bold = true, default = true })
  hi(0, "CursorWinbarFailed", { fg = "#e06c75", bg = "#2c323c", bold = true, default = true })
  hi(0, "CursorError", { fg = "#e06c75", bold = true, default = true })
  hi(0, "CursorLoading", { fg = "#c678dd", italic = true, default = true })
end

define_highlights()

function M.refresh_highlights()
  define_highlights()
end

pcall(function()
  vim.treesitter.language.register("markdown", "CursorChat")
end)

local loading_ns = vim.api.nvim_create_namespace("cursor_loading")

local fallback_models = {
  "default",
  "composer-2.5",
  "gpt-5.5-high",
  "gpt-5.4-high",
  "claude-opus-4-8-thinking-high",
  "claude-4.6-sonnet-high-thinking",
}

local function tab_id()
  return vim.api.nvim_get_current_tabpage()
end

local function calc_width()
  local cfg = config.get()
  local pct = (cfg.ui and cfg.ui.width) or 30
  return math.ceil(vim.o.columns * (pct / 100))
end

local function calc_height()
  return math.ceil(vim.o.lines * 0.35)
end

local function apply_win_chrome(win, cfg)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  local ui = cfg.ui or {}
  local border = ui.winborder
  if border and border ~= "none" then
    pcall(function()
      vim.wo[win].winborder = border
    end)
  end
  pcall(function()
    vim.wo[win].winhighlight = "WinSeparator:CursorSidebarBorder,FloatBorder:CursorSidebarBorder"
  end)
end

local function message_fold_opts(cfg, s)
  return {
    fold = cfg.ui and cfg.ui.fold_messages,
    win = s.transcript_win,
  }
end

local function reset_transcript_state(s)
  s.message_regions = {}
  s.current_response = ""
  s.assistant_region = nil
  render.clear_messages(s.transcript_buf)
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

local function get_display_model(s)
  local agent_status = agent.status()
  if agent_status.model and agent_status.model ~= "" then
    return agent_status.model
  end
  if s and s.last_model and s.last_model ~= "" then
    return s.last_model
  end
  local cfg = config.get()
  local mode = cfg.mode == "plan" and "plan" or nil
  local model = cfg.model or "default"
  if mode then
    return model .. " (" .. mode .. ")"
  end
  return model
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
  local model = get_display_model(s)
  local status_part = ""
  if s.state == "generating" and s.spinner_frame then
    status_part =
      string.format(" %%#CursorWinbarSpinner#%s generating...%%#CursorWinbar#", s.spinner_frame)
  elseif s.state == "error" then
    status_part = " %#CursorWinbarFailed#✗ error%#CursorWinbar#"
  elseif s.state == "done" then
    status_part = " %#CursorWinbarDone#✓ done%#CursorWinbar#"
  end
  local bar = string.format(
    "%%#CursorWinbar# cursor.nvim │ %%#CursorWinbarModel#%s%%#CursorWinbar#%s ",
    model,
    status_part
  )
  set_winbar(s.transcript_win, bar)
end

local function show_inline_loading(s, frame)
  if not s or not s.transcript_buf or not vim.api.nvim_buf_is_valid(s.transcript_buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(s.transcript_buf, loading_ns, 0, -1)
  local line_count = vim.api.nvim_buf_line_count(s.transcript_buf)
  pcall(vim.api.nvim_buf_set_extmark, s.transcript_buf, loading_ns, line_count - 1, 0, {
    virt_lines = { { { " " .. frame .. " Generating response...", "CursorLoading" } } },
  })
end

local function clear_inline_loading(s)
  if not s or not s.transcript_buf or not vim.api.nvim_buf_is_valid(s.transcript_buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(s.transcript_buf, loading_ns, 0, -1)
end

local function context_label(item)
  if item.type == "file" then
    return "@" .. vim.fn.fnamemodify(item.path, ":.")
  end
  if item.type == "buffer" then
    return "@buffer"
  end
  if item.type == "selection" then
    return "@selection"
  end
  if item.type == "instructions" then
    return "@instructions"
  end
  return "@context"
end

local function update_input_winbar(s)
  if not s or not s.input_win or not vim.api.nvim_win_is_valid(s.input_win) then
    return
  end
  local cfg = config.get()
  local parts = {}
  if cfg.ui and cfg.ui.show_hints then
    table.insert(parts, "<CR>/<C-s> send │ @ file │ /skills │ ,c ,s │ Tab │ q close")
  end
  local items = s.context_items or {}
  if #items > 0 then
    local names = {}
    for i, item in ipairs(items) do
      if i <= 2 then
        table.insert(names, context_label(item))
      end
    end
    local label = " " .. table.concat(names, ", ")
    if #items > 2 then
      label = label .. " +" .. (#items - 2)
    end
    table.insert(parts, label)
  end
  local active = s.active_skills or {}
  if #active > 0 then
    local names = {}
    for i, sk in ipairs(active) do
      if i <= 2 then
        table.insert(names, sk.name)
      end
    end
    local label = " / " .. table.concat(names, ", ")
    if #active > 2 then
      label = label .. " +" .. (#active - 2)
    end
    table.insert(parts, label)
  end
  if #parts == 0 then
    set_winbar(s.input_win, "")
    return
  end
  set_winbar(s.input_win, "%#Comment# " .. table.concat(parts, " │ ") .. " ")
end

local function context_key(item)
  return (item.type or "context") .. ":" .. tostring(item.path or item.name or "")
end

local function ensure_context_item(s, item)
  s.context_items = s.context_items or {}
  local key = context_key(item)
  for _, existing in ipairs(s.context_items) do
    if context_key(existing) == key then
      vim.notify("cursor.nvim: context already attached", vim.log.levels.INFO)
      return false
    end
  end
  table.insert(s.context_items, item)
  return true
end

local function insert_context_mention(s, item)
  if not s or not s.input_buf or not vim.api.nvim_buf_is_valid(s.input_buf) then
    return
  end
  local mention = context_label(item)
  local line = vim.api.nvim_buf_get_lines(s.input_buf, -2, -1, false)[1] or ""
  local prefix = line == "" and "" or " "
  vim.api.nvim_buf_set_lines(s.input_buf, -2, -1, false, { line .. prefix .. mention .. " " })
  vim.api.nvim_set_current_win(s.input_win)
  vim.cmd("normal! G$")
end

local function format_context_item(item)
  if item.type == "file" then
    local ok, file_lines = pcall(vim.fn.readfile, item.path)
    if ok and file_lines then
      local ft = vim.filetype.match({ filename = item.path }) or ""
      return string.format(
        "[File: %s]\n```%s\n%s\n```\n\n",
        item.path,
        ft,
        table.concat(file_lines, "\n")
      )
    end
  elseif item.type == "buffer" then
    local buf = item.buf
    if buf and vim.api.nvim_buf_is_valid(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local ft = vim.bo[buf].filetype or ""
      return string.format(
        "[Buffer: %s]\n```%s\n%s\n```\n\n",
        name ~= "" and name or tostring(buf),
        ft,
        table.concat(lines, "\n")
      )
    end
  elseif item.type == "selection" then
    local text = selection.format_context()
    if text then
      return "[Selected Code]\n" .. text .. "\n\n"
    end
  elseif item.type == "instructions" then
    local instructions = ui_util.get_project_instructions()
    if instructions then
      return "[Project Instructions]\n" .. instructions .. "\n\n"
    end
  end
  return nil
end

local function append_error(s, msg)
  if not s or not s.transcript_buf then
    return
  end
  ui_util.append_text(s.transcript_buf, "\n⚠ **Error:** " .. msg .. "\n")
  ui_util.scroll_to_end(s.transcript_win, s.transcript_buf)
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
  local model = cfg.model or "default"
  local logo = {
    "",
    "",
    ui_util.center_text(
      "┌─────────────────────┐",
      width
    ),
    ui_util.center_text("│   cursor.nvim v" .. version .. "  │", width),
    ui_util.center_text(
      "└─────────────────────┘",
      width
    ),
    "",
    ui_util.center_text("Model: " .. model, width),
    "",
    ui_util.center_text("Ask anything or paste code.", width),
    ui_util.center_text("<CR> or <C-s> to send │ @ attach file", width),
    ui_util.center_text("<Tab> switch panes │ q close sidebar", width),
    "",
    ui_util.center_text("/clear  - clear chat", width),
    ui_util.center_text("/new    - new conversation", width),
    ui_util.center_text("/compact - compact history", width),
    ui_util.center_text("/skills - list agent skills", width),
    ui_util.center_text("/<skill> - invoke a skill", width),
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
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
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
  local placeholder = "Type a message... (<C-s> send, /skills, /clear, /new)"
  ui_util.setup_placeholder_autocmds(buf, placeholder)
  return buf
end

local function create_selected_code()
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
  apply_win_chrome(s.selected_code_win, config.get())
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
  apply_win_chrome(s.transcript_win, cfg)

  local prompt_height = (cfg.ui and cfg.ui.prompt_height) or 8
  vim.cmd(string.format("belowright %dsplit", prompt_height))
  s.input_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(s.input_win, s.input_buf)
  vim.wo[s.input_win].wrap = true
  vim.wo[s.input_win].number = false
  vim.wo[s.input_win].relativenumber = false
  vim.wo[s.input_win].winfixheight = true
  vim.wo[s.input_win].signcolumn = "yes"
  apply_win_chrome(s.input_win, cfg)

  update_winbar(s)
  update_input_winbar(s)
end

local function get_code_buf(s)
  if s.code_win and vim.api.nvim_win_is_valid(s.code_win) then
    return vim.api.nvim_win_get_buf(s.code_win)
  end
  return nil
end

local function parse_slash_command(text)
  local cmd, args = text:match("^/(%S+)%s*(.*)$")
  if cmd then
    return cmd, vim.trim(args)
  end
  return nil, text
end

local function attach_skill(s, skill)
  s.active_skills = s.active_skills or {}
  for _, existing in ipairs(s.active_skills) do
    if existing.name == skill.name then
      return false
    end
  end
  table.insert(s.active_skills, skill)
  return true
end

local function resolve_skill(name, buf)
  local skill = skills.get(name, { reload = true })
  if not skill then
    return nil
  end
  if not skills.applies_to_buffer(skill, buf) then
    return nil, "not_in_scope"
  end
  return skill
end

function M.pick_skill(s)
  s = s or M.get_sidebar()
  if not s then
    return
  end
  local buf = get_code_buf(s) or s.transcript_buf
  local available = skills.filter_for_buffer(buf, { reload = true })
  if #available == 0 then
    vim.notify("cursor.nvim: no skills found for this project", vim.log.levels.INFO)
    return
  end
  local choices = {}
  for _, sk in ipairs(available) do
    local desc = sk.description ~= "" and (" — " .. sk.description) or ""
    table.insert(choices, sk.name .. desc)
  end
  vim.ui.select(choices, { prompt = "Attach skill:" }, function(choice)
    if not choice then
      return
    end
    local name = choice:match("^(%S+)")
    local skill = skills.get(name)
    if skill and attach_skill(s, skill) then
      update_input_winbar(s)
      vim.notify("cursor.nvim: attached skill /" .. skill.name, vim.log.levels.INFO)
    end
  end)
end

function M.manage_skills(s)
  s = s or M.get_sidebar()
  if not s then
    return
  end
  s.active_skills = s.active_skills or {}
  if #s.active_skills == 0 then
    vim.notify("cursor.nvim: no skills attached (use /skills or /<name>)", vim.log.levels.INFO)
    return
  end
  local choices = { "— Clear all —", "— Add skill —" }
  for _, sk in ipairs(s.active_skills) do
    table.insert(choices, sk.name)
  end
  vim.ui.select(choices, { prompt = "Active skills:" }, function(choice)
    if not choice then
      return
    end
    if choice == "— Clear all —" then
      s.active_skills = {}
    elseif choice == "— Add skill —" then
      M.pick_skill(s)
      return
    else
      for i, sk in ipairs(s.active_skills) do
        if sk.name == choice then
          table.remove(s.active_skills, i)
          break
        end
      end
    end
    update_input_winbar(s)
    vim.notify("cursor.nvim: skills updated", vim.log.levels.INFO)
  end)
end

local function clear_welcome(s)
  local buf_lines = vim.api.nvim_buf_get_lines(s.transcript_buf, 0, -1, false)
  if #buf_lines == 0 then
    return
  end
  if s.has_welcome then
    vim.api.nvim_buf_set_lines(s.transcript_buf, 0, -1, false, {})
    s.has_welcome = false
    local ns = vim.api.nvim_create_namespace("cursor_welcome")
    vim.api.nvim_buf_clear_namespace(s.transcript_buf, ns, 0, -1)
  end
end

local function set_state(s, new_state)
  log.debug("sidebar", "state change", { from = s.state, to = new_state })
  s.state = new_state
  update_winbar(s)
end

local function handle_submit(s)
  local lines = vim.api.nvim_buf_get_lines(s.input_buf, 0, -1, false)
  local joined = vim.trim(table.concat(lines, "\n"))
  log.info("sidebar", "submit", { length = #joined, empty = joined == "" })
  if joined == "" then
    return
  end

  local cmd, slash_args = parse_slash_command(joined)
  if cmd == "clear" then
    vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { "" })
    local cfg = config.get()
    local was = vim.bo[s.transcript_buf].modifiable
    vim.bo[s.transcript_buf].modifiable = true
    vim.api.nvim_buf_set_lines(s.transcript_buf, 0, -1, false, {})
    vim.bo[s.transcript_buf].modifiable = was
    reset_transcript_state(s)
    s.conversation = { messages = {}, id = s.conversation.id }
    s.context_items = {}
    s.active_skills = {}
    s.has_welcome = false
    set_state(s, nil)
    update_input_winbar(s)
    if cfg.ui and cfg.ui.welcome then
      render_welcome(s.transcript_buf, s.transcript_win)
      s.has_welcome = true
    end
    return
  end

  if cmd == "new" then
    vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { "" })
    if s.conversation and s.conversation.id and #(s.conversation.messages or {}) > 0 then
      history.save(s.conversation.id, s.conversation)
    end
    s.conversation = { messages = {}, id = history.generate_id() }
    s.context_items = {}
    s.active_skills = {}
    update_input_winbar(s)
    local was = vim.bo[s.transcript_buf].modifiable
    vim.bo[s.transcript_buf].modifiable = true
    vim.api.nvim_buf_set_lines(s.transcript_buf, 0, -1, false, {})
    vim.bo[s.transcript_buf].modifiable = was
    reset_transcript_state(s)
    s.has_welcome = false
    set_state(s, nil)
    local cfg = config.get()
    if cfg.ui and cfg.ui.welcome then
      render_welcome(s.transcript_buf, s.transcript_win)
      s.has_welcome = true
    end
    return
  end

  if cmd == "compact" then
    vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { "" })
    s.conversation = history.compact(s.conversation)
    vim.notify("cursor.nvim: conversation compacted", vim.log.levels.INFO)
    return
  end

  if cmd == "skills" then
    vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { "" })
    M.pick_skill(s)
    return
  end

  if cmd == "skill" then
    vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { "" })
    local skill_name = slash_args:match("^(%S+)")
    if not skill_name or skill_name == "" then
      M.pick_skill(s)
      return
    end
    local buf = get_code_buf(s) or s.transcript_buf
    local skill, err = resolve_skill(skill_name, buf)
    if not skill then
      local msg = err == "not_in_scope" and ("skill `/" .. skill_name .. "` is not in scope here")
        or ("unknown skill `/" .. skill_name .. "`")
      vim.notify("cursor.nvim: " .. msg, vim.log.levels.WARN)
      return
    end
    if attach_skill(s, skill) then
      update_input_winbar(s)
      vim.notify("cursor.nvim: attached skill /" .. skill.name, vim.log.levels.INFO)
    end
    local rest = vim.trim(slash_args:sub(#skill_name + 1))
    if rest == "" then
      return
    end
    joined = rest
  elseif cmd and not skills.is_builtin_slash(cmd) then
    local buf = get_code_buf(s) or s.transcript_buf
    local skill, err = resolve_skill(cmd, buf)
    if skill then
      attach_skill(s, skill)
      update_input_winbar(s)
      if slash_args == "" then
        vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { "" })
        vim.notify("cursor.nvim: attached skill /" .. skill.name, vim.log.levels.INFO)
        return
      end
      joined = slash_args
      vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { "" })
    elseif err == "not_in_scope" then
      vim.notify("cursor.nvim: skill `/" .. cmd .. "` is not in scope here", vim.log.levels.WARN)
      return
    end
  end

  local sel_context = selection.format_context()
  local instructions = ui_util.get_project_instructions()
  local full_prompt = ""
  if instructions then
    full_prompt = full_prompt .. "[Project Instructions]\n" .. instructions .. "\n\n"
  end
  if s.active_skills and #s.active_skills > 0 then
    full_prompt = full_prompt .. skills.format_many_for_prompt(s.active_skills) .. "\n\n"
  end
  if sel_context then
    full_prompt = full_prompt .. "[Selected Code]\n" .. sel_context .. "\n\n"
  end

  if s.context_items and #s.context_items > 0 then
    for _, item in ipairs(s.context_items) do
      if item.type ~= "instructions" or not instructions then
        local formatted = format_context_item(item)
        if formatted then
          full_prompt = full_prompt .. formatted
        end
      end
    end
  end

  full_prompt = full_prompt .. joined

  local cfg = config.get()
  local was = vim.bo[s.transcript_buf].modifiable
  vim.bo[s.transcript_buf].modifiable = true
  clear_welcome(s)

  local fold_opts = message_fold_opts(cfg, s)
  local user_region = render.append_message(s.transcript_buf, "user", joined, fold_opts)
  s.message_regions = s.message_regions or {}
  table.insert(s.message_regions, user_region)
  s.assistant_region = render.append_message(s.transcript_buf, "assistant", "", fold_opts)
  table.insert(s.message_regions, s.assistant_region)
  vim.bo[s.transcript_buf].modifiable = was
  ui_util.scroll_to_end(s.transcript_win, s.transcript_buf)
  vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { "" })

  table.insert(s.conversation.messages, {
    role = "user",
    content = joined,
    timestamp = os.time(),
  })

  s.spinner_frame = nil
  s.got_first_chunk = false
  s.current_response = ""
  set_state(s, "generating")

  spinner.start("generating", function(frame, _)
    s.spinner_frame = frame
    update_winbar(s)
    if not s.got_first_chunk then
      show_inline_loading(s, frame)
    end
  end)

  log.info("sidebar", "starting agent", { prompt_len = #full_prompt, model = config.get().model })
  local handle = agent.start({
    prompt = full_prompt,
    on_event = function(event)
      log.debug("sidebar", "on_event", { type = event.type, model = event.model })
      if event.type == "agent_created" or event.type == "agent" then
        local m = event.model
        if m and m ~= "" then
          s.last_model = m
          log.info("sidebar", "model detected from stream", { model = m })
          update_winbar(s)
        end
      elseif event.type == "thinking" or event.type == "task" then
        if not s.got_first_chunk then
          render.clear_thinking(s.transcript_buf)
          local hint = (type(event.text) == "string" and event.text ~= "") and event.text
            or "Thinking..."
          render.show_thinking(s.transcript_buf, hint)
          if s.state == "generating" then
            spinner.stop()
            spinner.start("thinking", function(frame, _)
              s.spinner_frame = frame
              update_winbar(s)
            end)
          end
        end
      end
    end,
    on_chunk = function(text)
      log.debug("sidebar", "on_chunk", { length = #text, first = not s.got_first_chunk })
      if not s.got_first_chunk then
        s.got_first_chunk = true
        clear_inline_loading(s)
        render.clear_thinking(s.transcript_buf)
        if spinner.is_running() then
          spinner.stop()
          spinner.start("generating", function(frame, _)
            s.spinner_frame = frame
            update_winbar(s)
          end)
        end
      end
      s.current_response = (s.current_response or "") .. text
      ui_util.append_text(s.transcript_buf, text)
      if s.assistant_region then
        s.assistant_region.end_line = vim.api.nvim_buf_line_count(s.transcript_buf)
      end
      ui_util.scroll_to_end(s.transcript_win, s.transcript_buf)
    end,
    on_done = function(code)
      log.info("sidebar", "on_done", { code = code })
      clear_inline_loading(s)
      local success = code == 0
      set_state(s, success and "done" or "error")
      spinner.finish(success, function(frame, _)
        s.spinner_frame = frame
        update_winbar(s)
        vim.defer_fn(function()
          s.spinner_frame = nil
          if s.state ~= "error" then
            set_state(s, nil)
          end
        end, 3000)
      end)
      if not success then
        append_error(s, "Agent exited with code " .. tostring(code))
      end
      ui_util.append_text(s.transcript_buf, "\n")
      ui_util.scroll_to_end(s.transcript_win, s.transcript_buf)
      local response_text = s.current_response or ""
      if s.assistant_region then
        s.assistant_region.end_line = vim.api.nvim_buf_line_count(s.transcript_buf)
        local cfg_done = config.get()
        if cfg_done.ui and cfg_done.ui.fold_messages and s.transcript_win then
          pcall(
            vim.cmd,
            string.format("%d,%dfold", s.assistant_region.header_line, s.assistant_region.end_line)
          )
        end
      end
      table.insert(s.conversation.messages, {
        role = "assistant",
        content = response_text,
        timestamp = os.time(),
      })
      s.current_response = ""
      if s.conversation.id then
        pcall(history.save, s.conversation.id, s.conversation)
      end
    end,
    on_error = function(line)
      log.warn("sidebar", "on_error", { line = line })
      clear_inline_loading(s)
      ui_util.append_text(s.transcript_buf, "\n⚠ " .. line .. "\n")
      ui_util.scroll_to_end(s.transcript_win, s.transcript_buf)
    end,
  })

  if not handle then
    log.error("sidebar", "agent.start() returned nil")
    spinner.stop()
    clear_inline_loading(s)
    set_state(s, "error")
    append_error(s, "Failed to start agent. Check :checkhealth cursor")
  end
end

local function insert_blocks_at_cursor(buf, blocks)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    return 0
  end
  vim.api.nvim_set_current_win(win)
  local row, _ = unpack(vim.api.nvim_win_get_cursor(win))
  local inserted = 0
  for _, block in ipairs(blocks) do
    local lines = block.lines or {}
    if #lines > 0 then
      vim.api.nvim_buf_set_lines(buf, row, row, false, lines)
      row = row + #lines
      inserted = inserted + 1
    end
  end
  return inserted
end

local function get_assistant_text(s)
  local region = render.last_assistant_region(s.message_regions or {})
  if region then
    return render.get_region_text(s.transcript_buf, region)
  end
  return s.current_response or ""
end

function M.apply_suggestion(s, apply_all)
  s = s or M.get_sidebar()
  if not s then
    return
  end
  local text = get_assistant_text(s)
  local blocks = render.extract_fenced_blocks(text)
  if #blocks == 0 then
    vim.notify("cursor.nvim: no code blocks in the latest response", vim.log.levels.INFO)
    return
  end
  local buf = get_code_buf(s)
  if not buf or not ui_util.buf_is_normal(buf) then
    vim.notify("cursor.nvim: no code buffer to apply into", vim.log.levels.WARN)
    return
  end
  if apply_all then
    local n = insert_blocks_at_cursor(buf, blocks)
    vim.notify("cursor.nvim: applied " .. n .. " code block(s)", vim.log.levels.INFO)
    return
  end
  local labels = {}
  for i, block in ipairs(blocks) do
    local lang = block.lang ~= "" and block.lang or "text"
    local preview = table.concat(block.lines, " "):sub(1, 40)
    table.insert(labels, string.format("%d: %s — %s…", i, lang, preview))
  end
  vim.ui.select(labels, { prompt = "Apply code block:" }, function(_, idx)
    if idx then
      insert_blocks_at_cursor(buf, { blocks[idx] })
      vim.notify("cursor.nvim: applied code block " .. idx, vim.log.levels.INFO)
    end
  end)
end

function M.manage_context(s)
  s = s or M.get_sidebar()
  if not s then
    return
  end
  s.context_items = s.context_items or {}
  if #s.context_items == 0 then
    vim.notify("cursor.nvim: no context attached (use @ in the prompt)", vim.log.levels.INFO)
    return
  end
  local choices = { "— Clear all —" }
  for _, item in ipairs(s.context_items) do
    table.insert(choices, context_label(item))
  end
  vim.ui.select(choices, { prompt = "Context:" }, function(choice)
    if not choice then
      return
    end
    if choice == "— Clear all —" then
      s.context_items = {}
    else
      for i, item in ipairs(s.context_items) do
        if context_label(item) == choice then
          table.remove(s.context_items, i)
          break
        end
      end
    end
    update_input_winbar(s)
    vim.notify("cursor.nvim: context updated", vim.log.levels.INFO)
  end)
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
      local ui_cfg = config.get().ui or {}
      if ui_cfg.close_on_empty_ctrl_c then
        local lines = vim.api.nvim_buf_get_lines(s.input_buf, 0, -1, false)
        local joined = vim.trim(table.concat(lines, "\n"))
        if joined == "" then
          M.close()
          return
        end
      end
      vim.cmd("stopinsert")
    end, vim.tbl_extend("force", input_opts, { desc = "cursor.nvim: exit insert mode" }))
  end

  local ctx_key = sidebar_keys.context or ",c"
  vim.keymap.set("n", ctx_key, function()
    M.manage_context(s)
  end, vim.tbl_extend("force", input_opts, { desc = "cursor.nvim: manage file context" }))

  local skills_key = sidebar_keys.skills or ",s"
  vim.keymap.set("n", skills_key, function()
    M.manage_skills(s)
  end, vim.tbl_extend("force", input_opts, { desc = "cursor.nvim: manage skills" }))

  vim.keymap.set("n", "@", function()
    M.add_context(s)
  end, vim.tbl_extend("force", input_opts, { desc = "cursor.nvim: add context" }))

  vim.keymap.set("i", "@", function()
    vim.cmd("stopinsert")
    M.add_context(s)
  end, vim.tbl_extend("force", input_opts, { desc = "cursor.nvim: add context" }))

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
    M.apply_suggestion(s, false)
  end, vim.tbl_extend("force", transcript_opts, { desc = "cursor.nvim: apply suggestion" }))

  vim.keymap.set("n", sidebar_keys.apply_all or "A", function()
    M.apply_suggestion(s, true)
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
  log.info("sidebar", "open()", { tab = tid, has_selection = opts.selection ~= nil })
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
      selected_code_buf = create_selected_code(),
      conversation = { messages = {}, id = history.generate_id() },
      context_items = {},
      active_skills = {},
      spinner_frame = nil,
      state = nil,
      last_model = nil,
      has_welcome = false,
      got_first_chunk = false,
      zen = false,
      message_regions = {},
      current_response = "",
      assistant_region = nil,
    }
    sidebars[tid] = s
  end

  open_windows(s, cfg)
  bind_keymaps(s)
  setup_autocmds(s)

  if cfg.ui and cfg.ui.welcome and #s.conversation.messages == 0 then
    render_welcome(s.transcript_buf, s.transcript_win)
    s.has_welcome = true
  end

  if opts.selection then
    update_selected_code(s, opts.selection)
    show_selected_code_win(s)
  end

  update_input_winbar(s)

  vim.api.nvim_set_current_win(s.input_win)
  return s
end

function M.close()
  local tid = tab_id()
  log.info("sidebar", "close()", { tab = tid })
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
    s.context_items = {}
    s.active_skills = {}
    s.has_welcome = false
    s.last_model = nil
    reset_transcript_state(s)
    update_input_winbar(s)
    selection.clear()
    hide_selected_code_win(s)
    local was = vim.bo[s.transcript_buf].modifiable
    vim.bo[s.transcript_buf].modifiable = true
    vim.api.nvim_buf_set_lines(s.transcript_buf, 0, -1, false, {})
    vim.bo[s.transcript_buf].modifiable = was
    vim.api.nvim_buf_set_lines(s.input_buf, 0, -1, false, { "" })
    set_state(s, nil)
    local cfg = config.get()
    if cfg.ui and cfg.ui.welcome then
      render_welcome(s.transcript_buf, s.transcript_win)
      s.has_welcome = true
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
    local height = calc_height()
    pcall(vim.api.nvim_win_set_height, s.transcript_win, height)
    if s.input_win and vim.api.nvim_win_is_valid(s.input_win) then
      pcall(vim.api.nvim_win_set_height, s.input_win, height)
    end
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
  if not s.transcript_win or not vim.api.nvim_win_is_valid(s.transcript_win) then
    return
  end
  if s.message_regions and #s.message_regions > 0 then
    local cursor_line = vim.api.nvim_win_get_cursor(s.transcript_win)[1]
    for _, region in ipairs(s.message_regions) do
      if region.header_line > cursor_line then
        vim.api.nvim_win_set_cursor(s.transcript_win, { region.header_line, 0 })
        return
      end
    end
    return
  end
  local lines = vim.api.nvim_buf_get_lines(s.transcript_buf, 0, -1, false)
  local cursor_line = vim.api.nvim_win_get_cursor(s.transcript_win)[1]
  for i = cursor_line + 1, #lines do
    if render.is_header_line(lines[i]) then
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
  if not s.transcript_win or not vim.api.nvim_win_is_valid(s.transcript_win) then
    return
  end
  if s.message_regions and #s.message_regions > 0 then
    local cursor_line = vim.api.nvim_win_get_cursor(s.transcript_win)[1]
    local prev = nil
    for _, region in ipairs(s.message_regions) do
      if region.header_line < cursor_line then
        prev = region
      end
    end
    if prev then
      vim.api.nvim_win_set_cursor(s.transcript_win, { prev.header_line, 0 })
    end
    return
  end
  local lines = vim.api.nvim_buf_get_lines(s.transcript_buf, 0, -1, false)
  local cursor_line = vim.api.nvim_win_get_cursor(s.transcript_win)[1]
  for i = cursor_line - 1, 1, -1 do
    if render.is_header_line(lines[i]) then
      vim.api.nvim_win_set_cursor(s.transcript_win, { i, 0 })
      return
    end
  end
end

function M.add_context(s)
  s = s or M.get_sidebar()
  if not s then
    return
  end
  local cwd = vim.fn.getcwd()
  local choices = {}
  local choice_items = {}
  local function add_choice(label, item)
    table.insert(choices, label)
    choice_items[label] = item
  end
  add_choice("@buffer Current buffer", {
    type = "buffer",
    buf = vim.api.nvim_get_current_buf(),
    name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()),
  })
  if selection.format_context() then
    add_choice("@selection Visual selection", { type = "selection", name = "selection" })
  end
  if ui_util.get_project_instructions() then
    add_choice(
      "@instructions Project instructions",
      { type = "instructions", name = "instructions" }
    )
  end
  for _, rel in ipairs(ui_util.find_project_files({ cwd = cwd })) do
    local path = cwd .. "/" .. rel
    add_choice("@" .. rel, { type = "file", path = path, name = rel })
  end
  table.sort(choices)
  vim.ui.select(choices, { prompt = "Add context:" }, function(choice)
    if choice then
      local item = choice_items[choice]
      if item and ensure_context_item(s, item) then
        insert_context_mention(s, item)
        update_input_winbar(s)
        vim.notify(
          "cursor.nvim: added " .. context_label(item) .. " to context",
          vim.log.levels.INFO
        )
      end
    end
  end)
end

function M.add_file_context(s)
  return M.add_context(s)
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
  local item = { type = "file", path = name, name = vim.fn.fnamemodify(name, ":.") }
  if ensure_context_item(s, item) then
    insert_context_mention(s, item)
    update_input_winbar(s)
    vim.notify("cursor.nvim: added " .. context_label(item) .. " to context", vim.log.levels.INFO)
  end
end

function M.select_model()
  local function open_picker(models)
    if #models == 0 then
      models = fallback_models
    elseif models[1] ~= "default" then
      table.insert(models, 1, "default")
    end
    vim.ui.select(models, { prompt = "Select model:" }, function(choice)
      if choice then
        local cfg = config.get()
        local model_id = choice:match("^([^%s]+)") or choice
        if model_id == "default" then
          cfg.model = nil
        else
          cfg.model = model_id
        end
        local s = M.get_sidebar()
        if s then
          update_winbar(s)
        end
        vim.notify("cursor.nvim: model set to " .. model_id, vim.log.levels.INFO)
      end
    end)
  end
  if not agent.list_models(function(models)
    open_picker(models)
  end) then
    open_picker(vim.deepcopy(fallback_models))
  end
end

function M.select_mode()
  local modes = { "agent", "plan", "ask" }
  vim.ui.select(modes, { prompt = "Select Cursor mode:" }, function(choice)
    if choice then
      local cfg = config.get()
      cfg.mode = choice
      local s = M.get_sidebar()
      if s then
        update_winbar(s)
      end
      vim.notify("cursor.nvim: mode set to " .. choice, vim.log.levels.INFO)
    end
  end)
end

function M.toggle_plan()
  local cfg = config.get()
  cfg.mode = cfg.mode == "plan" and "agent" or "plan"
  local s = M.get_sidebar()
  if s then
    update_winbar(s)
  end
  vim.notify("cursor.nvim: mode set to " .. cfg.mode, vim.log.levels.INFO)
end

function M.insert_skill()
  local s = M.get_sidebar()
  if not s then
    M.open()
    s = M.get_sidebar()
  end
  if not s then
    return
  end
  local cfg = config.get()
  local skill_cfg = cfg.skills or {}
  local commands = skill_cfg.commands or {}
  if #commands == 0 then
    vim.notify(
      "cursor.nvim: configure setup({ skills = { commands = { ... } } }) to use skill insertion",
      vim.log.levels.INFO
    )
    return
  end
  local choices = {}
  local by_label = {}
  for _, skill in ipairs(commands) do
    local name = type(skill) == "table" and skill.name or skill
    if name and name ~= "" then
      local label = "/" .. name
      if type(skill) == "table" and skill.description then
        label = label .. " — " .. skill.description
      end
      table.insert(choices, label)
      by_label[label] = "/" .. name .. " "
    end
  end
  table.sort(choices)
  vim.ui.select(choices, { prompt = "Insert skill:" }, function(choice)
    if choice then
      local text = by_label[choice]
      local line = vim.api.nvim_buf_get_lines(s.input_buf, -2, -1, false)[1] or ""
      local prefix = line == "" and "" or " "
      vim.api.nvim_buf_set_lines(s.input_buf, -2, -1, false, { line .. prefix .. text })
      vim.api.nvim_set_current_win(s.input_win)
      vim.cmd("normal! G$")
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
        reset_transcript_state(s)
        local cfg_hist = config.get()
        local fold_opts = message_fold_opts(cfg_hist, s)
        for _, msg in ipairs(conv.messages or {}) do
          local role = msg.role == "user" and "user" or "assistant"
          local region = render.append_message(s.transcript_buf, role, msg.content or "", fold_opts)
          table.insert(s.message_regions, region)
        end
        vim.bo[s.transcript_buf].modifiable = was
        ui_util.scroll_to_end(s.transcript_win, s.transcript_buf)
      end
    end
  end)
end

return M
