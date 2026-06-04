local M = {}

M.ns = vim.api.nvim_create_namespace("cursor_messages")
M.thinking_ns = vim.api.nvim_create_namespace("cursor_thinking")

M.HEADER_USER = "━━━ You ━━━"
M.HEADER_ASSISTANT = "━━━ Cursor ━━━"

local ROLE_HL = {
  user = "CursorRoleUser",
  assistant = "CursorRoleAssistant",
}

local function with_modifiable(buf, fn)
  local was = vim.bo[buf].modifiable
  if not was then
    vim.bo[buf].modifiable = true
  end
  local ok, err = pcall(fn)
  if not was then
    vim.bo[buf].modifiable = false
  end
  if not ok then
    error(err)
  end
end

function M.header_line(role)
  if role == "user" then
    return M.HEADER_USER
  end
  return M.HEADER_ASSISTANT
end

function M.is_header_line(line)
  if not line or line == "" then
    return false
  end
  return line:match("^━━━") ~= nil
end

function M.mark_header(buf, line_nr, role)
  local hl = ROLE_HL[role] or "CursorRoleSeparator"
  local header = vim.api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1] or ""
  pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, line_nr, 0, {
    end_row = line_nr,
    end_col = #header,
    hl_group = hl,
    priority = 10,
  })
  local sep_col = header:find("━", 1, true)
  if sep_col then
    pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, line_nr, sep_col - 1, {
      end_row = line_nr,
      end_col = sep_col + 2,
      hl_group = "CursorRoleSeparator",
      priority = 5,
    })
  end
end

---@param buf number
---@param role "user"|"assistant"
---@param content string
---@param opts? { fold?: boolean, win?: number }
---@return table region { role, header_line, start_line, end_line } 1-based lines
function M.append_message(buf, role, content, opts)
  opts = opts or {}
  local header = M.header_line(role)
  local body = content or ""
  local ui_util = require("cursor.ui.util")

  local lc = vim.api.nvim_buf_line_count(buf)
  local last_line = vim.api.nvim_buf_get_lines(buf, math.max(0, lc - 1), lc, false)[1] or ""
  local prefix = (last_line ~= "" and lc > 0) and "\n" or ""
  local block = prefix .. header .. "\n" .. body
  if body == "" or not body:match("\n$") then
    block = block .. "\n"
  end

  with_modifiable(buf, function()
    ui_util.append_text(buf, block)
  end)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local header_line = #lines
  for i = #lines, 1, -1 do
    if lines[i] == header then
      header_line = i
      break
    end
  end

  M.mark_header(buf, header_line - 1, role)

  local end_line = #lines
  local region = {
    role = role,
    header_line = header_line,
    start_line = header_line,
    end_line = end_line,
  }

  if opts.fold and opts.win and vim.api.nvim_win_is_valid(opts.win) then
    pcall(vim.cmd, string.format("%d,%dfold", header_line, end_line))
  end

  return region
end

function M.clear_messages(buf)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, M.thinking_ns, 0, -1)
end

function M.show_thinking(buf, text)
  vim.api.nvim_buf_clear_namespace(buf, M.thinking_ns, 0, -1)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local display = text or "Thinking..."
  pcall(vim.api.nvim_buf_set_extmark, buf, M.thinking_ns, line_count - 1, 0, {
    virt_lines = { { { " " .. display, "CursorThinking" } } },
  })
end

function M.clear_thinking(buf)
  vim.api.nvim_buf_clear_namespace(buf, M.thinking_ns, 0, -1)
end

--- Extract fenced code blocks from markdown text.
---@return { lang: string, lines: string[] }[]
function M.extract_fenced_blocks(text)
  if not text or text == "" then
    return {}
  end
  local blocks = {}
  local in_fence = false
  local lang = ""
  local current = {}

  for line in (text .. "\n"):gmatch("(.-)\n") do
    local fence, info = line:match("^```(%S*)")
    if fence ~= nil or line:match("^```%s*$") then
      if not in_fence then
        in_fence = true
        lang = info or fence or ""
        current = {}
      else
        in_fence = false
        table.insert(blocks, { lang = lang, lines = current })
        lang = ""
        current = {}
      end
    elseif in_fence then
      table.insert(current, line)
    end
  end

  return blocks
end

function M.last_assistant_region(message_regions)
  for i = #message_regions, 1, -1 do
    local r = message_regions[i]
    if r.role == "assistant" then
      return r
    end
  end
  return nil
end

function M.get_region_text(buf, region)
  if not region then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(buf, region.start_line, region.end_line, false)
  -- Skip header line
  if #lines > 0 and M.is_header_line(lines[1]) then
    table.remove(lines, 1)
  end
  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end
  return table.concat(lines, "\n")
end

return M
