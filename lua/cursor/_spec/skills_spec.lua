describe("cursor.skills", function()
  local skills = require("cursor.skills")
  local config = require("cursor.config")

  local fixture_root

  before_each(function()
    config.reset()
    fixture_root = vim.fn.getcwd() .. "/tests/fixtures/skill-project"
    skills.invalidate_cache()
  end)

  it("parses SKILL.md frontmatter", function()
    local path = fixture_root .. "/.cursor/skills/demo-skill/SKILL.md"
    local skill = skills.parse_skill_file(path)
    assert.is_not_nil(skill)
    assert.are.equal("demo-skill", skill.name)
    assert.are.equal("A demo skill for tests.", skill.description)
    assert.matches("Step one", skill.body)
  end)

  it("discovers project skills", function()
    config.setup({
      skills = {
        paths = { fixture_root .. "/.cursor/skills" },
      },
    })
    local list, by_name = skills.discover({ cwd = fixture_root, reload = true })
    assert.is_true(#list >= 1)
    assert.is_not_nil(by_name["demo-skill"])
  end)

  it("treats built-in slash names as reserved", function()
    assert.is_true(skills.is_builtin_slash("clear"))
    assert.is_false(skills.is_builtin_slash("demo-skill"))
  end)
end)
