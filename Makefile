.PHONY: lint stylua luacheck test test-headless test-ui clean

STYLUA ?= stylua
LUACHECK ?= luacheck
NVIM ?= nvim

lint: stylua luacheck

stylua:
	$(STYLUA) --check lua/ plugin/

stylua-fix:
	$(STYLUA) lua/ plugin/

luacheck:
	$(LUACHECK) lua/ plugin/

test: test-headless

test-headless:
	$(NVIM) --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory lua/cursor/_spec/ {minimal_init = 'tests/minimal_init.lua'}"

test-ui:
	chmod +x tests/harness/sidebar-smoke.sh
	./tests/harness/sidebar-smoke.sh

clean:
	rm -rf .luacheckcache
