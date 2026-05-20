std = "luajit"
cache = true
codes = true

self = false

ignore = {
  "122", -- setting read-only field of global vim (idiomatic Neovim Lua)
  "212", -- unused argument
  "631", -- line is too long
}

read_globals = {
  "vim",
}

globals = {
  "vim",
}

include_files = {
  "lua/**/*.lua",
  "plugin/**/*.lua",
}

exclude_files = {
  "lua/cursor/_spec/**/*.lua",
}
