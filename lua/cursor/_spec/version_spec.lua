describe("cursor.nvim :CursorVersion", function()
  local cursor = require("cursor")
  local version = require("cursor.version")

  it("exposes the version constant via the public API", function()
    assert.are.equal("string", type(version))
    assert.is_truthy(version:match("^%d+%.%d+%.%d+"))
    assert.are.equal(version, cursor.version())
  end)

  it("registers the :CursorVersion ex command", function()
    local commands = vim.api.nvim_get_commands({})
    assert.is_truthy(commands.CursorVersion)
  end)

  it("prints `cursor.nvim v<version>` when invoked", function()
    vim.cmd("messages clear")
    vim.cmd("CursorVersion")
    local out = vim.fn.execute("messages")
    assert.is_truthy(
      out:find("cursor.nvim v" .. version, 1, true),
      "expected `cursor.nvim v" .. version .. "` in :messages, got: " .. out
    )
  end)
end)
