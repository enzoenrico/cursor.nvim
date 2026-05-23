local M = {}

M.defaults = {
  cmd = "cursor-agent",
  model = nil,
  keymaps = false,
  ui = {
    layout = "vsplit",
    transcript_filetype = "markdown",
    prompt_height = 6,
  },
  notify = true,
}

local current = vim.deepcopy(M.defaults)

function M.setup(opts)
  current = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return current
end

function M.get()
  return current
end

function M.reset()
  current = vim.deepcopy(M.defaults)
  return current
end

return M
