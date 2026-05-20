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
  vim.api.nvim_win_set_cursor(win, { last, 0 })
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

return M
