local M = {}

M.frames = {
  generating = { "·", "✢", "✳", "∗", "✻", "✽" },
  thinking = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  done = { "✓" },
  failed = { "✗" },
}

M.hl = {
  generating = "CursorSpinnerGenerating",
  thinking = "CursorSpinnerThinking",
  done = "CursorSpinnerDone",
  failed = "CursorSpinnerFailed",
}

local state = {
  timer = nil,
  frame_idx = 0,
  kind = nil,
  callback = nil,
}

local function define_highlights()
  local hi = vim.api.nvim_set_hl
  hi(0, "CursorSpinnerGenerating", { fg = "#ab9df2", bold = true, default = true })
  hi(0, "CursorSpinnerThinking", { fg = "#c678dd", bold = true, default = true })
  hi(0, "CursorSpinnerDone", { fg = "#98c379", bold = true, default = true })
  hi(0, "CursorSpinnerFailed", { fg = "#e06c75", bold = true, default = true })
end

define_highlights()

function M.start(kind, callback)
  M.stop()
  state.kind = kind or "generating"
  state.frame_idx = 0
  state.callback = callback
  local frames = M.frames[state.kind] or M.frames.generating
  state.timer = vim.uv.new_timer()
  state.timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      if not state.timer then
        return
      end
      state.frame_idx = (state.frame_idx % #frames) + 1
      local frame = frames[state.frame_idx]
      if state.callback then
        pcall(state.callback, frame, M.hl[state.kind] or "Normal")
      end
    end)
  )
end

function M.stop()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  state.kind = nil
  state.frame_idx = 0
  state.callback = nil
end

function M.is_running()
  return state.timer ~= nil
end

function M.current_kind()
  return state.kind
end

function M.finish(success, callback)
  M.stop()
  local kind = success and "done" or "failed"
  local frame = M.frames[kind][1]
  if callback then
    pcall(callback, frame, M.hl[kind])
  end
end

return M
