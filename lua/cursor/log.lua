local M = {}

local log_file = nil
local log_path = nil

local function get_log_path()
  if log_path then
    return log_path
  end
  log_path = vim.fn.stdpath("log") .. "/cursor_nvim.log"
  local dir = vim.fn.fnamemodify(log_path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  return log_path
end

local function ensure_file()
  if log_file then
    return log_file
  end
  local path = get_log_path()
  log_file = io.open(path, "a")
  return log_file
end

local function is_enabled()
  local ok, config = pcall(require, "cursor.config")
  if not ok then
    return false
  end
  local cfg = config.get()
  return cfg.debug == true
end

local function timestamp()
  return os.date("%H:%M:%S") .. string.format(".%03d", (vim.uv.hrtime() / 1e6) % 1000)
end

function M.log(level, module, msg, data)
  if not is_enabled() then
    return
  end
  local f = ensure_file()
  if not f then
    return
  end
  local line = string.format("[%s] [%s] [%s] %s", timestamp(), level, module, msg)
  if data ~= nil then
    local ok, encoded = pcall(vim.json.encode, data)
    if ok then
      line = line .. " " .. encoded
    else
      line = line .. " " .. tostring(data)
    end
  end
  f:write(line .. "\n")
  f:flush()
end

function M.debug(module, msg, data)
  M.log("DEBUG", module, msg, data)
end

function M.info(module, msg, data)
  M.log("INFO", module, msg, data)
end

function M.warn(module, msg, data)
  M.log("WARN", module, msg, data)
end

function M.error(module, msg, data)
  M.log("ERROR", module, msg, data)
end

function M.get_path()
  return get_log_path()
end

function M.clear()
  if log_file then
    log_file:close()
    log_file = nil
  end
  local path = get_log_path()
  local f = io.open(path, "w")
  if f then
    f:write("")
    f:close()
  end
end

function M.close()
  if log_file then
    log_file:close()
    log_file = nil
  end
end

function M.tail(n)
  n = n or 50
  local path = get_log_path()
  if vim.fn.filereadable(path) == 0 then
    return {}
  end
  local lines = vim.fn.readfile(path)
  if #lines <= n then
    return lines
  end
  local result = {}
  for i = #lines - n + 1, #lines do
    table.insert(result, lines[i])
  end
  return result
end

return M
