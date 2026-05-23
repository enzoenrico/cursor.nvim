local sidebar = require("cursor.ui.sidebar")

local M = {}

function M.open(opts)
  return sidebar.open(opts)
end

function M.close()
  sidebar.close()
end

function M.__session()
  return sidebar.get_sidebar()
end

return M
