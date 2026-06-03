local config = require("cursor.config")

local M = {}

local function vim_health()
  if vim.health and type(vim.health.start) == "function" then
    return vim.health
  end
  -- Pre-0.10 shims: report{} → ok/warn/error functions live on the
  -- legacy table. The plugin floor is 0.10, but the shim keeps tests
  -- working under older runners.
  local h = require("vim.health")
  return {
    start = h.report_start or h.start,
    ok = h.report_ok or h.ok,
    warn = h.report_warn or h.warn,
    error = h.report_error or h.error,
    info = h.report_info or h.info,
  }
end

function M.check()
  local h = vim_health()
  h.start("cursor.nvim")

  local cfg = config.get()
  local transport_cmd = cfg.transport == "sdk" and cfg.sdk and cfg.sdk.cmd or cfg.cmd
  local cmd_parts = vim.split(transport_cmd or "", "%s+", { trimempty = true })
  local exe = cmd_parts[1] or ""

  if vim.fn.executable(exe) == 1 then
    h.ok(string.format("`%s` is on PATH", exe))
    if vim.system then
      local out = vim.system({ exe, "--version" }, { text = true }):wait()
      if out and out.code == 0 then
        local version = (out.stdout or ""):gsub("%s+$", "")
        if version ~= "" then
          h.info("version: " .. version)
        end
      end
    end
  else
    h.error(
      string.format(
        "`%s` not found on PATH; install cursor-agent, configure sdk.cmd, or set cmd in setup()",
        exe
      )
    )
  end

  h.info("transport: " .. tostring(cfg.transport or "cli"))
  if cfg.mode then
    h.info("mode: " .. tostring(cfg.mode))
  end

  if cfg.model then
    h.info("configured model: " .. tostring(cfg.model))
  else
    h.info("model: <SDK default>")
  end

  if vim.json and type(vim.json.decode) == "function" then
    h.ok("vim.json available")
  else
    h.error("vim.json unavailable; cursor.nvim requires Neovim 0.10+")
  end
end

return M
