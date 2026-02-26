require('spec.support.init')

local stub = require('luassert.stub')

describe('plugin/java-utils.lua commands', function()
  local create_cmd_stub
  local commands
  local test_runner_mock

  before_each(function()
    package.loaded['java-utils'] = nil
    package.loaded['java-utils.config'] = nil
    package.loaded['java-utils.test_runner'] = nil
    package.preload['java-utils'] = nil
    package.preload['java-utils.config'] = nil
    package.preload['java-utils.test_runner'] = nil

    vim.b.java_utils_loaded = nil
    commands = {}

    test_runner_mock = {
      prompt_run_mode = function(cb) cb('run') end,
      prompt_test_method = function(methods, cb) cb(methods[1]) end,
      run_test = stub.new(),
      load_existing_report = function() end,
    }

    package.preload['java-utils'] = function()
      return {
        setup = function() end,
        create_file = function() end,
        list_java_tests = function() end,
        get_test_methods = function()
          return { 'testAlpha', 'testBeta', 'otherCase' }
        end,
        get_config = function()
          return {
            test_runner = {
              highlight_groups = {},
              test_patterns = { '*Test.java', '*IT.java' },
              auto_run_on_save = false,
            },
          }
        end,
      }
    end

    package.preload['java-utils.config'] = function()
      return {
        get = function()
          return {
            file_creator = { file_types = { 'class', 'interface' } },
          }
        end,
      }
    end

    package.preload['java-utils.test_runner'] = function()
      return test_runner_mock
    end

    create_cmd_stub = stub(vim.api, 'nvim_create_user_command').invokes(function(name, fn, opts)
      commands[name] = { fn = fn, opts = opts }
    end)

    assert.has_no.errors(function()
      dofile('plugin/java-utils.lua')
    end)
  end)

  after_each(function()
    if create_cmd_stub and create_cmd_stub.revert then
      create_cmd_stub:revert()
    end

    package.loaded['java-utils'] = nil
    package.loaded['java-utils.config'] = nil
    package.loaded['java-utils.test_runner'] = nil
    package.preload['java-utils'] = nil
    package.preload['java-utils.config'] = nil
    package.preload['java-utils.test_runner'] = nil

    vim.b.java_utils_loaded = nil
  end)

  it('JavaPickTest accepts optional testcase argument', function()
    assert.is_table(commands.JavaPickTest)
    assert.equals('?', commands.JavaPickTest.opts.nargs)

    commands.JavaPickTest.fn({ args = 'testBeta' })

    assert.stub(test_runner_mock.run_test).was_called(1)
    assert.stub(test_runner_mock.run_test).was_called_with({
      bufnr = 1,
      debug = false,
      method_name = 'testBeta',
    })
  end)

  it('JavaPickTest provides completion for testcase names', function()
    assert.is_function(commands.JavaPickTest.opts.complete)

    local matches = commands.JavaPickTest.opts.complete('test', 'JavaPickTest test', 17)
    assert.same({ 'testAlpha', 'testBeta' }, matches)
  end)
end)
