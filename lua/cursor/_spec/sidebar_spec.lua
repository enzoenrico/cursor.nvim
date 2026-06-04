describe("cursor.ui.render", function()
  local render = require("cursor.ui.render")

  it("extracts fenced code blocks", function()
    local text = [[
Here is code:

```lua
local x = 1
print(x)
```

Done.
]]
    local blocks = render.extract_fenced_blocks(text)
    assert.are.equal(1, #blocks)
    assert.are.equal("lua", blocks[1].lang)
    assert.are.equal(2, #blocks[1].lines)
    assert.are.equal("local x = 1", blocks[1].lines[1])
  end)

  it("append_message adds a header line with extmarks", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].modifiable = true
    local region = render.append_message(buf, "user", "hello")
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.is_true(vim.tbl_contains(lines, render.HEADER_USER))
    assert.are.equal("user", region.role)
    assert.are.equal(render.HEADER_USER, lines[region.header_line])
    local marks = vim.api.nvim_buf_get_extmarks(buf, render.ns, 0, -1, {})
    assert.is_true(#marks > 0)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

describe("cursor.ui.sidebar", function()
  local config = require("cursor.config")
  local sidebar = require("cursor.ui.sidebar")
  local agent = require("cursor.agent")

  before_each(function()
    config.reset()
    agent.__reset()
    sidebar.close()
  end)

  after_each(function()
    sidebar.close()
    agent.__reset()
  end)

  it("open() creates transcript and input buffers", function()
    config.setup({ ui = { welcome = false } })
    local s = sidebar.open()
    assert.is_not_nil(s)
    assert.are.equal("CursorChat", vim.bo[s.transcript_buf].filetype)
    assert.are.equal("markdown", vim.bo[s.input_buf].filetype)
    sidebar.close()
  end)

  it("persists only streamed assistant text in conversation", function()
    config.setup({ ui = { welcome = false } })
    local s = sidebar.open()
    s.message_regions = {}
    s.current_response = "partial "
    s.current_response = s.current_response .. "response"
    table.insert(s.conversation.messages, { role = "user", content = "hi" })
    table.insert(s.conversation.messages, {
      role = "assistant",
      content = s.current_response,
    })
    assert.are.equal("partial response", s.conversation.messages[2].content)
    sidebar.close()
  end)
end)

describe("cursor.ui.util find_project_files", function()
  local util = require("cursor.ui.util")

  it("ignores node_modules paths", function()
    assert.is_true(util.should_ignore_path("foo/node_modules/bar.lua"))
    assert.is_false(util.should_ignore_path("lua/cursor/init.lua"))
  end)
end)
