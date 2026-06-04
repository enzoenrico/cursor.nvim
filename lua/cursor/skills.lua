local config = require("cursor.config")

local M = {}

local SKILL_FILE = "SKILL.md"

local CONTAINER_DIRS = {
  [".cursor"] = true,
  [".agents"] = true,
  [".claude"] = true,
  [".codex"] = true,
}

local PROJECT_ROOT_SUFFIXES = {
  ".cursor/skills",
  ".agents/skills",
  ".claude/skills",
  ".codex/skills",
}

local BUILTIN_SLASH = {
  clear = true,
  new = true,
  compact = true,
  skills = true,
  skill = true,
}

local cache = {
  key = nil,
  by_name = {},
  list = {},
}

local function expand(path)
  if path:sub(1, 1) == "~" then
    return vim.fn.expand(path)
  end
  return path
end

function M.is_builtin_slash(cmd)
  return BUILTIN_SLASH[cmd] == true
end

local function parse_frontmatter(lines)
  if #lines == 0 or lines[1] ~= "---" then
    return {}, table.concat(lines, "\n")
  end
  local end_idx = nil
  for i = 2, #lines do
    if lines[i] == "---" then
      end_idx = i
      break
    end
  end
  if not end_idx then
    return {}, table.concat(lines, "\n")
  end
  local meta = {}
  for i = 2, end_idx - 1 do
    local key, val = lines[i]:match("^([%w%-]+)%s*:%s*(.+)$")
    if key and val then
      key = key:gsub("-", "_")
      val = vim.trim(val)
      if val:sub(1, 1) == "[" and val:sub(-1) == "]" then
        local items = {}
        for item in val:sub(2, -2):gmatch("[^,]+") do
          item = vim.trim(item):gsub("^[\"']", ""):gsub("[\"']$", "")
          if item ~= "" then
            table.insert(items, item)
          end
        end
        meta[key] = items
      else
        meta[key] = val
      end
    end
  end
  local body_lines = {}
  for i = end_idx + 1, #lines do
    table.insert(body_lines, lines[i])
  end
  local body = table.concat(body_lines, "\n")
  return meta, body
end

local function scope_root_for(skill_path)
  local norm = vim.fs.normalize(skill_path)
  local parts = vim.split(norm, "/")
  for i = #parts, 2, -1 do
    if parts[i] == "skills" and CONTAINER_DIRS[parts[i - 1]] then
      if i >= 3 then
        return table.concat(parts, "/", 1, i - 2)
      end
      return nil
    end
  end
  return nil
end

local function skill_name_from_path(skill_path, meta)
  if type(meta.name) == "string" and meta.name ~= "" then
    return meta.name
  end
  local parent = vim.fs.dirname(skill_path)
  return vim.fs.basename(parent)
end

function M.parse_skill_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines or #lines == 0 then
    return nil
  end
  local meta, body = parse_frontmatter(lines)
  local name = skill_name_from_path(path, meta)
  local paths = meta.paths or meta.globs
  if type(paths) == "string" then
    local items = {}
    for item in paths:gmatch("[^,]+") do
      item = vim.trim(item)
      if item ~= "" then
        table.insert(items, item)
      end
    end
    paths = items
  end
  return {
    name = name,
    description = meta.description or "",
    path = path,
    skill_dir = vim.fs.dirname(path),
    body = body,
    paths = paths,
    scope_root = scope_root_for(path),
    disable_auto = meta.disable_model_invocation == true or meta.disable_model_invocation == "true",
  }
end

local function collect_skill_files(roots)
  local files = {}
  for _, root in ipairs(roots) do
    root = expand(root)
    if vim.fn.isdirectory(root) == 1 then
      local found = vim.fs.find(SKILL_FILE, {
        path = root,
        type = "file",
        limit = 200,
      })
      if found then
        vim.list_extend(files, found)
      end
    end
  end
  return files
end

local function project_skill_roots(cwd)
  local roots = {}
  local cfg = config.get()
  local extra = cfg.skills and cfg.skills.paths
  if type(extra) == "table" then
    for _, p in ipairs(extra) do
      table.insert(roots, expand(p))
    end
  end
  for _, suffix in ipairs(PROJECT_ROOT_SUFFIXES) do
    table.insert(roots, cwd .. "/" .. suffix)
  end
  local nested = vim.fs.find(function(name, path)
    if name ~= "skills" then
      return false
    end
    local parent = vim.fs.dirname(path)
    local base = vim.fs.basename(parent)
    return CONTAINER_DIRS[base] == true
  end, {
    path = cwd,
    type = "directory",
    limit = 50,
  })
  if nested then
    for _, dir in ipairs(nested) do
      table.insert(roots, dir)
    end
  end
  return roots
