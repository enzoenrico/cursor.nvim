describe("cursor.nvim :checkhealth", function()
  local config = require("cursor.config")

  before_each(function()
    config.reset()
  end)

  it("loads without raising", function()
    local ok, mod = pcall(require, "cursor.health")
    assert.is_true(ok, tostring(mod))
    assert.is_function(mod.check)
  end)

  it("runs against the fake CLI and reports `ok`", function()
    local repo = vim.fn.getcwd()
    local fake = repo .. "/tests/fake-cursor-agent.sh"
    config.setup({ cmd = fake, notify = false })
    local fired = {}
    local original = vim.health
    vim.health = vim.tbl_extend("force", original or {}, {
      start = function(name)
        table.insert(fired, { kind = "start", arg = name })
      end,
      ok = function(msg)
        table.insert(fired, { kind = "ok", arg = msg })
      end,
      warn = function(msg)
        table.insert(fired, { kind = "warn", arg = msg })
      end,
      error = function(msg)
        table.insert(fired, { kind = "error", arg = msg })
      end,
      info = function(msg)
        table.insert(fired, { kind = "info", arg = msg })
      end,
    })
    require("cursor.health").check()
    vim.health = original
    assert.is_truthy(fired[1])
    assert.are.equal("start", fired[1].kind)
    local saw_ok = false
    for _, entry in ipairs(fired) do
      if entry.kind == "ok" and entry.arg:find(fake, 1, true) then
        saw_ok = true
      end
    end
    assert.is_true(saw_ok, "expected an ok line referencing the fake CLI path")
  end)
end)
