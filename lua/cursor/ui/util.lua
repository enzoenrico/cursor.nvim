local M = {}

function M.scratch_buf(opts)
  opts = opts or {}
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "hide"
  if opts.filetype then
    vim.bo[buf].filetype = opts.filetype
  end
  if opts.modifiable == false then
    vim.bo[buf].modifiable = false
  end
  return buf
end

function M.append_text(buf, text)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local was_modifiable = vim.bo[buf].modifiable
  if not was_modifiable then
    vim.bo[buf].modifiable = true
  end
  local lines = vim.split(text, "\n", { plain = true })
  local last = vim.api.nvim_buf_line_count(buf)
  local last_line = vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1] or ""
  lines[1] = last_line .. lines[1]
  vim.api.nvim_buf_set_lines(buf, last - 1, last, false, lines)
  if not was_modifiable then
    vim.bo[buf].modifiable = false
  end
end

function M.scroll_to_end(win, buf)
  if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local last = vim.api.nvim_buf_line_count(buf)
  pcall(vim.api.nvim_win_set_cursor, win, { last, 0 })
end

function M.replace_lines(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local was_modifiable = vim.bo[buf].modifiable
  if not was_modifiable then
    vim.bo[buf].modifiable = true
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if not was_modifiable then
    vim.bo[buf].modifiable = false
  end
end

function M.safe_keymap_set(mode, lhs, rhs, opts)
  local existing = vim.fn.maparg(lhs, mode, false, true)
  if existing and existing.lhs and existing.lhs ~= "" then
    if not (existing.desc and existing.desc:match("^cursor%.nvim")) then
      return false
    end
  end
  vim.keymap.set(mode, lhs, rhs, opts)
  return true
end

function M.buf_is_normal(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local bt = vim.bo[buf].buftype
  return bt == "" or bt == nil
end

local placeholder_ns = vim.api.nvim_create_namespace("cursor_placeholder")

function M.set_placeholder(buf, text)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, placeholder_ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local is_empty = #lines == 0 or (#lines == 1 and lines[1] == "")
  if is_empty then
    pcall(vim.api.nvim_buf_set_extmark, buf, placeholder_ns, 0, 0, {
      virt_text = { { text, "Comment" } },
      virt_text_pos = "overlay",
    })
  end
end

function M.setup_placeholder_autocmds(buf, text)
  local group = vim.api.nvim_create_augroup("CursorPlaceholder" .. buf, { clear = true })
  M.set_placeholder(buf, text)
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = buf,
    callback = function()
      M.set_placeholder(buf, text)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
end

function M.center_text(text, width)
  local pad = math.max(0, math.floor((width - vim.fn.strdisplaywidth(text)) / 2))
  return string.rep(" ", pad) .. text
end

local IGNORE_DIRS = {
  [".git"] = true,
  ["node_modules"] = true,
  [".deps"] = true,
  [".venv"] = true,
  ["venv"] = true,
  ["dist"] = true,
  ["build"] = true,
  [".cache"] = true,
}

function M.should_ignore_path(path)
  for part in path:gmatch("[^/]+") do
    if IGNORE_DIRS[part] then
      return true
    end
  end
  return false
end

--- Collect project files for @ context picker (capped, sorted).
function M.find_project_files(opts)
  opts = opts or {}
  local cwd = opts.cwd or vim.fn.getcwd()
  local max = opts.max or 500
  local results = {}

  local ok, paths = pcall(vim.fs.find, function(name, path)
    if name:sub(1, 1) == "." and name ~= ".cursor.md" and name ~= ".cursorcontext" then
      return false
    end
    local rel = path:sub(#cwd + 2)
    if rel == "" then
      rel = name
    else
      rel = rel .. "/" .. name
    end
    if M.should_ignore_path(rel) then
      return false
    end
    return vim.fn.isdirectory(path) == 0
  end, {
    path = cwd,
    type = "file",
    limit = max * 4,
  })

  if not ok or not paths then
    return {}
  end

  for _, abs in ipairs(paths) do
    if vim.fn.isdirectory(abs) == 0 then
      local rel = abs:sub(#cwd + 2)
      if rel ~= "" and not M.should_ignore_path(rel) then
        table.insert(results, rel)
      end
    end
    if #results >= max then
      break
    end
  end

  table.sort(results)
  return results
end

function M.get_project_instructions()
  local markers = { ".cursor.md", ".cursorcontext", "cursor.md" }
  local cwd = vim.fn.getcwd()
  for _, name in ipairs(markers) do
    local path = cwd .. "/" .. name
    if vim.fn.filereadable(path) == 1 then
      local lines = vim.fn.readfile(path)
      if lines and #lines > 0 then
        return table.concat(lines, "\n")
      end
    end
  end
  return nil
end

return M
