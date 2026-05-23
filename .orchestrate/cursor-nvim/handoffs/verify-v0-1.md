<!-- orchestrate handoff
task: verify-v0-1
branch: `orch/cursor-nvim/add-version-command` (no new commits; verifier-only)
agentId: bc-762fffc7-2ad4-4ce4-8160-2213ad8d08d2
runId: run-02b4624d-a2e4-4077-88d2-1d823609a940
resultStatus: finished
finishedAt: 2026-05-20T00:45:44.148Z
-->

All checks pass cleanly. I have enough evidence for a strong verdict — every acceptance bullet is reproducible with command output. I won't commit any verifier artifacts since the run was clean and the handoff itself is the structured signal.

## Verification
unit-test-verified

## Target
`add-version-command` on branch `orch/cursor-nvim/add-version-command`

## Branch
`orch/cursor-nvim/add-version-command` (no new commits; verifier-only)

## Execution
- `sudo apt-get update && sudo apt-get install -y --no-install-recommends neovim luarocks unzip` → installed `neovim 0.9.5-6ubuntu2`, `luarocks 3.8.0`
- `sudo luarocks install luacheck` → `luacheck 1.2.0-1 is now installed in /usr/local`
- `curl -fsSL …/stylua-linux-x86_64.zip && unzip && mv stylua /usr/local/bin/` → `stylua 2.5.2` (latest; upstream used 0.20.0 but both honor `.stylua.toml`)
- `git clone --depth=1 https://github.com/nvim-lua/plenary.nvim .deps/plenary.nvim` → `Cloning into '.deps/plenary.nvim'... done`
- `nvim --version | head -3` → `NVIM v0.9.5 / Build type: Release / LuaJIT 2.1.1703358377`
- `make lint` → exit 0; stylua + luacheck `Total: 0 warnings / 0 errors in 8 files` (agent, config, health, init, ui/chat, ui/util, version, plugin/cursor)
- `make test` → exit 0; `PlenaryBustedDirectory`:
  - `version_spec.lua`: Success 3 / Failed 0 / Errors 0
  - `health_spec.lua`: Success 2 / Failed 0 / Errors 0
  - `init_spec.lua`: Success 6 / Failed 0 / Errors 0
  - Aggregate: 11 successes, 0 failures, 0 errors
