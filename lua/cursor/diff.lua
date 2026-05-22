local config = require("cursor.config")

local M = {}

local ns = vim.api.nvim_create_namespace("cursor_diff")

local MARKER_OURS = "<<<<<<< HEAD"
local MARKER_SEP = "======="
local MARKER_THEIRS = ">>>>>>> Cursor"

local function define_highlights()
  local hi = vim.api.nvim_set_hl
  hi(0, "CursorConflictCurrent", { bg = "#2e1f1f", default = true })
  hi(
    0,
    "CursorConflictCurrentLabel",
    { bg = "#4b2020", fg = "#e06c75", bold = true, default = true }
  )
  hi(0, "CursorConflictIncoming", { bg = "#1f2e1f", default = true })
  hi(
    0,
    "CursorConflictIncomingLabel",
    { bg = "#204b20", fg = "#98c379", bold = true, default = true }
  )
  hi(0, "CursorConflictSeparator", { fg = "#565c64", bold = true, default = true })
end

define_highlights()

local function find_conflicts(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local conflicts = {}
  local i = 1
  while i <= #lines do
    if lines[i]:match("^" .. vim.pesc(MARKER_OURS)) then
      local conflict = { ours_start = i }
      for j = i + 1, #lines do
        if lines[j]:match("^" .. vim.pesc(MARKER_SEP)) then
          conflict.sep = j
        elseif lines[j]:match("^" .. vim.pesc(MARKER_THEIRS)) then
          conflict.theirs_end = j
          table.insert(conflicts, conflict)
          i = j
          break
        end
      end
    end
    i = i + 1
  end
  return conflicts
end

local function highlight_conflicts(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local conflicts = find_conflicts(buf)
  for _, c in ipairs(conflicts) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, c.ours_start - 1, 0, {
      end_row = c.ours_start - 1,
      end_col = 0,
      hl_group = "CursorConflictCurrentLabel",
      virt_text = { { " (Current changes) ", "CursorConflictCurrentLabel" } },
      virt_text_pos = "eol",
    })
    for line = c.ours_start, (c.sep or c.theirs_end) - 2 do
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, line, 0, {
        end_row = line + 1,
        hl_eol = true,
        hl_group = "CursorConflictCurrent",
      })
    end
    if c.sep then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, c.sep - 1, 0, {
        end_row = c.sep - 1,
        end_col = 0,
        hl_group = "CursorConflictSeparator",
      })
    end
    if c.sep and c.theirs_end then
      for line = c.sep, c.theirs_end - 2 do
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, line, 0, {
          end_row = line + 1,
          hl_eol = true,
          hl_group = "CursorConflictIncoming",
        })
      end
    end
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, c.theirs_end - 1, 0, {
      end_row = c.theirs_end - 1,
      end_col = 0,
      hl_group = "CursorConflictIncomingLabel",
      virt_text = { { " (Incoming changes) ", "CursorConflictIncomingLabel" } },
      virt_text_pos = "eol",
    })
  end
  return conflicts
end

function M.insert_conflict(buf, start_line, original_lines, suggested_lines)
  local markers = { MARKER_OURS }
  vim.list_extend(markers, original_lines)
  table.insert(markers, MARKER_SEP)
  vim.list_extend(markers, suggested_lines)
  table.insert(markers, MARKER_THEIRS)
  vim.api.nvim_buf_set_lines(buf, start_line - 1, start_line - 1 + #original_lines, false, markers)
  highlight_conflicts(buf)
end

local function resolve_conflict(buf, conflict, keep)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local result = {}
  if keep == "ours" then
    for i = conflict.ours_start + 1, (conflict.sep or conflict.theirs_end) - 1 do
      table.insert(result, lines[i])
    end
  elseif keep == "theirs" then
    if conflict.sep then
      for i = conflict.sep + 1, conflict.theirs_end - 1 do
        table.insert(result, lines[i])
      end
    end
  elseif keep == "both" then
    for i = conflict.ours_start + 1, (conflict.sep or conflict.theirs_end) - 1 do
      table.insert(result, lines[i])
    end
    if conflict.sep then
      for i = conflict.sep + 1, conflict.theirs_end - 1 do
        table.insert(result, lines[i])
      end
    end
  end
  vim.api.nvim_buf_set_lines(buf, conflict.ours_start - 1, conflict.theirs_end, false, result)
  highlight_conflicts(buf)
end

function M.resolve_at_cursor(buf, keep)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local conflicts = find_conflicts(buf)
  for _, c in ipairs(conflicts) do
    if cursor_line >= c.ours_start and cursor_line <= c.theirs_end then
      resolve_conflict(buf, c, keep)
      return true
    end
  end
  return false
end

function M.resolve_all(buf, keep)
  local conflicts = find_conflicts(buf)
  for i = #conflicts, 1, -1 do
    resolve_conflict(buf, conflicts[i], keep)
  end
end

function M.goto_next(buf)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local conflicts = find_conflicts(buf)
  for _, c in ipairs(conflicts) do
    if c.ours_start > cursor_line then
      vim.api.nvim_win_set_cursor(0, { c.ours_start, 0 })
      return true
    end
  end
  if #conflicts > 0 then
    vim.api.nvim_win_set_cursor(0, { conflicts[1].ours_start, 0 })
    return true
  end
  return false
end

function M.goto_prev(buf)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local conflicts = find_conflicts(buf)
  for i = #conflicts, 1, -1 do
    if conflicts[i].ours_start < cursor_line then
      vim.api.nvim_win_set_cursor(0, { conflicts[i].ours_start, 0 })
      return true
    end
  end
  if #conflicts > 0 then
    vim.api.nvim_win_set_cursor(0, { conflicts[#conflicts].ours_start, 0 })
    return true
  end
  return false
end

function M.setup_keymaps(buf)
  local cfg = config.get()
  local diff_cfg = cfg.diff or {}
  local opts = { buffer = buf, silent = true }
  if diff_cfg.ours then
    vim.keymap.set("n", diff_cfg.ours, function()
      M.resolve_at_cursor(buf, "ours")
    end, vim.tbl_extend("force", opts, { desc = "cursor.nvim: keep current" }))
  end
  if diff_cfg.theirs then
    vim.keymap.set("n", diff_cfg.theirs, function()
      M.resolve_at_cursor(buf, "theirs")
    end, vim.tbl_extend("force", opts, { desc = "cursor.nvim: accept incoming" }))
  end
  if diff_cfg.all_theirs then
    vim.keymap.set("n", diff_cfg.all_theirs, function()
      M.resolve_all(buf, "theirs")
    end, vim.tbl_extend("force", opts, { desc = "cursor.nvim: accept all" }))
  end
  if diff_cfg.both then
    vim.keymap.set("n", diff_cfg.both, function()
      M.resolve_at_cursor(buf, "both")
    end, vim.tbl_extend("force", opts, { desc = "cursor.nvim: keep both" }))
  end
  if diff_cfg.next then
    vim.keymap.set("n", diff_cfg.next, function()
      M.goto_next(buf)
    end, vim.tbl_extend("force", opts, { desc = "cursor.nvim: next conflict" }))
  end
  if diff_cfg.prev then
    vim.keymap.set("n", diff_cfg.prev, function()
      M.goto_prev(buf)
    end, vim.tbl_extend("force", opts, { desc = "cursor.nvim: prev conflict" }))
  end
end

function M.refresh(buf)
  highlight_conflicts(buf)
end

return M
