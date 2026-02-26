-- spec/java_utils_spec.lua
-- Tests for java-utils.nvim core modules.
-- Run with: make test   or   busted spec/java_utils_spec.lua

require("spec.support.init")

local stub  = require("luassert.stub")

-- ── helpers ───────────────────────────────────────────────────────────────────

local function fresh_config()
  package.loaded["java-utils.config"] = nil
  return require("java-utils.config")
end

local function fresh_file_creator()
  package.loaded["java-utils.config"]       = nil
  package.loaded["java-utils.file_creator"] = nil
  local config       = require("java-utils.config")
  local file_creator = require("java-utils.file_creator")
  config.setup()
  return config, file_creator
end

local function fresh_test_runner()
  package.loaded["java-utils.config"]      = nil
  package.loaded["java-utils.test_runner"] = nil
  local config = require("java-utils.config")
  config.setup()  -- MUST call setup before test_runner loads (it calls config.get() at module level)
  local test_runner = require("java-utils.test_runner")
  return config, test_runner
end

-- ─────────────────────────────────────────────────────────────────────────────
describe("java-utils.config", function()

  after_each(function()
    package.loaded["java-utils.config"] = nil
  end)

  it("has default configuration", function()
    local config = fresh_config()
    config.setup()
    local opts = config.get()

    assert.is_false(opts.debug)
    assert.is_true(opts.file_creator.package_completion)
    assert.is_true(opts.file_creator.use_current_file_package)
    assert.same({ "class", "enum", "interface", "record" }, opts.file_creator.file_types)
    assert.is_false(opts.test_runner.auto_run_on_save)
    assert.is_true(opts.test_runner.show_notifications)
    assert.same({ "*Test.java", "*IT.java" }, opts.test_runner.test_patterns)
  end)

  it("merges user config with defaults", function()
    local config = fresh_config()
    config.setup({
      debug = true,
      file_creator = {
        default_package = "com.example",
        file_types      = { "class", "interface" },
      },
      test_runner = {
        auto_run_on_save = true,
        symbols = { passed = "✓" },
      },
    })
    local opts = config.get()

    assert.is_true(opts.debug)
    assert.equals("com.example", opts.file_creator.default_package)
    assert.same({ "class", "interface" }, opts.file_creator.file_types)
    assert.is_true(opts.file_creator.package_completion) -- default preserved
    assert.is_true(opts.test_runner.auto_run_on_save)
    assert.equals("✓", opts.test_runner.symbols.passed)
    assert.is_string(opts.test_runner.symbols.error)  -- default preserved (icon glyph)
  end)

  it("accepts a function as default_package", function()
    local config    = fresh_config()
    local pkg_func  = function() return "com.dynamic" end
    config.setup({ file_creator = { default_package = pkg_func } })

    assert.equals(pkg_func, config.get().file_creator.default_package)
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
describe("java-utils.file_creator", function()

  local config, file_creator
  local stubs = {}

  before_each(function()
    config, file_creator = fresh_file_creator()
    stubs.expand  = stub(vim.fn,  "expand")
    stubs.fs_dir  = stub(vim.fs,  "dir")
    stubs.input   = stub(vim.fn,  "input")
    stubs.select  = stub(vim.ui,  "select")
    stubs.mkdir   = stub(vim.fn,  "mkdir")
    stubs.io_open = stub(io,      "open")
  end)

  after_each(function()
    for _, s in pairs(stubs) do
      if s.revert then s:revert() end
    end
    package.loaded["java-utils.config"]       = nil
    package.loaded["java-utils.file_creator"] = nil
  end)

  it("gets the current file package", function()
    local get_buf  = stub(vim.api, "nvim_get_current_buf").returns(1)
    local get_name = stub(vim.api, "nvim_buf_get_name").returns("/project/src/main/java/com/example/test/TestClass.java")

    local pkg = file_creator.get_current_file_package()
    assert.equals("com.example.test", pkg)

    get_buf:revert()
    get_name:revert()
  end)

  it("lists java packages as a table", function()
    local glob_stub = stub(vim.fn, "glob").returns({
      "/project/src/main/java/com/example/Test1.java",
      "/project/src/main/java/com/test/Test2.java"
    })

    local packages = file_creator.list_java_packages()
    assert.is_table(packages)
    
    glob_stub:revert()
  end)

  it("provides package completion filtered by arg lead", function()
    local glob_stub = stub(vim.fn, "glob").returns({
      "/project/src/main/java/com/example/Test1.java",
      "/project/src/main/java/com/test/Test2.java",
      "/project/src/main/java/org/example/Test3.java"
    })

    local matches = file_creator._package_completion("com", "JavaNew com", 8)
    local com_count = 0
    for _, m in ipairs(matches) do
      if m:match("^com") then com_count = com_count + 1 end
    end
    assert.is_true(com_count >= 1)
    
    glob_stub:revert()
  end)

  it("creates a file when given direct options", function()
    -- get_root() calls vim.fs.find then vim.fs.dirname, make both return valid strings
    local fs_find_stub = stub(vim.fs, "find").returns({ "/test/project/.git" })
    local fs_dir_stub  = stub(vim.fs, "dirname").returns("/test/project")
    stubs.buf_name = stub(vim.api, "nvim_buf_get_name").returns("")
    stubs.isdirectory = stub(vim.fn, "isdirectory").returns(0)
    stubs.glob = stub(vim.fn, "glob").returns({ "/test/project/app/src/main/java" })

    local mock_file = { write = stub.new(), close = stub.new() }
    stubs.io_open.returns(mock_file)

    file_creator._create_file({ kind = "class", package = "com.example", class_name = "TestClass" })

    assert.stub(stubs.io_open).was_called()
    assert.stub(mock_file.write).was_called()
    assert.stub(mock_file.close).was_called()

    fs_find_stub:revert()
    fs_dir_stub:revert()
    stubs.buf_name:revert()
    stubs.isdirectory:revert()
    stubs.glob:revert()
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
describe("java-utils.test_runner", function()

  local stubs = {}

  before_each(function()
    _, _ = fresh_test_runner()   -- sets up config; test_runner loaded fresh
    stubs.buf_name   = stub(vim.api, "nvim_buf_get_name")
    stubs.fs_dirname = stub(vim.fs,  "dirname")
    stubs.fs_find    = stub(vim.fs,  "find")
    stubs.expand     = stub(vim.fn,  "expand")
    stubs.glob       = stub(vim.fn,  "glob")
    stubs.fnamemod   = stub(vim.fn,  "fnamemodify")
    stubs.getftime   = stub(vim.fn,  "getftime")
    stubs.jobstart   = stub(vim.fn,  "jobstart")
  end)

  after_each(function()
    for _, s in pairs(stubs) do
      if s.revert then s:revert() end
    end
    package.loaded["java-utils.config"]      = nil
    package.loaded["java-utils.test_runner"] = nil
    package.loaded["notify"] = nil
  end)

  it("returns a table from get_test_methods", function()
    package.loaded["java-utils.test_runner"] = nil
    local _, tr = fresh_test_runner()

    local gp = stub(vim.treesitter, "get_parser").returns({
      parse      = function() return { { root = function() return {} end } } end,
      invalidate = function() end,
    })
    local qp = stub(vim.treesitter.query, "parse").returns({
      iter_captures = function() return function() end end,
      captures      = {},
    })

    local methods = tr.get_test_methods()
    assert.is_table(methods)

    gp:revert()
    qp:revert()
  end)

  it("run_test does not raise when no build wrapper is found", function()
    package.loaded["java-utils.test_runner"] = nil
    local _, tr = fresh_test_runner()

    stubs.fs_find.returns({})
    stubs.buf_name.returns("/project/src/test/java/TestClass.java")
    stubs.expand.returns("TestClass")

    local lsp_stub = stub(vim.lsp, "get_clients").returns({})

    local ok, err = pcall(function()
      tr.run_test({ bufnr = 1, debug = false, method_name = "testMethod" })
    end)
    assert.is_true(ok, "run_test should not raise: " .. tostring(err))

    lsp_stub:revert()
  end)

  it("parse_xml_to_json returns structured result", function()
    package.loaded["java-utils.test_runner"] = nil
    local _, tr = fresh_test_runner()

    local xml = [[
      <testsuite errors="0" failures="1" tests="2" time="0.123">
        <testcase classname="TestClass" name="testMethod1" time="0.05"/>
        <testcase classname="TestClass" name="testMethod2" time="0.073">
          <failure message="Test failed">Assertion error</failure>
        </testcase>
      </testsuite>
    ]]

    -- parse_xml_to_json reads the file then calls get_string_parser + query.parse.
    -- The stub for get_string_parser must make iter_captures produce a hit for
    -- the testsuite STag so get_testsuite_attributes can fill in errors/failures/tests.
    -- Since our mock query's iter_captures returns nothing, parse_xml_to_json
    -- will return an attrs table with only type='testsuite' but no attribute values.
    -- We verify the call succeeds and returns a table (not nil).
    local mock_file = { read = function() return xml end, close = function() end }
    local io_stub   = stub(io, "open").returns(mock_file)

    local gsp = stub(vim.treesitter, "get_string_parser").returns({
      parse      = function() return { { root = function() return {} end } } end,
      invalidate = function() end,
    })
    local qp = stub(vim.treesitter.query, "parse").returns({
      iter_captures = function() return function() end end,
      captures      = {},
    })

    local result = tr.parse_xml_to_json("/tmp/test.xml")
    -- With mocked treesitter, attr values won't be parsed from XML, but the
    -- function should still return a table without raising.
    assert.is_table(result)

    io_stub:revert()
    gsp:revert()
    qp:revert()
  end)

  it("prompt_run_mode omits Debug when dap java adapter is not configured", function()
    package.loaded["java-utils.test_runner"] = nil
    local _, tr = fresh_test_runner()

    -- The preloaded dap stub has no adapters.java by default
    local dap = require("dap")
    dap.adapters = dap.adapters or {}
    dap.adapters["java"] = nil  -- explicitly unconfigured

    local captured_choices
    local ui_stub = stub(vim.ui, "select").invokes(function(choices, _opts, cb)
      captured_choices = choices
      cb("Skip")
    end)

    tr.prompt_run_mode(function() end)

    local function has(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
    assert.is_false(has(captured_choices, "Debug"),
      "Debug should not appear when adapter is unconfigured")

    ui_stub:revert()
  end)

  it("prompt_run_mode includes Debug when dap java adapter is configured", function()
    package.loaded["java-utils.test_runner"] = nil
    local _, tr = fresh_test_runner()

    local dap = require("dap")
    dap.adapters = dap.adapters or {}
    dap.adapters["java"] = { type = "server", host = "127.0.0.1", port = 5005 }

    local captured_choices
    local ui_stub = stub(vim.ui, "select").invokes(function(choices, _opts, cb)
      captured_choices = choices
      cb("Skip")
    end)

    tr.prompt_run_mode(function() end)

    local function has(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
    assert.is_true(has(captured_choices, "Debug"),
      "Debug should appear when adapter is configured")

    dap.adapters["java"] = nil  -- cleanup
    ui_stub:revert()
  end)

  it("prompt_run_mode invokes callback with 'run' on Run choice", function()
    package.loaded["java-utils.test_runner"] = nil
    local _, tr = fresh_test_runner()

    local ui_stub = stub(vim.ui, "select").invokes(function(_choices, _opts, cb)
      cb("Run")
    end)

    local result
    tr.prompt_run_mode(function(mode) result = mode end)
    assert.equals("run", result)

    ui_stub:revert()
  end)

  it("prompt_run_mode invokes callback with nil on Skip", function()
    package.loaded["java-utils.test_runner"] = nil
    local _, tr = fresh_test_runner()

    local ui_stub = stub(vim.ui, "select").invokes(function(_choices, _opts, cb)
      cb("Skip")
    end)

    local result = "sentinel"
    tr.prompt_run_mode(function(mode) result = mode end)
    assert.is_nil(result)

    ui_stub:revert()
  end)

  it("run_test dismisses notification when jobstart fails", function()
    package.loaded["java-utils.test_runner"] = nil
    local _, tr = fresh_test_runner()

    stubs.buf_name.returns("/project/src/test/java/com/example/MyServiceIT.java")
    stubs.fs_dirname.returns("/project/src/test/java/com/example")
    stubs.fs_find.invokes(function(names, _opts)
      if names[1] == "gradlew" then
        return { "/project/gradlew" }
      end
      if names[1] == "pom.xml" then
        return { "/project/pom.xml" }
      end
      return {}
    end)
    stubs.jobstart.returns(0)

    local dismiss_called = 0
    package.loaded["notify"] = {
      notify = function() return {} end,
      dismiss = function() dismiss_called = dismiss_called + 1 end,
    }

    tr.run_test({ bufnr = 1, debug = false, method_name = nil })

    assert.is_true(dismiss_called > 0)
  end)

  it("run_test opens floating output window and starts 5s autoclose timer", function()
    package.loaded["java-utils.test_runner"] = nil
    local _, tr = fresh_test_runner()

    stubs.buf_name.returns("/project/src/test/java/com/example/MyServiceIT.java")
    stubs.fs_dirname.returns("/project/src/test/java/com/example")
    stubs.fs_find.invokes(function(names, _opts)
      if names[1] == "gradlew" then
        return { "/project/gradlew" }
      end
      if names[1] == "pom.xml" then
        return { "/project/pom.xml" }
      end
      return {}
    end)
    stubs.glob.returns({})

    local open_win_stub = stub(vim.api, "nvim_open_win").returns(1)

    local original_new_timer = vim.loop.new_timer
    local timer_started_timeout
    vim.loop.new_timer = function()
      return {
        start = function(_, timeout, _repeat, _cb)
          timer_started_timeout = timeout
        end,
        is_closing = function() return false end,
        stop = function() end,
        close = function() end,
      }
    end

    stubs.jobstart.invokes(function(_cmd, opts)
      opts.on_stdout(nil, { "stdout line" })
      opts.on_stderr(nil, { "stderr line" })
      opts.on_exit(nil, 0)
      return 42
    end)

    tr.run_test({ bufnr = 1, debug = false, method_name = nil })

    assert.stub(open_win_stub).was_called()
    assert.equals(5000, timer_started_timeout)

    vim.loop.new_timer = original_new_timer
    open_win_stub:revert()
  end)

  it("run_test debug path dismisses notification when java dap is unavailable", function()
    package.loaded["java-utils.test_runner"] = nil
    local _, tr = fresh_test_runner()

    stubs.buf_name.returns("/project/src/test/java/com/example/MyServiceIT.java")
    stubs.fs_dirname.returns("/project/src/test/java/com/example")
    stubs.fs_find.invokes(function(names, _opts)
      if names[1] == "gradlew" then
        return { "/project/gradlew" }
      end
      if names[1] == "pom.xml" then
        return { "/project/pom.xml" }
      end
      return {}
    end)

    local dap = require("dap")
    dap.adapters = dap.adapters or {}
    dap.configurations = dap.configurations or {}
    dap.adapters.java = nil
    dap.configurations.java = nil

    local dismiss_called = 0
    package.loaded["notify"] = {
      notify = function() return {} end,
      dismiss = function() dismiss_called = dismiss_called + 1 end,
    }

    tr.run_test({ bufnr = 1, debug = true, method_name = nil })

    assert.is_true(dismiss_called > 0)
  end)

  it("run_test only shows error notification when exit code is non-zero", function()
    package.loaded["java-utils.test_runner"] = nil
    local _, tr = fresh_test_runner()

    stubs.buf_name.returns("/project/src/test/java/com/example/MyServiceIT.java")
    stubs.fs_dirname.returns("/project/src/test/java/com/example")
    stubs.fs_find.invokes(function(names, _opts)
      if names[1] == "gradlew" then
        return { "/project/gradlew" }
      end
      if names[1] == "pom.xml" then
        return { "/project/pom.xml" }
      end
      return {}
    end)
    stubs.glob.returns({})

    local messages = {}
    package.loaded["notify"] = {
      notify = function(msg)
        table.insert(messages, msg)
        return {}
      end,
      dismiss = function() end,
    }

    stubs.jobstart.invokes(function(_cmd, opts)
      opts.on_stderr(nil, { "warning output" })
      opts.on_exit(nil, 0)
      return 42
    end)

    tr.run_test({ bufnr = 1, debug = false, method_name = nil })

    local all = table.concat(messages, "\n")
    assert.is_true(all:match("Test run completed") ~= nil)
    assert.is_true(all:match("Test run produced errors") == nil)
  end)

  it("run_test shows error notification when exit code is non-zero", function()
    package.loaded["java-utils.test_runner"] = nil
    local _, tr = fresh_test_runner()

    stubs.buf_name.returns("/project/src/test/java/com/example/MyServiceIT.java")
    stubs.fs_dirname.returns("/project/src/test/java/com/example")
    stubs.fs_find.invokes(function(names, _opts)
      if names[1] == "gradlew" then
        return { "/project/gradlew" }
      end
      if names[1] == "pom.xml" then
        return { "/project/pom.xml" }
      end
      return {}
    end)
    stubs.glob.returns({})

    local messages = {}
    package.loaded["notify"] = {
      notify = function(msg)
        table.insert(messages, msg)
        return {}
      end,
      dismiss = function() end,
    }

    stubs.jobstart.invokes(function(_cmd, opts)
      opts.on_exit(nil, 1)
      return 42
    end)

    tr.run_test({ bufnr = 1, debug = false, method_name = nil })

    local all = table.concat(messages, "\n")
    assert.is_true(all:match("Test run produced errors") ~= nil)
  end)

  it("load_existing_report loads matching IT report by basename", function()
    package.loaded["java-utils.test_runner"] = nil
    local _, tr = fresh_test_runner()

    stubs.buf_name.returns("/project/src/test/java/com/example/MyServiceIT.java")
    stubs.fs_dirname.returns("/project/src/test/java/com/example")
    stubs.fs_find.invokes(function(names, _opts)
      if names[1] == "gradlew" then
        return { "/project/gradlew" }
      end
      if names[1] == "pom.xml" then
        return { "/project/pom.xml" }
      end
      return {}
    end)
    stubs.glob.returns({
      "/project/build/test-results/test/TEST-com.example.OtherIT.xml",
      "/project/build/test-results/test/TEST-com.example.MyServiceIT.xml",
    })
    stubs.fnamemod.invokes(function(path, modifier)
      if modifier == ":t:r" then
        local tail = path:match("([^/]+)$") or path
        return tail:gsub("%.[^.]+$", "")
      end
      return path
    end)
    stubs.getftime.invokes(function(path)
      if path:match("MyServiceIT") then
        return 200
      end
      return 100
    end)

    local clear_ns_stub = stub(vim.api, "nvim_buf_clear_namespace")

    tr.load_existing_report(1)

    assert.stub(clear_ns_stub).was_called()

    clear_ns_stub:revert()
  end)
end)
