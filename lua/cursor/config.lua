local M = {}

M.defaults = {
  cmd = "cursor-agent",
  transport = "cli",
  model = nil,
  model_params = {},
  mode = "agent",
  output_format = "stream-json",
  stream_partial_output = true,
  force = false,
  sandbox = nil,
  trust = false,
  approve_mcps = false,
  workspace = nil,
  headers = {},
  plugin_dirs = {},
  extra_args = {},
  models = nil,
  skills = {
    paths = nil,
    commands = {},
  },
  sdk = {
    cmd = nil,
    runtime = "local",
    api_key_env = "CURSOR_API_KEY",
    force = false,
    extra_args = {},
  },
  keymaps = false,
  ui = {
    layout = "right",
    width = 30,
    prompt_height = 8,
    transcript_filetype = "CursorChat",
    winborder = "rounded",
    use_colorscheme = false,
    close_on_empty_ctrl_c = false,
    fold_messages = true,
    sidebar_header = {
      enabled = true,
    },
    prompt_prefix = "> ",
    show_hints = true,
    welcome = true,
  },
  diff = {
    ours = "co",
    theirs = "ct",
    all_theirs = "ca",
    both = "cb",
    next = "]x",
    prev = "[x",
  },
  selection = {
    hints = "delayed",
  },
  history = {
    enabled = true,
    path = nil,
  },
  mappings = {
    toggle = "<leader>ct",
    focus = "<leader>cf",
    chat = "<leader>cc",
    ask = "<leader>ca",
    new = "<leader>cn",
    edit = "<leader>ce",
    stop = "<leader>cs",
    status = "<leader>c?",
    history = "<leader>ch",
    model = "<leader>cm",
    mode = "<leader>cM",
    plan = "<leader>cp",
    skill = "<leader>c/",
    zen = "<leader>cz",
    buffer_context = "<leader>cb",
    submit = {
      normal = "<CR>",
      insert = "<C-s>",
    },
    cancel = {
      normal = { "<C-c>", "q" },
      insert = { "<C-c>" },
    },
    sidebar = {
      apply = "a",
      apply_all = "A",
      next_message = "]]",
      prev_message = "[[",
      context = ",c",
      skills = ",s",
    },
  },
  debug = false,
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
