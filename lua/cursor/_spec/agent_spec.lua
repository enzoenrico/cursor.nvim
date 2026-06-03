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

  it("__dispatch_event records model ids from SDK model objects", function()
    agent.__dispatch_event({
      type = "system",
      subtype = "init",
      model = { id = "composer-2.5", params = { { id = "thinking", value = "high" } } },
    })
    assert.are.equal("composer-2.5", agent.status().model)
  end)

  it("__build_argv includes Cursor CLI capability flags", function()
    local argv = agent.__build_argv({
      cmd = "cursor-agent",
      transport = "cli",
      output_format = "stream-json",
      stream_partial_output = true,
      model = "composer-2.5",
      mode = "plan",
      force = true,
      trust = true,
      approve_mcps = true,
      sandbox = "enabled",
      workspace = "/repo",
      headers = { "X-Test: yes" },
      plugin_dirs = { "/plugins/skills" },
      extra_args = { "--worktree" },
    }, "hello")
    assert.are.same({
      "cursor-agent",
      "--print",
      "--output-format=stream-json",
      "--stream-partial-output",
      "--model",
      "composer-2.5",
      "--plan",
      "--force",
      "--trust",
      "--approve-mcps",
      "--sandbox",
      "enabled",
      "--workspace",
      "/repo",
      "--header",
      "X-Test: yes",
      "--plugin-dir",
      "/plugins/skills",
      "--worktree",
      "-p",
      "hello",
    }, argv)
  end)

  it("__build_argv includes SDK bridge options", function()
    local argv = agent.__build_argv({
      cmd = "cursor-agent",
      transport = "sdk",
      model = "composer-2.5",
      model_params = { { id = "thinking", value = "high" } },
      mode = "plan",
      workspace = "/repo",
      force = true,
      sdk = {
        cmd = "node scripts/cursor-sdk-bridge.mjs",
        runtime = "local",
        api_key_env = "CURSOR_API_KEY",
        extra_args = { "--verbose" },
      },
    }, "hello")
    assert.are.same({
      "node",
      "scripts/cursor-sdk-bridge.mjs",
      "--output-format=stream-json",
      "--runtime",
      "local",
      "--api-key-env",
      "CURSOR_API_KEY",
      "--workspace",
      "/repo",
      "--model",
      "composer-2.5",
      "--model-param",
      "thinking=high",
      "--mode",
      "plan",
      "--force",
      "--verbose",
      "-p",
      "hello",
    }, argv)
  end)

  it("__parse_models_output reads SDK JSON model lists", function()
    local models = agent.__parse_models_output(
      vim.json.encode({ { id = "composer-2.5", displayName = "Composer" }, { id = "auto" } })
    )
    assert.are.same({ "composer-2.5 — Composer", "auto" }, models)
  end)
end)
