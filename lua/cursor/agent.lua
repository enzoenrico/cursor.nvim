-- Subprocess wrapper around the `cursor-agent` CLI. The CLI is the
-- supported shell-out boundary for the Cursor SDK and emits one JSON
-- object per line when invoked with `--output-format=stream-json`.
--
-- The wrapper exposes a small surface:
--   start(opts) -> handle  -- spawns a run, streams events back via callbacks
--   stop()                 -- cancels the active run
--   is_running()           -- bool
--   status()               -- { running, agent_id, model }

local config = require("cursor.config")

local M = {}

local state = {
  job_id = nil,
  agent_id = nil,
  model = nil,
  buffer = "",
  on_chunk = nil,
  on_event = nil,
  on_done = nil,
  on_error = nil,
}

local function reset()
  state.job_id = nil
  state.agent_id = nil
  state.buffer = ""
  state.on_chunk = nil
  state.on_event = nil
  state.on_done = nil
  state.on_error = nil
end

local function notify(level, msg)
  local cfg = config.get()
  if cfg.notify then
    vim.schedule(function()
      vim.notify("cursor.nvim: " .. msg, level)
    end)
  end
end

-- Decode a single JSON-line record. Returns the decoded table or nil
-- when the line is empty or malformed; callers must not assume a record
-- per line because the CLI may emit blank padding between events.
local function decode_line(line)
  if line == nil or line == "" then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, line)
  if not ok then
    return nil
  end
  if type(decoded) ~= "table" then
    return nil
  end
  return decoded
end

local function dispatch(event)
  if state.on_event then
    pcall(state.on_event, event)
  end
  local etype = event.type
  if etype == "assistant" then
    local text = event.text or event.content or event.message
    if type(text) == "string" and state.on_chunk then
      pcall(state.on_chunk, text)
    end
  elseif etype == "agent" or etype == "agent_created" then
    state.agent_id = event.agent_id or event.id or state.agent_id
    state.model = event.model or state.model
  end
end

-- jobstart already splits stdout on `\n`. The contract per `:help
-- channel-lines`: the first element is appended to the previous tail,
-- middle elements are complete lines, and the final element is the new
-- tail (empty when the burst ended on a newline). `state.buffer` carries
-- the tail across bursts.
local function consume_stdout(_, data, _)
  if not data or #data == 0 then
    return
  end
  state.buffer = state.buffer .. data[1]
  for i = 2, #data do
    local line = state.buffer
    state.buffer = data[i]
    local event = decode_line(line)
    if event then
      vim.schedule(function()
        dispatch(event)
      end)
    end
  end
end

local function consume_stderr(_, data, _)
  if not data then
    return
  end
  for _, line in ipairs(data) do
    if line ~= nil and line ~= "" and state.on_error then
      vim.schedule(function()
        pcall(state.on_error, line)
      end)
    end
  end
end

local function on_exit(_, code, _)
  vim.schedule(function()
    if state.on_done then
      pcall(state.on_done, code)
    end
    reset()
  end)
end

-- Build the argv we pass to `vim.fn.jobstart`. Splitting cmd via
-- `vim.split` lets users override with `cmd = "node bin/agent.js"`.
local function build_argv(cfg, prompt)
  local argv = {}
  for _, part in ipairs(vim.split(cfg.cmd, "%s+", { trimempty = true })) do
    table.insert(argv, part)
  end
  table.insert(argv, "--print")
  table.insert(argv, "--output-format=stream-json")
  if cfg.model then
    table.insert(argv, "--model")
    table.insert(argv, cfg.model)
  end
  table.insert(argv, "-p")
  table.insert(argv, prompt)
  return argv
end

function M.start(opts)
  opts = opts or {}
  if state.job_id then
    notify(vim.log.levels.WARN, "agent already running; call stop() first")
    return nil
  end
  if type(opts.prompt) ~= "string" or opts.prompt == "" then
    notify(vim.log.levels.ERROR, "start({prompt=...}) requires a non-empty prompt")
    return nil
  end
  local cfg = config.get()
  if vim.fn.executable(vim.split(cfg.cmd, "%s+", { trimempty = true })[1]) ~= 1 then
    notify(
      vim.log.levels.ERROR,
      cfg.cmd .. " not found on PATH. Install cursor-agent or set cmd in setup()."
    )
    if opts.on_error then
      pcall(opts.on_error, "cursor-agent not on PATH")
    end
    return nil
  end
  state.on_chunk = opts.on_chunk
  state.on_event = opts.on_event
  state.on_done = opts.on_done
  state.on_error = opts.on_error
  state.buffer = ""
  state.model = opts.model or cfg.model

  local argv = build_argv(cfg, opts.prompt)
  local job_id = vim.fn.jobstart(argv, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = consume_stdout,
    on_stderr = consume_stderr,
    on_exit = on_exit,
  })
  if job_id <= 0 then
    notify(
      vim.log.levels.ERROR,
      "failed to start agent (jobstart returned " .. tostring(job_id) .. ")"
    )
    reset()
    return nil
  end
  state.job_id = job_id
  return { job_id = job_id }
end

function M.stop()
  local jid = state.job_id
  if not jid then
    return false
  end
  pcall(vim.fn.jobstop, jid)
  return true
end

function M.is_running()
  return state.job_id ~= nil
end

function M.status()
  return {
    running = state.job_id ~= nil,
    agent_id = state.agent_id,
    model = state.model,
  }
end

-- Test seam: lets specs reset internal state without restarting Neovim.
-- Not exposed in the public API.
function M.__reset()
  reset()
end

return M