- Command-registration probe (`nvim --headless ... assert(c[n], n .. ' missing') ... print('COMMANDS_OK')`) → stdout `COMMANDS_OK` (all of CursorChat, CursorAsk, CursorStop, CursorStatus, CursorVersion present)
- `nvim --headless ... -c "CursorVersion" -c "messages" -c "qa!"` → stdout `cursor.nvim v0.1.0` (twice — once from `nvim_echo`'s history write, once from `:messages` dump), confirming the line lands in `:messages`
- `nvim --headless ... -c 'CursorAsk ping' -c 'sleep 1' -c <dump-buffer> -c 'qa!'` → buffer contained `# ping`, `echo: ping`, `_(run finished, exit=0)_` (fake CLI stream-json parsed end-to-end)
- `nvim --headless ... -c 'lua require("cursor").setup({cmd = "/no/such/binary", notify=true})' -c 'CursorAsk hello' -c 'messages'` → single friendly notification `cursor.nvim: /no/such/binary not found on PATH. Install cursor-agent or set cmd in setup().` (no Lua traceback)
- `nvim --headless ... -c 'checkhealth cursor'` (buffer dump) → structured `vim.health` output: `- OK ‌/workspace/tests/fake-cursor-agent.sh is on PATH / - model: <SDK default> / - OK vim.json available`

## Findings
Per **v0.1 IMPLEMENTATION_PLAN.md** acceptance criteria:
- [x] (1) `require("cursor").setup({})` succeeds headless: tests/minimal_init.lua wires `setup({...notify=false})` and `make test` runs clean across 11 cases (met).
- [x] (2) `:CursorChat` registers and is callable; with `cursor-agent` absent it surfaces a single warning, no traceback: COMMANDS_OK probe + the cmd=`/no/such/binary` repro (above) printed exactly one friendly line via `vim.notify` (met).
- [x] (3) `:CursorAsk "ping"` runs to a clean exit when `cursor-agent` is mocked; streamed text lands in a buffer: manual repro showed `echo: ping` and `_(run finished, exit=0)_` in the scratch buffer; `init_spec.lua "runs against the fake CLI and streams chunks"` passes (met).
- [x] (4) `:checkhealth cursor` produces structured `vim.health` output: dumped buffer shows `- OK` lines from `vim.health.ok`; `health_spec.lua` asserts an `ok` entry referencing the fake CLI path and passes (met).
- [x] (5) `doc/cursor.txt` is real `:help` content: contains `*cursor.txt*` / `*cursor.nvim*` tags, INTRODUCTION/QUICK START/COMMANDS/HEALTH/LUA API/KEYMAPS/LICENSE sections (met).
- [x] (6) `README.md` documents lazy.nvim, packer.nvim, and vim-plug + `setup()` shape: all three installer snippets present (lines 17–47) plus a `setup({...})` block (lines 71–83) (met).
- [x] (7) stylua + luacheck pass: `make lint` exits 0, 8 files OK, 0 warnings (met).
- [x] (8) CI runs stylua + luacheck + busted/plenary on push and PR: `.github/workflows/ci.yml` defines `lint` job (`stylua-action` + `luarocks install luacheck` + `luacheck`) and `test` job (Neovim stable + plenary clone + `PlenaryBustedDirectory`) triggered `on: push (main) / pull_request` (met).

Per **add-version-command** acceptance criteria:
- [x] `lua/cursor/version.lua` exists and exports a single string constant: file contents are literally `local M = "0.1.0"\n\nreturn M` (met).
- [x] `:CursorVersion` is registered and prints `cursor.nvim v<version>` to `:messages`: manual `CursorVersion ; messages` repro printed `cursor.nvim v0.1.0`; uses `vim.api.nvim_echo({...}, true, {})` in `plugin/cursor.lua` (the `true` flag adds to history → `:messages`) (met).
- [x] `require('cursor').version()` returns the same string the constant exports: `lua/cursor/init.lua` does `local version = require("cursor.version") ... function M.version() return version end`; `version_spec.lua` first `it` block asserts `cursor.version() == require("cursor.version")` and passes (met).
- [x] `lua/cursor/_spec/version_spec.lua` has ≥2 assertions and passes under PlenaryBustedDirectory: 3 `it` blocks with 7 `assert.*` calls total, all `Success` (met).
- [x] stylua + luacheck both pass: see lint output above (met).
- [x] README.md and doc/cursor.txt mention `:CursorVersion` in their command tables: README line 21 (`cmd = {...,"CursorVersion"}`), line 56 (usage table), line 94 (`cursor.version()` API); doc/cursor.txt lines 47–49 (tag + COMMANDS entry), line 69 (LUA API entry) (met).

Verifier-specific:
- [x] Per-criterion pass/fail with execution evidence: above, with real command output.
- [x] Verification line is one of the allowed values: `unit-test-verified`.

Other findings:
- (low) Substrate ships Neovim 0.9.5 only (`apt install neovim`), but the plugin advertises 0.10+. Spec works on 0.9.5 because `version_spec.lua` reads `:messages` via `vim.fn.execute("messages")` (portable across 0.9 and 0.10). CI (out of bounds) pins `neovim: stable` via `rhysd/action-setup-vim` so the 0.10+ floor still gets exercised upstream. No action needed.
- (low) `nvim_echo(..., true, {})` in `:CursorVersion` writes to history; this is exactly what the planner wanted ("prints to `:messages`"). The existing `:CursorStatus` still uses `false`, so it echoes to the screen but not to `:messages`. Out of bounds for this task; flagging only because upstream's notes mentioned it.
- (low) `init_spec.lua` deliberately exercises the empty-prompt error path, which writes the line `cursor.nvim: start({prompt=...}) requires a non-empty prompt` to test output via `vim.notify` → headless error sink. Noisy but harmless; all assertions still pass. Upstream already noted this.

## Notes & suggestions
- Stylua versions diverge (substrate now has 2.5.2; upstream worker used 0.20.0). Both accept the repo's `.stylua.toml` and both produce "OK" on every file, so this is purely informational — the CI workflow pins `version: latest` which will track 2.x.
- Toolchain provisioning (neovim, luarocks, luacheck, stylua, plenary clone) is the slow part of verification. Confirming upstream's suggestion: a `make doctor` target or a Cloud-Agent env-setup pass that prebakes these would let future verifiers skip ~30s of `apt-get`/`luarocks`/`unzip` work.
- The handoff's "verdict" maps cleanly to reality: the v0.1 baseline is genuinely shippable, and the `:CursorVersion` increment is a tight, idiomatic addition that doesn't perturb adjacent modules (agent/config/health/ui/CI all untouched, as the worker plan required). No follow-ups required for this task.