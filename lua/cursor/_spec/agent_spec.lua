describe("cursor.agent stream-json parsing", function()
  local agent = require("cursor.agent")
  local config = require("cursor.config")

  before_each(function()
    config.reset()
    agent.__reset()
  end)

  it("extract_assistant_text reads flat fake-CLI events", function()
    local text = agent.__extract_assistant_text({
      type = "assistant",
      text = "echo: ping",
    })
    assert.are.equal("echo: ping", text)
  end)

  it("extract_assistant_text reads live cursor-agent message.content", function()
    local text = agent.__extract_assistant_text({
      type = "assistant",
      message = {
        role = "assistant",
        content = {
          { type = "text", text = "Hi there friend." },
        },
      },
    })
    assert.are.equal("Hi there friend.", text)
  end)

  it("extract_assistant_text concatenates multiple content blocks", function()
    local text = agent.__extract_assistant_text({
      type = "assistant",
      message = {
        content = {
          { type = "text", text = "Hello " },
          { type = "text", text = "world" },
        },
      },
    })
    assert.are.equal("Hello world", text)
  end)

  it("__dispatch_event emits on_chunk for nested assistant payloads", function()
    local chunks = {}
    agent.__test_callbacks({
      on_chunk = function(t)
        table.insert(chunks, t)
      end,
    })
    agent.__dispatch_event({
      type = "assistant",
      message = {
        content = { { type = "text", text = "Hi there friend." } },
      },
    })
    assert.are.same({ "Hi there friend." }, chunks)
  end)

  it("__dispatch_event records model from system init events", function()
    agent.__dispatch_event({
      type = "system",
      subtype = "init",
      model = "gpt-5.5-high",
    })
    assert.are.equal("gpt-5.5-high", agent.status().model)
  end)
end)
