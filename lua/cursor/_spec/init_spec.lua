describe("cursor.nvim public API", function()
  local cursor = require("cursor")
  local config = require("cursor.config")
  local agent = require("cursor.agent")

  before_each(function()
    config.reset()
    agent.__reset()
  end)

  it("setup() merges defaults with user options", function()
    cursor.setup({
      model = "test-model",
      ui = { layout = "tab" },
    })
    local cfg = config.get()
    assert.are.equal("test-model", cfg.model)
    assert.are.equal("tab", cfg.ui.layout)
    -- Defaults still present
    assert.are.equal("cursor-agent", cfg.cmd)
    assert.are.equal(false, cfg.keymaps)
  end)

  it("registers user commands", function()
    local commands = vim.api.nvim_get_commands({})
    assert.is_truthy(commands.CursorChat)
    assert.is_truthy(commands.CursorAsk)
    assert.is_truthy(commands.CursorStop)
    assert.is_truthy(commands.CursorStatus)
    assert.is_truthy(commands.CursorMode)
    assert.is_truthy(commands.CursorPlan)
    assert.is_truthy(commands.CursorSkill)
  end)

  it("status() returns a stable shape", function()
    local s = cursor.status()
    assert.are.equal(false, s.running)
    assert.is_nil(s.agent_id)
  end)

  it("ask() with empty prompt does not crash", function()
    cursor.ask("")
    cursor.ask(nil)
    assert.are.equal(false, cursor.status().running)
  end)
end)

describe("cursor.agent stream parser", function()
  local agent = require("cursor.agent")
  local config = require("cursor.config")

  before_each(function()
    config.reset()
    agent.__reset()
  end)

  it("rejects start() with no prompt", function()
    local h = agent.start({ prompt = "" })
    assert.is_nil(h)
    assert.are.equal(false, agent.is_running())
  end)

  it("runs against the fake CLI and streams chunks", function()
    local repo = vim.fn.getcwd()
    config.setup({
      cmd = repo .. "/tests/fake-cursor-agent.sh",
      notify = false,
    })
    local chunks = {}
    local done_code
    local handle = agent.start({
      prompt = "ping",
      on_chunk = function(t)
        table.insert(chunks, t)
      end,
      on_done = function(code)
        done_code = code
      end,
    })
    assert.is_truthy(handle, "start() should return a handle when CLI is on PATH")
    -- Wait up to ~2s for the fake CLI to finish.
    vim.wait(2000, function()
      return done_code ~= nil
    end, 25)
    assert.are.equal(0, done_code)
    assert.is_true(#chunks >= 1, "should have received at least one chunk")
    local joined = table.concat(chunks, "")
    assert.is_truthy(joined:find("echo: ping", 1, true), "chunk should echo the prompt")
  end)
end)
