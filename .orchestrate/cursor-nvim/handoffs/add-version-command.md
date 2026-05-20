<!-- orchestrate handoff
task: add-version-command
branch: orch/cursor-nvim/add-version-command
agentId: bc-9f848779-6bce-4826-a932-2615edea7f5b
runId: run-3c221e3d-8055-4eb4-82b3-ac28447937b4
resultStatus: finished
finishedAt: 2026-05-20T00:40:48.050Z
-->

Branch pushed. Per orchestrator instructions, I am explicitly told not to open a PR ("Do NOT merge, rebase, or open a PR. The planner owns integration."), so I'm skipping that step.

## Status
success

## Branch
`orch/cursor-nvim/add-version-command`

## What I did
- Verified v0.1 baseline on `cursor/orchestrate-cursor-nvim-e603`: `make lint` and `make test` both green (stylua + luacheck clean over 7 files; 2 health specs + 6 init/agent specs passing) after installing toolchain (neovim 0.9.5, luacheck 1.2.0, stylua 0.20.0) and cloning plenary into `.deps/plenary.nvim`.
- `lua/cursor/version.lua`: new module exporting a single Lua string constant `"0.1.0"`.
- `lua/cursor/init.lua`: requires `cursor.version` at top of file and adds `M.version()` returning the constant (no inline imports).
- `plugin/cursor.lua`: registers `:CursorVersion`, lazy-loaded via the same `lazy("cursor", …)` pattern as `:CursorStatus`; uses `nvim_echo(..., true, {})` so the line lands in `:messages`.
- `lua/cursor/_spec/version_spec.lua`: 3 assertions — (a) `cursor.version() == require("cursor.version")` and the constant looks like semver, (b) `:CursorVersion` is registered, (c) running `:CursorVersion` writes `cursor.nvim v<version>` into `:messages` (read back via `vim.fn.execute("messages")`, which works on 0.9.x and 0.10+).
- `README.md`: added `:CursorVersion` to the lazy.nvim `cmd` list, to the usage block, and `cursor.version()` to the Lua API block.
- `doc/cursor.txt`: added `*:CursorVersion*` tag + entry in the COMMANDS section and `require("cursor").version()` in the LUA API section.

## Measurements
- `make lint`: 7 files OK → 8 files OK (0 warnings / 0 errors)
- `make test`: 8 successes → 11 successes (0 failures, 0 errors)
- `:CursorVersion` headless invocation: prints `cursor.nvim v0.1.0` to `:messages` (verified via `nvim --headless -u tests/minimal_init.lua -c CursorVersion -c messages -c qa!`)
- `lua/cursor/version.lua`: nonexistent → 3 LOC exporting a string

## Verification
unit-test-verified

The new `version_spec.lua` exercises every acceptance criterion (constant export, API exposure, command registration, `:messages` output) and passes under `PlenaryBustedDirectory`. I additionally ran the manual verification command from the plan (`nvim --headless --noplugin -u tests/minimal_init.lua -c "CursorVersion" -c "qa!"`) — it printed `cursor.nvim v0.1.0` on stdout.

## Notes, concerns, deviations, findings, thoughts, feedback
- The substrate VM only ships Neovim 0.9.5 (`apt install neovim`), even though the plugin advertises a 0.10+ floor. Tests still pass on 0.9.5 because I used `vim.fn.execute("messages")` instead of `vim.api.nvim_exec2` to read the message history; that keeps the spec portable across both versions and avoids over-tightening the runtime floor. CI in `.github/workflows/ci.yml` is out of bounds for me, but if it pins to 0.10+ this will still work (the API exists on 0.10).
- I followed the prompt literally: `lua/cursor/version.lua` is `local M = "0.1.0"; return M`. That is technically a "module that returns a string constant" rather than a table with `M.version` — i.e. `require("cursor.version")` returns `"0.1.0"`, not `{ version = "0.1.0" }`. The spec reads it dynamically, so changing the constant later won't break tests.
- The `:CursorVersion` callback uses the lazy-loader so the command remains free until first invocation, matching `:CursorStatus`. Startup cost stays at one extra `nvim_create_user_command` call.
- `notify on history` (`nvim_echo(..., true, ...)`) is what makes the line show up in `:messages`; the existing `:CursorStatus` passes `false`, which is fine for it because the planner explicitly wanted `:CursorVersion` to land in `:messages`. I left `:CursorStatus` alone (out of scope and not in my allowed-modify list except via `plugin/cursor.lua`, but its behavior wasn't part of this task).
- Toolchain provisioning was needed before lint/test could run: `apt install neovim lua5.1 luarocks`, `luarocks install luacheck`, and a release-binary install of `stylua 0.20.0`. Plus the `.deps/plenary.nvim` clone the task specified. If the planner expects future workers to skip this, an env-setup agent could prebake those into the VM image.

## Suggested follow-ups
- Consider letting `:CursorStatus` also land in `:messages` (currently it only echoes to the screen). Trivial — flip the second arg of `nvim_echo` to `true`.
- Add a `make doctor` or `make bootstrap` target that installs stylua + luacheck + clones plenary, so future workers don't each re-derive the toolchain.
- Once v0.1 ships, a `cursor.nvim` Git tag matching `lua/cursor/version.lua` would make this constant a real release marker rather than a developer placeholder; consider wiring `release-please` or a `make tag` step against the constant.
- The fake CLI test in `init_spec.lua` prints `Error detected while processing command line: cursor.nvim: start({prompt=...}) requires a non-empty prompt` during the run because the spec exercises that error path. It's noisy but harmless; could be silenced by routing the message through `vim.notify` instead of letting it escape from the callback.