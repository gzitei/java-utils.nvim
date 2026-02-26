-- Plugin specification for java-utils.nvim
-- This file is loaded by Neovim's plugin system

-- Prevent double loading
if vim.b.java_utils_loaded then
  return
end

local function setup_java_utils()
  -- config.setup() must run before test_runner is required
  -- (test_runner calls config.get() at module-load time).
  local java_utils = require('java-utils')
  java_utils.setup()

  -- ── Commands ──────────────────────────────────────────────────────────────

  vim.api.nvim_create_user_command('JavaNew', function(opts)
    local args = vim.split(opts.args, '%s+', { trimempty = true })
    java_utils.create_file({ args = args })
  end, { 
    nargs = '*',
    complete = function(ArgLead, CmdLine, CursorPos)
        local parts = vim.split(CmdLine:sub(1, CursorPos), '%s+', { trimempty = false })
        if #parts == 2 then
            local cfg = require('java-utils.config').get()
            local kinds = cfg.file_creator.file_types
            local matches = {}
            for _, k in ipairs(kinds) do
                if vim.startswith(k, ArgLead) then
                    table.insert(matches, k)
                end
            end
            return matches
        end
        return {}
    end,
    desc = 'Create new Java file' 
  })

  vim.api.nvim_create_user_command('JavaFindTest', function()
    java_utils.list_java_tests()
  end, { desc = 'Find tests for current Java class' })

  vim.api.nvim_create_user_command('JavaRunTest', function()
    local test_runner = require('java-utils.test_runner')
    local bufnr = vim.api.nvim_get_current_buf()
    test_runner.prompt_run_mode(function(mode)
      if mode then
        test_runner.run_test({
          bufnr  = bufnr,
          debug  = mode == 'debug',
          method_name = nil,
        })
      end
    end)
  end, { desc = 'Run current Java test class (prompts Run / Debug)' })

  vim.api.nvim_create_user_command('JavaPickTest', function(opts)
    local test_runner = require('java-utils.test_runner')
    local bufnr    = vim.api.nvim_get_current_buf()
    local methods  = java_utils.get_test_methods()
    local method_arg = vim.trim(opts.args or '')

    if #methods == 0 then
      vim.notify('No @Test methods found in current buffer', vim.log.levels.WARN)
      return
    end

    if method_arg ~= '' then
      test_runner.prompt_run_mode(function(mode)
        if mode then
          test_runner.run_test({
            bufnr  = bufnr,
            debug  = mode == 'debug',
            method_name = method_arg,
          })
        end
      end)
      return
    end

    test_runner.prompt_test_method(methods, function(method)
      if method then
        test_runner.prompt_run_mode(function(mode)
          if mode then
            test_runner.run_test({
              bufnr  = bufnr,
              debug  = mode == 'debug',
              method_name = method,
            })
          end
        end)
      end
    end)
  end, {
    nargs = '?',
    complete = function(ArgLead)
      local matches = {}
      local methods = java_utils.get_test_methods()
      for _, method in ipairs(methods) do
        if ArgLead == '' or vim.startswith(method, ArgLead) then
          table.insert(matches, method)
        end
      end
      return matches
    end,
    desc = 'Pick and run a specific Java test method (prompts Run / Debug)'
  })

  -- ── Highlights ────────────────────────────────────────────────────────────

  local cfg = java_utils.get_config()
  for name, hl_opts in pairs(cfg.test_runner.highlight_groups) do
    vim.api.nvim_set_hl(0, name, hl_opts)
  end

  -- ── Autocommands ──────────────────────────────────────────────────────────

  local group = vim.api.nvim_create_augroup('JavaUtilsPluginGroup', { clear = true })

  -- Load existing test results when entering a test file
  vim.api.nvim_create_autocmd('BufEnter', {
    group   = group,
    pattern = cfg.test_runner.test_patterns,
    callback = function(args)
      require('java-utils.test_runner').load_existing_report(args.buf)
    end,
  })

  -- Prompt to run tests automatically on save (if configured)
  if cfg.test_runner.auto_run_on_save then
    vim.api.nvim_create_autocmd('BufWritePost', {
      group   = group,
      pattern = cfg.test_runner.test_patterns,
      callback = function(args)
        local test_runner = require('java-utils.test_runner')
        test_runner.prompt_run_mode(function(mode)
          if mode then
            test_runner.run_test({
              bufnr  = args.buf,
              debug  = mode == 'debug',
              method_name = nil,
            })
          end
        end)
      end,
    })
  end

  vim.b.java_utils_loaded = true
end

local ok, err = pcall(setup_java_utils)
if not ok then
  vim.notify('Failed to load java-utils.nvim: ' .. tostring(err), vim.log.levels.ERROR)
end
