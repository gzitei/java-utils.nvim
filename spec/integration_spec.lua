-- spec/integration_spec.lua
-- Integration tests for java-utils.nvim: module loading, public API surface,
-- and end-to-end config / file-creation flow.
-- Run with: make test   or   busted spec/integration_spec.lua

require("spec.support.init")

-- ── helpers ───────────────────────────────────────────────────────────────────

local function fresh_all()
  package.loaded["java-utils"]              = nil
  package.loaded["java-utils.config"]       = nil
  package.loaded["java-utils.file_creator"] = nil
  package.loaded["java-utils.test_runner"]  = nil
end

-- ─────────────────────────────────────────────────────────────────────────────
describe("module loading", function()

  before_each(fresh_all)
  after_each(fresh_all)

  it("loads java-utils (main) without error", function()
    assert.has_no.errors(function()
      require("java-utils.config").setup()
      require("java-utils")
    end)
  end)

  it("loads java-utils.config without error", function()
    assert.has_no.errors(function() require("java-utils.config") end)
  end)

  it("loads java-utils.file_creator without error", function()
    assert.has_no.errors(function() require("java-utils.file_creator") end)
  end)

  it("loads java-utils.test_runner without error", function()
    assert.has_no.errors(function()
      require("java-utils.config").setup()
      require("java-utils.test_runner")
    end)
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
describe("public API surface", function()

  local java_utils, config, file_creator, test_runner

  before_each(function()
    fresh_all()
    -- config.setup() must be called before test_runner is loaded because
    -- test_runner.lua calls config.get() at module-load time (setup_highlights).
    local config_mod = require("java-utils.config")
    config_mod.setup()
    config        = config_mod
    test_runner   = require("java-utils.test_runner")
    -- Now safe to load the main module (which wraps test_runner)
    java_utils    = require("java-utils")
    file_creator  = require("java-utils.file_creator")
  end)

  after_each(fresh_all)

  it("main module exposes create_file", function()
    assert.is_function(java_utils.create_file)
  end)

  it("main module exposes run_test", function()
    assert.is_function(java_utils.run_test)
  end)

  it("main module exposes get_config", function()
    assert.is_function(java_utils.get_config)
  end)

  it("main module exposes list_java_tests", function()
    assert.is_function(java_utils.list_java_tests)
  end)

  it("file_creator exposes create_file", function()
    assert.is_function(file_creator.create_file)
  end)

  it("file_creator exposes get_current_file_package", function()
    assert.is_function(file_creator.get_current_file_package)
  end)

  it("test_runner exposes get_test_methods", function()
    assert.is_function(test_runner.get_test_methods)
  end)

  it("test_runner exposes run_test", function()
    assert.is_function(test_runner.run_test)
  end)

  it("config exposes setup", function()
    assert.is_function(config.setup)
  end)

  it("config exposes get", function()
    assert.is_function(config.get)
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
describe("setup + get_config round-trip", function()

  before_each(fresh_all)
  after_each(fresh_all)

  it("setup stores user values and get_config returns them", function()
    local config_mod = require("java-utils.config")
    config_mod.setup()  -- init defaults first
    local java_utils = require("java-utils")
    java_utils.setup({
      debug = true,
      file_creator = { default_package = "com.test.integration" },
    })

    local cfg = java_utils.get_config()
    assert.is_true(cfg.debug)
    assert.equals("com.test.integration", cfg.file_creator.default_package)
  end)

  it("preserves defaults for keys not overridden", function()
    local config_mod = require("java-utils.config")
    config_mod.setup()
    local java_utils = require("java-utils")
    java_utils.setup({ debug = true })

    local cfg = java_utils.get_config()
    assert.is_true(cfg.file_creator.package_completion)
    assert.same({ "class", "enum", "interface", "record" }, cfg.file_creator.file_types)
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
describe("package completion", function()

  local file_creator

  before_each(function()
    fresh_all()
    local config = require("java-utils.config")
    config.setup({ file_creator = { package_completion = true, use_current_file_package = true } })
    file_creator = require("java-utils.file_creator")
  end)

  after_each(fresh_all)

  it("_package_completion filters by arg lead", function()
    local glob_stub = require("luassert.stub")(vim.fn, "glob").returns({
      "/project/src/main/java/com/example/Test1.java",
      "/project/src/main/java/com/test/Test2.java",
      "/project/src/main/java/org/example/Test3.java"
    })

    local matches = file_creator._package_completion("com.", "JavaNew com.", 8)
    assert.same({ "com.example", "com.test" }, matches)

    glob_stub:revert()
  end)

  it("_package_completion returns all packages when lead is empty", function()
    local glob_stub = require("luassert.stub")(vim.fn, "glob").returns({
      "/project/src/main/java/com/example/Test1.java",
      "/project/src/main/java/org/example/Test2.java"
    })

    local matches = file_creator._package_completion("", "JavaNew ", 8)
    assert.is_table(matches)

    glob_stub:revert()
  end)
end)
