local config = require("cursor.config")

local M = {}

local function history_dir()
  local cfg = config.get()
  if cfg.history and cfg.history.path then
    return cfg.history.path
  end
  return vim.fn.stdpath("data") .. "/cursor_nvim/history"
end

local function ensure_dir()
  local dir = history_dir()
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  return dir
end

local function conversation_path(id)
  return ensure_dir() .. "/" .. id .. ".json"
end

function M.save(id, conversation)
  local path = conversation_path(id)
  local data = vim.json.encode(conversation)
  local f = io.open(path, "w")
  if f then
    f:write(data)
    f:close()
  end
end

function M.load(id)
  local path = conversation_path(id)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.json.decode, data)
  if not ok then
    return nil
  end
  return decoded
end

function M.list()
  local dir = history_dir()
  if vim.fn.isdirectory(dir) == 0 then
    return {}
  end
  local files = vim.fn.glob(dir .. "/*.json", false, true)
  local result = {}
  for _, file in ipairs(files) do
    local name = vim.fn.fnamemodify(file, ":t:r")
    local stat = vim.uv.fs_stat(file)
    table.insert(result, {
      id = name,
      mtime = stat and stat.mtime.sec or 0,
      path = file,
    })
  end
  table.sort(result, function(a, b)
    return a.mtime > b.mtime
  end)
  return result
end

function M.delete(id)
  local path = conversation_path(id)
  pcall(os.remove, path)
end

function M.clear_all()
  local entries = M.list()
  for _, entry in ipairs(entries) do
    pcall(os.remove, entry.path)
  end
end

function M.generate_id()
  return os.date("%Y%m%d_%H%M%S") .. "_" .. string.format("%04x", math.random(0, 0xFFFF))
end

function M.compact(conversation)
  if not conversation or not conversation.messages then
    return conversation
  end
  local compacted = vim.deepcopy(conversation)
  local messages = compacted.messages
  if #messages <= 4 then
    return compacted
  end
  local keep = {}
  for i = 1, math.min(2, #messages) do
    table.insert(keep, messages[i])
  end
  table.insert(keep, {
    role = "system",
    content = string.format("[%d earlier messages compacted]", #messages - 4),
    timestamp = os.time(),
  })
  for i = #messages - 1, #messages do
    if i > 0 then
      table.insert(keep, messages[i])
    end
  end
  compacted.messages = keep
  return compacted
end

return M
