local config = require("cursor.config")
local log = require("cursor.log")

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
  log.debug("agent", "reset state")
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
  log.warn("agent", msg)
  if cfg.notify then
    vim.schedule(function()
      vim.notify("cursor.nvim: " .. msg, level)
    end)
  end
end

local function decode_line(line)
  if line == nil or line == "" then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, line)
  if not ok then
    log.warn("agent", "failed to decode JSON line", { line = line })
    return nil
  end
  if type(decoded) ~= "table" then
    log.warn("agent", "decoded value is not a table", { line = line })
    return nil
  end
  return decoded
end

-- Concatenate text blocks from cursor-agent stream-json content arrays.
-- Supports both the flat test fake (`event.text`) and live CLI shapes
-- (`event.message.content[{type,text}]`).
local function text_from_content_blocks(content)
  if type(content) ~= "table" then
    return nil
  end
  local parts = {}
  for _, block in ipairs(content) do
    if type(block) == "table" then
      if type(block.text) == "string" then
        table.insert(parts, block.text)
      elseif type(block.content) == "string" then
        table.insert(parts, block.content)
      end
    elseif type(block) == "string" then
      table.insert(parts, block)
    end
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(parts, "")
end

local function extract_assistant_text(event)
  if type(event.text) == "string" then
    return event.text
  end
  if type(event.content) == "string" then
    return event.content
  end
  if type(event.content) == "table" then
    return text_from_content_blocks(event.content)
  end
  local msg = event.message
  if type(msg) == "string" then
    return msg
  end
  if type(msg) == "table" then
    if type(msg.content) == "string" then
      return msg.content
    end
    if type(msg.content) == "table" then
      return text_from_content_blocks(msg.content)
    end
  end
  return nil
end

local function emit_chunk(text)
  if type(text) == "string" and text ~= "" and state.on_chunk then
    pcall(state.on_chunk, text)
  end
end

local function dispatch(event)
  log.debug(
    "agent",
    "dispatch event",
    { type = event.type, model = event.model, agent_id = event.agent_id }
  )
  if state.on_event then
    pcall(state.on_event, event)
  end
  local etype = event.type
  if etype == "assistant" then
    local text = extract_assistant_text(event)
    log.debug("agent", "assistant chunk", { length = text and #text or 0 })
    emit_chunk(text)
  elseif etype == "agent" or etype == "agent_created" then
    state.agent_id = event.agent_id or event.id or state.agent_id
    state.model = event.model or state.model
    log.info("agent", "agent identified", { agent_id = state.agent_id, model = state.model })
  elseif etype == "system" and event.subtype == "init" and type(event.model) == "string" then
    state.model = event.model
    log.info("agent", "model from system init", { model = state.model })
  elseif etype == "task" then
    log.debug("agent", "task event", { text = event.text })
  else
    log.debug("agent", "unhandled event type", { type = etype })
  end
end

local function consume_stdout(_, data, _)
  if not data or #data == 0 then
    return
  end
  log.debug("agent", "stdout burst", { segments = #data })
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
    if line ~= nil and line ~= "" then
      log.warn("agent", "stderr: " .. line)
      if state.on_error then
        vim.schedule(function()
          pcall(state.on_error, line)
        end)
      end
    end
  end
end

local function on_exit(_, code, _)
  log.info("agent", "process exited", { code = code })
  vim.schedule(function()
    if state.on_done then
      pcall(state.on_done, code)
    end
    reset()
  end)
end

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
  log.info("agent", "start() called", { prompt_len = opts.prompt and #opts.prompt or 0 })
  if state.job_id then
    notify(vim.log.levels.WARN, "agent already running; call stop() first")
    return nil
  end
  if type(opts.prompt) ~= "string" or opts.prompt == "" then
    notify(vim.log.levels.ERROR, "start({prompt=...}) requires a non-empty prompt")
    return nil
  end
  local cfg = config.get()
  local cmd_bin = vim.split(cfg.cmd, "%s+", { trimempty = true })[1]
  if vim.fn.executable(cmd_bin) ~= 1 then
    log.error("agent", "command not executable", { cmd = cfg.cmd, bin = cmd_bin })
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
  log.info("agent", "spawning process", { argv = argv })
  local job_id = vim.fn.jobstart(argv, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = consume_stdout,
    on_stderr = consume_stderr,
    on_exit = on_exit,
  })
  if job_id <= 0 then
    log.error("agent", "jobstart failed", { job_id = job_id })
    notify(
      vim.log.levels.ERROR,
      "failed to start agent (jobstart returned " .. tostring(job_id) .. ")"
    )
    reset()
    return nil
  end
  log.info("agent", "process started", { job_id = job_id })
  state.job_id = job_id
  return { job_id = job_id }
end

function M.stop()
  local jid = state.job_id
  if not jid then
    log.debug("agent", "stop() called but no job running")
    return false
  end
  log.info("agent", "stopping job", { job_id = jid })
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

function M.__reset()
  reset()
end

function M.__dispatch_event(event)
  dispatch(event)
end

function M.__extract_assistant_text(event)
  return extract_assistant_text(event)
end

function M.__test_callbacks(opts)
  opts = opts or {}
  state.on_chunk = opts.on_chunk
  state.on_event = opts.on_event
  state.on_done = opts.on_done
  state.on_error = opts.on_error
end

return M
