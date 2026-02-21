local M = {}

---@class JavaUtilsConfig
---@field file_creator JavaUtilsFileCreatorConfig
---@field test_runner JavaUtilsTestRunnerConfig
---@field debug boolean

---@class JavaUtilsFileCreatorConfig
---@field default_package? string|fun(): string|nil
---@field package_completion boolean
---@field use_current_file_package boolean
---@field file_types string[]

---@class JavaUtilsTestRunnerConfig
---@field auto_run_on_save boolean
---@field show_notifications boolean
---@field test_patterns string[]
---@field symbols table<string, string>
---@field highlight_groups table<string, table>

---@type JavaUtilsConfig
local defaults = {
    debug = false,
    file_creator = {
        default_package = nil,
        package_completion = true,
        use_current_file_package = true,
        file_types = { 'class', 'enum', 'interface', 'record' },
    },
    test_runner = {
        auto_run_on_save = false,
        show_notifications = true,
        test_patterns = { '*Test.java', '*IT.java' },
        symbols = {
            passed = ' ',
            error = ' ',
            failed = ' ',
            skipped = ' ',
        },
        highlight_groups = {
            TestPassed = { fg = '#00FF00' },
            TestFailed = { fg = '#FF0000' },
            TestSkipped = { fg = '#FFFF00' },
        },
    },
}

M.options = {}

---@param opts? JavaUtilsConfig
function M.setup(opts)
    M.options = vim.tbl_deep_extend('force', defaults, opts or {})
    
    -- Set up highlight groups
    for name, opts in pairs(M.options.test_runner.highlight_groups) do
        vim.api.nvim_set_hl(0, name, opts)
    end
    
    if M.options.debug then
        vim.notify('java-utils: Configuration applied', vim.log.levels.INFO)
    end
end

---@return JavaUtilsConfig
function M.get()
    return M.options
end

return M