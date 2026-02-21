local M = {}

-- Module cache
local modules = {}

-- Lazy load modules
local function require_module(name)
    if not modules[name] then
        modules[name] = require('java-utils.' .. name)
    end
    return modules[name]
end

-- Forward-declare so M.setup can reference it
local setup_autocommands

-- Setup function
function M.setup(opts)
    local config = require_module('config')
    config.setup(opts)

    setup_autocommands()

    if config.get().debug then
        vim.notify('java-utils: Plugin setup complete', vim.log.levels.INFO)
    end
end

-- Setup autocommands (local to avoid polluting _G)
setup_autocommands = function()
    local config = require_module('config')
    local cfg = config.get()

    local group = vim.api.nvim_create_augroup('JavaUtilsAutoGroup', { clear = true })

    vim.api.nvim_create_autocmd('BufEnter', {
        group = group,
        pattern = cfg.test_runner.test_patterns,
        callback = function(args)
            local test_runner = require_module('test_runner')
            test_runner.load_existing_report(args.buf)
        end,
    })

    if cfg.test_runner.auto_run_on_save then
        vim.api.nvim_create_autocmd('BufWritePost', {
            group = group,
            pattern = cfg.test_runner.test_patterns,
            callback = function(args)
                local test_runner = require_module('test_runner')
                test_runner.prompt_run_mode(function(mode)
                    if mode then
                        test_runner.run_test({
                            bufnr = args.buf,
                            debug = mode == 'debug',
                            method_name = nil,
                        })
                    end
                end)
            end,
        })
    end
end

-- API functions
function M.create_file(opts)
    return require_module('file_creator').create_file(opts)
end

function M.get_test_methods()
    return require_module('test_runner').get_test_methods()
end

function M.run_test(opts)
    return require_module('test_runner').run_test(opts)
end

function M.list_java_tests()
    return require_module('test_runner').list_java_tests()
end

function M.get_config()
    return require_module('config').get()
end

return M