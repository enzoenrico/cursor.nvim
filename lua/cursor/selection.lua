local config = require("cursor.config")

local M = {}

local state = {
  content = nil,
  filetype = nil,
  filepath = nil,
  range = nil,
  augroup = nil,
  hint_ns = vim.api.nvim_create_namespace("cursor_selection_hints"),
  highlight_ns = vim.api.nvim_create_namespace("cursor_selection_hl"),
}

local function clear_hints(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, state.hint_ns, 0, -1)
  end
end

local function show_hints(buf, line)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  clear_hints(buf)
  local cfg = config.get()
  local mappings = cfg.mappings or {}
  local ask_key = mappings.ask or "<leader>ca"
  local edit_key = mappings.edit or "<leader>ce"
  local hint_text = string.format("[%s: ask, %s: edit]", ask_key, edit_key)
  pcall(vim.api.nvim_buf_set_extmark, buf, state.hint_ns, line, 0, {
    virt_text = { { hint_text, "Comment" } },
    virt_text_pos = "eol",
  })
end

function M.capture()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return nil
  end
  vim.cmd('noautocmd normal! "zy')
  local content = vim.fn.getreg("z")
  if not content or content == "" then
    return nil
  end
  local buf = vim.api.nvim_get_current_buf()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  state.content = content
  state.filetype = vim.bo[buf].filetype
  state.filepath = vim.api.nvim_buf_get_name(buf)
  state.range = {
    start_line = start_pos[2],
    start_col = start_pos[3],
    end_line = end_pos[2],
    end_col = end_pos[3],
  }
  return M.get()
end

function M.capture_from_range()
  local buf = vim.api.nvim_get_current_buf()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.api.nvim_buf_get_lines(buf, start_pos[2] - 1, end_pos[2], false)
  if #lines == 0 then
    return nil
  end
  state.content = table.concat(lines, "\n")
  state.filetype = vim.bo[buf].filetype
  state.filepath = vim.api.nvim_buf_get_name(buf)
  state.range = {
    start_line = start_pos[2],
    start_col = start_pos[3],
    end_line = end_pos[2],
    end_col = end_pos[3],
  }
  return M.get()
end

function M.get()
  if not state.content then
    return nil
  end
  return {
    content = state.content,
    filetype = state.filetype,
    filepath = state.filepath,
    range = state.range,
  }
end

function M.clear()
  if state.highlight_ns then
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_clear_namespace(buf, state.highlight_ns, 0, -1)
        clear_hints(buf)
      end
    end
  end
  state.content = nil
  state.filetype = nil
  state.filepath = nil
  state.range = nil
end

function M.highlight_selection(buf, range)
  if not buf or not vim.api.nvim_buf_is_valid(buf) or not range then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, state.highlight_ns, 0, -1)
  for line = range.start_line - 1, range.end_line - 1 do
    pcall(vim.api.nvim_buf_set_extmark, buf, state.highlight_ns, line, 0, {
      end_line = line + 1,
      hl_group = "Visual",
    })
  end
end

function M.setup_autocmds()
  if state.augroup then
    return
  end
  local cfg = config.get()
  local hint_mode = cfg.selection and cfg.selection.hints or "delayed"
  if hint_mode == "none" then
    return
  end
  state.augroup = vim.api.nvim_create_augroup("CursorSelection", { clear = true })
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = state.augroup,
    pattern = { "n:v", "n:V", "n:\22" },
    callback = function()
      if hint_mode == "always" then
        local buf = vim.api.nvim_get_current_buf()
        local line = vim.fn.line(".") - 1
        show_hints(buf, line)
      elseif hint_mode == "delayed" then
        vim.defer_fn(function()
          local mode = vim.fn.mode()
          if mode == "v" or mode == "V" or mode == "\22" then
            local buf = vim.api.nvim_get_current_buf()
            local line = vim.fn.line("'>") - 1
            show_hints(buf, line)
          end
        end, vim.o.updatetime)
      end
    end,
  })
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = state.augroup,
    pattern = { "v:n", "V:n", "\22:n" },
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      clear_hints(buf)
    end,
  })
end

function M.format_context()
  local sel = M.get()
  if not sel then
    return nil
  end
  local header = string.format("```%s\n", sel.filetype or "")
  local footer = "\n```"
  local filepath = sel.filepath and sel.filepath ~= "" and vim.fn.fnamemodify(sel.filepath, ":.")
    or nil
  local prefix = ""
  if filepath then
    prefix =
      string.format("File: %s (lines %d-%d)\n", filepath, sel.range.start_line, sel.range.end_line)
  end
  return prefix .. header .. sel.content .. footer
end

return M
