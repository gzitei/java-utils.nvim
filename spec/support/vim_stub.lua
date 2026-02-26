-- spec/support/vim_stub.lua
-- Minimal vim-API stub for running java-utils tests outside Neovim.
-- Only the symbols actually used by the tested modules are provided.

-- ── Stub 'dap': required at module load time by test_runner.lua ───────────────
package.preload["dap"] = function()
  return {
    run              = function() end,
    listeners        = setmetatable({}, { __index = function() return {} end }),
    set_breakpoint   = function() end,
    continue         = function() end,
  }
end

-- ── Stub 'notify': required at runtime by test_runner.lua ────────────────────
package.preload["notify"] = function()
  return {
    notify = function(_msg, _level, _opts) return {} end,
    dismiss = function(_id) end,
  }
end

-- ─────────────────────────────────────────────────────────────────────────────

local vim_stub = {}

-- ── vim.tbl_deep_extend ───────────────────────────────────────────────────────
vim_stub.tbl_deep_extend = function(mode, ...)
  local result = {}
  local function is_array(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n == #t
  end
  local function deep_extend(t)
    for k, v in pairs(t) do
      if type(v) == "table" and type(result[k]) == "table"
          and not is_array(v) and not is_array(result[k]) then
        -- both are dicts: recurse
        local sub = {}
        for kk, vv in pairs(result[k]) do sub[kk] = vv end
        for kk, vv in pairs(v) do
          if type(vv) == "table" and type(sub[kk]) == "table"
              and not is_array(vv) and not is_array(sub[kk]) then
            local subsub = {}
            for kkk, vvv in pairs(sub[kk]) do subsub[kkk] = vvv end
            for kkk, vvv in pairs(vv) do subsub[kkk] = vvv end
            sub[kk] = subsub
          else
            sub[kk] = vv  -- array or scalar: replace
          end
        end
        result[k] = sub
      else
        result[k] = v  -- array or scalar: replace
      end
    end
  end
  for i = 1, select("#", ...) do
    local t = select(i, ...)
    if t then deep_extend(t) end
  end
  return result
end

-- ── vim.tbl_extend ────────────────────────────────────────────────────────────
vim_stub.tbl_extend = function(mode, ...)
  local result = {}
  for i = 1, select("#", ...) do
    local t = select(i, ...)
    if t then
      for k, v in pairs(t) do result[k] = v end
    end
  end
  return result
end

-- ── vim.tbl_filter ────────────────────────────────────────────────────────────
vim_stub.tbl_filter = function(fn, t)
  local result = {}
  for _, v in ipairs(t) do
    if fn(v) then result[#result + 1] = v end
  end
  return result
end

-- ── vim.tbl_map ───────────────────────────────────────────────────────────────
vim_stub.tbl_map = function(fn, t)
  local result = {}
  for k, v in pairs(t) do result[k] = fn(v) end
  return result
end

-- ── vim.split ─────────────────────────────────────────────────────────────────
vim_stub.split = function(s, sep, _opts)
  local result = {}
  local pattern = "([^" .. sep .. "]*)" .. sep .. "?"
  for part in s:gmatch(pattern) do result[#result + 1] = part end
  -- remove last empty entry that gmatch always appends
  if result[#result] == "" then result[#result] = nil end
  return result
end

-- ── vim.trim ──────────────────────────────────────────────────────────────────
vim_stub.trim = function(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- ── vim.deepcopy ──────────────────────────────────────────────────────────────
vim_stub.deepcopy = function(orig)
  local copy
  if type(orig) == "table" then
    copy = {}
    for k, v in pairs(orig) do copy[vim_stub.deepcopy(k)] = vim_stub.deepcopy(v) end
    setmetatable(copy, getmetatable(orig))
  else
    copy = orig
  end
  return copy
end

-- ── vim.log ───────────────────────────────────────────────────────────────────
vim_stub.log = {
  levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 },
}

-- ── vim.notify ────────────────────────────────────────────────────────────────
vim_stub.notify = function(_msg, _level, _opts) end

-- ── vim.schedule ──────────────────────────────────────────────────────────────
vim_stub.schedule = function(fn) fn() end

-- ── vim.inspect ───────────────────────────────────────────────────────────────
vim_stub.inspect = function(v)
  if type(v) == "table" then return "{table}" end
  return tostring(v)
end

vim_stub.startswith = function(s, prefix)
  if type(s) ~= "string" or type(prefix) ~= "string" then return false end
  return s:sub(1, #prefix) == prefix
end

-- ── vim.cmd ───────────────────────────────────────────────────────────────────
vim_stub.cmd = function() end

-- ── vim.bo / vim.b ────────────────────────────────────────────────────────────
vim_stub.bo = { filetype = "java" }
vim_stub.b  = {}

-- ── vim.o ─────────────────────────────────────────────────────────────────────
vim_stub.o = { lines = 40, columns = 120 }

-- ── vim.uv ────────────────────────────────────────────────────────────────────
vim_stub.uv = {
  cwd = function() return "/test/project" end,
}

-- ── vim.loop (alias for vim.uv) ───────────────────────────────────────────────
vim_stub.loop = vim_stub.uv

-- ── vim.keymap ────────────────────────────────────────────────────────────────
vim_stub.keymap = {
  set = function() end,
  del = function() end,
}

-- ── vim.diagnostic ────────────────────────────────────────────────────────────
vim_stub.diagnostic = {
  get       = function() return {} end,
  set       = function() end,
  severity  = { ERROR = 1, WARN = 2, INFO = 3, HINT = 4 },
}

-- ── vim.uri_from_bufnr ────────────────────────────────────────────────────────
vim_stub.uri_from_bufnr = function(bufnr)
  return "file:///test/project/src/test/java/TestClass.java"
end

-- ── vim.api ───────────────────────────────────────────────────────────────────
vim_stub.api = {
  nvim_get_current_buf  = function() return 1 end,
  nvim_get_current_win  = function() return 1 end,
  nvim_win_is_valid     = function() return false end,
  nvim_win_close        = function() end,
  nvim_win_call         = function(_, fn) fn() end,
  nvim_set_current_win  = function() end,
  nvim_create_buf       = function() return 1 end,
  nvim_open_win         = function() return 1 end,
  nvim_buf_set_lines    = function() end,
  nvim_buf_set_extmark  = function() end,
  nvim_buf_clear_namespace = function() end,
  nvim_create_namespace = function() return 1 end,
  nvim_set_option_value = function() end,
  nvim_set_hl           = function() end,
  nvim_create_autocmd   = function() return 1 end,
  nvim_create_augroup   = function() return 1 end,
  nvim_create_user_command      = function() end,
  nvim_buf_create_user_command  = function() end,

  nvim_buf_get_name = function(_bufnr)
    return "/test/project/src/test/java/com/example/TestClass.java"
  end,

  nvim_buf_get_lines = function(_bufnr, _s, _e, _strict)
    return {
      "package com.example.test;",
      "",
      "public class TestClass {",
      "  @Test",
      "  public void testMethod1() { }",
      "  @Test",
      "  public void testMethod2() { }",
      "}",
    }
  end,
}

-- ── vim.fn ────────────────────────────────────────────────────────────────────
vim_stub.fn = {
  expand = function(path, _, _)
    -- Return a non-nil string for any glob/expand pattern
    if path == "%:p:h"         then return "/test/project/src/main/java" end
    if path == "%:t:r"         then return "TestClass"                  end
    if path == "%:p"           then return "/test/project/src/test/java/com/example/TestClass.java" end
    -- For glob patterns like "root/*/src/main/java" return a safe path
    if path:match("src/main/java") then return "/test/project/src/main/java" end
    return path
  end,

  glob = function(pattern, _, as_list)
    if pattern:match("gradlew") then
      return as_list and { "/test/project/gradlew" } or "/test/project/gradlew"
    end
    if pattern:match("mvnw") then
      return as_list and { "/test/project/mvnw" } or "/test/project/mvnw"
    end
    return as_list and {} or ""
  end,

  fnamemodify = function(path, modifier)
    if modifier == ":h"    then return path:match("(.*)/") or path end
    if modifier == ":t"    then return path:match("([^/]+)$") or path end
    if modifier == ":t:r"  then
      local t = path:match("([^/]+)$") or path
      return t:gsub("%.[^.]+$", "")
    end
    return path
  end,

  getftime  = function() return os.time() end,
  mkdir     = function() return 1 end,
  setqflist = function() end,

  jobstart = function(_cmd, _opts)
    -- Do NOT call on_exit synchronously — that would block the test suite
    -- for the duration of the real process the stub is pretending to run.
    return 12345
  end,

  input = function(opts_or_prompt, default, _completion)
    local prompt = type(opts_or_prompt) == "table" and opts_or_prompt.prompt  or opts_or_prompt
    local def    = type(opts_or_prompt) == "table" and opts_or_prompt.default or default
    prompt = tostring(prompt or "")
    if prompt:match("Package")    then return def or "com.example.test" end
    if prompt:match("Class name") then return def or "TestClass"        end
    if prompt:match("extends")    then return ""                        end
    if prompt:match("implements") then return ""                        end
    return def or ""
  end,
}

-- ── vim.fs ────────────────────────────────────────────────────────────────────
vim_stub.fs = {
  dirname  = function(path)
    if path == nil then return "/test/project" end
    return path:match("(.*)/") or path
  end,
  basename = function(path)
    if path == nil then return "" end
    return path:match("([^/]+)$") or path
  end,
  joinpath = function(...)
    return table.concat({ ... }, "/")
  end,
  root = function() return "/test/project" end,

  -- dir(path, opts?) returns iterator: for name, type in vim.fs.dir(...) do
  dir = function(_path, _opts)
    local dirs = { "com/example", "com/test", "org/example" }
    local i = 0
    return function()
      i = i + 1
      if i <= #dirs then return dirs[i], "directory" end
    end
  end,

  find = function(names, _opts)
    if type(names) == "table" then
      for _, name in ipairs(names) do
        if name == "gradlew"     then return { "/test/project/gradlew" } end
        if name == "mvnw"        then return { "/test/project/mvnw"    } end
        if name == "pom.xml"     then return { "/test/project/pom.xml" } end
        if name == "build.gradle" then return { "/test/project/build.gradle" } end
        if name == ".git"        then return { "/test/project/.git"    } end
      end
    end
    return {}
  end,
}

-- ── vim.ui ────────────────────────────────────────────────────────────────────
vim_stub.ui = {
  select = function(items, _opts, on_choice)
    if on_choice then on_choice(items[1], 1) end
  end,
}

-- ── vim.treesitter ────────────────────────────────────────────────────────────

-- A mock query object that satisfies both iter_captures and iter_matches.
-- iter_matches yields one fake match so get_current_file_package can return a value.
local function _mock_query()
  local mock_node = {
    type              = function() return "scoped_identifier" end,
    parent            = function()
      return { type = function() return "package_declaration" end }
    end,
    start             = function() return 0, 0, 0 end,
    ["end_"]          = function() return 0, 5, 5 end,
    next_named_sibling = function() return nil end,
  }
  -- captures[1] = "package_name" so the loop key → capture name lookup works
  local captures = { "package_name" }
  return {
    captures      = captures,
    iter_captures = function() return function() end end,
    iter_matches  = function()
      local done = false
      return function()
        if not done then
          done = true
          -- yield: pattern_index=1, match={[1]=node}, metadata={}
          return 1, { [1] = mock_node }, {}
        end
      end
    end,
  }
end

-- A mock TSNode with enough methods to satisfy source code
local function _mock_node()
  return {
    type              = function() return "identifier" end,
    parent            = function()
      return { type = function() return "package_declaration" end }
    end,
    start             = function() return 0, 0, 0 end,
    ["end_"]          = function() return 0, 5, 5 end,
    next_named_sibling = function() return nil end,
    child_count       = function() return 0 end,
  }
end

local function _mock_parser()
  local node = _mock_node()
  return {
    parse = function()
      return { { root = function() return node end } }
    end,
    invalidate = function() end,
  }
end

vim_stub.treesitter = {
  get_parser        = function() return _mock_parser() end,
  get_string_parser = function() return _mock_parser() end,
  get_node_text     = function() return "com.example.test" end,
  query = {
    parse = function() return _mock_query() end,
  },
}

-- ── vim.lsp ───────────────────────────────────────────────────────────────────
vim_stub.lsp = {
  get_clients     = function() return {} end,
  buf_get_clients = function() return {} end,
  util = {
    locations_to_items = function() return {} end,
  },
}

return vim_stub