end

local function global_skill_roots()
  local home = vim.fn.expand("~")
  local roots = {}
  for _, container in ipairs({ ".cursor", ".agents", ".claude", ".codex" }) do
    table.insert(roots, home .. "/" .. container .. "/skills")
  end
  return roots
end

local function cache_key(cwd)
  return cwd .. ":" .. tostring(math.floor(os.time() / 30))
end

function M.discover(opts)
  opts = opts or {}
  local cwd = opts.cwd or vim.fn.getcwd()
  local key = cache_key(cwd)
  if not opts.reload and cache.key == key then
    return cache.list, cache.by_name
  end

  local roots = {}
  vim.list_extend(roots, project_skill_roots(cwd))
  vim.list_extend(roots, global_skill_roots())

  local seen_path = {}
  local list = {}
  local by_name = {}

  for _, file in ipairs(collect_skill_files(roots)) do
    file = vim.fs.normalize(file)
    if not seen_path[file] then
      seen_path[file] = true
      local skill = M.parse_skill_file(file)
      if skill and skill.name and skill.name ~= "" then
        if not by_name[skill.name] then
          by_name[skill.name] = skill
          table.insert(list, skill)
        end
      end
    end
  end

  table.sort(list, function(a, b)
    return a.name < b.name
  end)

  cache.key = key
  cache.list = list
  cache.by_name = by_name
  return list, by_name
end

function M.invalidate_cache()
  cache.key = nil
  cache.list = {}
  cache.by_name = {}
end

function M.get(name, opts)
  local _, by_name = M.discover(opts)
  return by_name[name]
end

local function buffer_relative_path(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return nil
  end
  local cwd = vim.fn.getcwd()
  if vim.startswith(name, cwd) then
    local rel = name:sub(#cwd + 1)
    if rel:sub(1, 1) == "/" then
      rel = rel:sub(2)
    end
    return rel
  end
  return name
end

function M.matches_paths(rel_path, patterns)
  if not patterns or #patterns == 0 then
    return true
  end
  if not rel_path or rel_path == "" then
    return false
  end
  for _, pat in ipairs(patterns) do
    local ok = vim.fn.glob(pat, false, true)
    if type(ok) == "table" then
      for _, match in ipairs(ok) do
        if rel_path == match or rel_path:match(match) then
          return true
        end
      end
    end
    if vim.fn.fnamematch(rel_path, pat) == 1 then
      return true
    end
  end
  return false
end

function M.applies_to_buffer(skill, buf)
  buf = buf or 0
  local rel = buffer_relative_path(buf)
  if skill.scope_root then
    local cwd = vim.fn.getcwd()
    local scope = skill.scope_root
    if not vim.startswith(scope, cwd) then
      scope = cwd .. "/" .. scope
    end
    local norm_buf = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
    local norm_scope = vim.fs.normalize(scope)
    if rel == nil or rel == "" then
      return false
    end
    if not vim.startswith(norm_buf, norm_scope) then
      return false
    end
  end
  if skill.paths and #skill.paths > 0 then
    return M.matches_paths(rel, skill.paths)
  end
  return true
end

function M.filter_for_buffer(buf, opts)
  local list, _ = M.discover(opts)
  local out = {}
  for _, skill in ipairs(list) do
    if M.applies_to_buffer(skill, buf) then
      table.insert(out, skill)
    end
  end
  return out
end

function M.format_for_prompt(skill)
  local header = string.format("[Skill: %s]", skill.name)
  if skill.description and skill.description ~= "" then
    header = header .. "\n" .. skill.description
  end
  local body = vim.trim(skill.body or "")
  if body == "" then
    return header
  end
  return header .. "\n\n" .. body
end

function M.format_many_for_prompt(skills)
  local parts = {}
  for _, skill in ipairs(skills) do
    table.insert(parts, M.format_for_prompt(skill))
  end
  return table.concat(parts, "\n\n")
end

return M
