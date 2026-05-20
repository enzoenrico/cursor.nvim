-- Minimal init for headless test runs. Wires the plugin under test and
-- a sibling plenary clone (CI clones it into ./.deps/plenary.nvim) into
-- the runtimepath, then loads plenary's busted runner.

local repo = vim.fn.getcwd()
local deps = repo .. "/.deps"

vim.opt.rtp:prepend(repo)
vim.opt.rtp:prepend(deps .. "/plenary.nvim")

vim.cmd("runtime plugin/plenary.vim")
vim.cmd("runtime plugin/cursor.lua")

require("cursor").setup({
  cmd = repo .. "/tests/fake-cursor-agent.sh",
  notify = false,
})
