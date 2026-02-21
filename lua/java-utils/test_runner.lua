local M = {}
local config = require('java-utils.config')

local function get_symbols()
    local cfg = config.get()
    return cfg.test_runner.symbols
end

local function setup_highlights()
    local cfg = config.get()
    for name, opts in pairs(cfg.test_runner.highlight_groups) do
        vim.api.nvim_set_hl(0, name, opts)
    end
end

-- Initialize highlights on module load
setup_highlights()

local symbols = get_symbols()

local hl_by_status = {
    passed = 'TestPassed',
    error = 'TestFailed',
    failed = 'TestFailed',
    skipped = 'TestSkipped',
}

---@param text string|string[]
local function show_long_text_in_floating_window(text)
    local current_win = vim.api.nvim_get_current_win()
    local lines
    if type(text) == 'string' then
        lines = vim.split(text, '\n')
    else
        lines = text
    end

    local width = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.8)

    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
    vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })

    local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        style = 'minimal',
        border = 'rounded',
    })

    vim.api.nvim_win_call(win, function()
        vim.cmd('normal! G')
    end)
    vim.api.nvim_set_current_win(current_win)

    vim.keymap.set('n', 'q', function()
        vim.api.nvim_win_close(win, true)
    end, { buffer = buf, nowait = true })
    vim.keymap.set('n', '<Esc>', function()
        vim.api.nvim_win_close(win, true)
    end, { buffer = buf, nowait = true })
    local timer = vim.loop.new_timer()

    timer:start(5000, 0, function()
        vim.schedule(function()
            if vim.api.nvim_win_is_valid(win) then
                if vim.api.nvim_get_current_win() ~= win then
                    vim.api.nvim_win_close(win, true)
                end
            end

            if not timer:is_closing() then
                timer:stop()
                timer:close()
            end
        end)
    end)

    vim.api.nvim_create_autocmd({ 'WinEnter', 'BufEnter' }, {
        buffer = buf,
        once = true,
        callback = function()
            if timer and not timer:is_closing() then
                timer:stop()
                timer:close()
            end
        end,
    })
end

---@class testcase
---@field skipped? boolean
---@field classname string
---@field name string
---@field time string
---@field content? string
---@field message? string
---@field type? string
---@field status? string

---@class testsuite
---@field errors string
---@field failures string
---@field hostname string
---@field name string
---@field skipped string
---@field tests string
---@field time string
---@field timestamp string
---@field testcases testcase[]

---@class class_node
---@field text string
---@field node TSNode

---@class parsed_document
---@field package_declaration class_node
---@field class_declaration class_node
---@field method_declaration class_node[]

---@class TestRunOptions
---@field bufnr integer
---@field debug boolean
---@field method_name? string

local function get_file_content(file_path)
    local file = io.open(file_path, 'r')
    if not file then
        return ''
    end
    local content = file:read('*all')
    file:close()
    return content
end

local function get_query(content, query_str)
    local parser = vim.treesitter.get_string_parser(content, 'xml')
    local tree = parser:parse()[1]
    local root = tree:root()
    local query = vim.treesitter.query.parse('xml', query_str)
    parser:invalidate()
    return query, root
end

local function get_tag_attributes(node, content)
    local attrs = {}
    while true do
        node = node:next_named_sibling()
        if not node then
            break
        end
        local text = vim.treesitter.get_node_text(node, content)
        local attribute_text = vim.split(text, '=')
        local key, value = attribute_text[1], attribute_text[2]
        if key and value then
            attrs[vim.trim(key)] = vim.trim(value):gsub('"', '')
        end
    end
    return attrs
end

local function get_testsuite_attributes(content)
    local attrs = { type = 'testsuite' }
    local query_str = [[
        (STag
            (Name) @_name
            (#eq? @_name "testsuite"))
        (EmptyElemTag
            (Name) @_name
            (#eq? @_name "testsuite"))
    ]]
    local query, root = get_query(content, query_str)
    for id, node in query:iter_captures(root, content) do
        local capture_name = query.captures[id]
        if capture_name == '_name' then
            local tag_attrs = get_tag_attributes(node, content)
            attrs = vim.tbl_extend('force', attrs, tag_attrs)
        end
    end
    return attrs
end

local function get_children_content(current_node, content)
    local state = {}
    local query_str = [[
        (element
            (STag
                (Name) @name
                (#eq? @name "failure"))
            (content) @data) @failure
        (EmptyElemTag
            (Name) @name
            (#eq? @name "skipped")) @skipped
    ]]
    local query, _ = get_query(content, query_str)
    for id, node in query:iter_captures(current_node, content) do
        local capture_name = query.captures[id]
        if capture_name == 'skipped' or capture_name == 'failure' then
            state['status'] = capture_name
        end
        if capture_name == 'name' then
            local attrs = get_tag_attributes(node, content)
            state = vim.tbl_extend('force', state, attrs)
        end
        if capture_name == 'data' then
            local node_text = vim.treesitter.get_node_text(node, content)
            local cdata_content = node_text:match('<!%[CDATA%[(.-)%]%]>')
                or node_text
            state = vim.tbl_extend('force', state, { content = cdata_content })
        end
    end
    return state
end

local function get_testcases_attributes(content)
    local testcases = {}
    local query_str = [[
        (element
            (STag
                (Name) @_name
                (#eq? @_name "testcase"))
            (content) @content) @element
        (element
            (EmptyElemTag
                (Name) @_name
                (#eq? @_name "testcase"))) @element
    ]]
    local query, root = get_query(content, query_str)
    local idx = 0
    for id, node in query:iter_captures(root, content) do
        local capture_name = query.captures[id]
        if capture_name == 'content' then
            local content_attrs = get_children_content(node, content)
            testcases[idx] =
                vim.tbl_extend('force', testcases[idx] or {}, content_attrs)
        end
        if capture_name == '_name' then
            local tag_attrs = get_tag_attributes(node, content)
            idx = idx + 1
            testcases[idx] =
                vim.tbl_extend('force', testcases[idx] or {}, tag_attrs)
        end
    end
    return testcases
end

local function reset_xml_parser(file_path)
    local content = get_file_content(file_path)
    local parser = vim.treesitter.get_string_parser(content, 'xml')
    parser:invalidate()
end

---@param file_path any
---@return testsuite
local function parse_xml_to_json(file_path)
    local content = get_file_content(file_path)
    local testsuite = get_testsuite_attributes(content)
    local testcases = get_testcases_attributes(content)
    testsuite.testcases = testcases
    return testsuite
end

---@return parsed_document
local function parse_document()
    local data = {
        package_declaration = nil,
        class_declaration = nil,
        method_declaration = {},
    }
    local query_str = [[
      (package_declaration
        (scoped_identifier) @package_name)

      (class_declaration
        name: (identifier) @class_name
        body: (class_body
          (method_declaration
            name: (identifier) @method_name
          )*
        )
      )
    ]]
    local query = vim.treesitter.query.parse('java', query_str)
    local parser = vim.treesitter.get_parser(0, 'java')
    if parser ~= nil then
        local tree = parser:parse()[1]
        for _, node, _ in query:iter_captures(tree:root(), 0) do
            local node_type = node:parent():type()
            if
                node_type == 'class_declaration'
                or node_type == 'package_declaration'
            then
                if data[node_type] == nil then
                    local text = vim.treesitter.get_node_text(
                        node,
                        vim.api.nvim_get_current_buf()
                    )
                    data[node_type] = { text = text, node = node }
                end
            end
            if node_type == 'method_declaration' then
                local text = vim.treesitter.get_node_text(
                    node,
                    vim.api.nvim_get_current_buf()
                )
                table.insert(data[node_type], { text = text, node = node })
            end
        end
        parser:invalidate()
    end
    return data
end

---@return string[]
M.get_test_methods = function()
    local methods = {}
    local query_str = [[
      (method_declaration
        (modifiers
          (marker_annotation
            name: (identifier) @annotation
            (#eq? @annotation "Test")))
        name: (identifier) @method_name)
    ]]
    local query = vim.treesitter.query.parse('java', query_str)
    local parser = vim.treesitter.get_parser(0, 'java')
    if parser ~= nil then
        local tree = parser:parse()[1]
        for id, node in query:iter_captures(tree:root(), 0) do
            local capture_name = query.captures[id]
            if capture_name == 'method_name' then
                local text = vim.treesitter.get_node_text(
                    node,
                    vim.api.nvim_get_current_buf()
                )
                table.insert(methods, text)
            end
        end
        parser:invalidate()
    end
    return methods
end

local function get_test_dir(buf_name)
    local dir = vim.fs.dirname(buf_name)
    local test_dir = dir:gsub('^.*src/main/java', 'src/test/java')
    return test_dir
end

---@param msg string
---@param id notify.Record|nil
---@param end_state? boolean
---@return notify.Record
local function notification(msg, id, end_state)
    if end_state == nil then
        end_state = false
    end
    local cfg = config.get()
    if not cfg.test_runner.show_notifications then
        return nil
    end
    
    local opts = {
        render = 'compact',
        icon = ' 󰙨',
        keep = function()
            return not end_state
        end,
        title = 'Java Test',
        animate = false,
    }
    if end_state then
        opts.timeout = 2000
    end
    if id ~= nil then
        opts.replace = id
    end
    return require('notify').notify(msg .. ' ', 'info', opts)
end

---@param case testcase
---@return 'passed'|'skipped'|'failed'
local function get_test_result_status(case)
    if case.status == 'skipped' then
        return 'skipped'
    elseif case.status == 'failure' then
        return 'failed'
    else
        return 'passed'
    end
end

---@param status 'passed'|'skipped'|'failed'
---@param time number
---@return table[]
local function build_method_virt_text(status, time)
    local text = {}
    local symbols = get_symbols()
    if status == 'passed' then
        table.insert(text, { symbols.passed, hl_by_status.passed })
        table.insert(text, { string.format(' (%.3f s)', time), 'Comment' })
    elseif status == 'skipped' then
        table.insert(text, { symbols.skipped, 'Comment' })
    else
        table.insert(text, { symbols.failed, hl_by_status.failed })
        table.insert(text, { string.format(' (%.3f s)', time), 'Comment' })
    end
    return text
end

---@param bufnr integer
---@param ns_id integer
---@param case testcase
---@param line integer
---@param col integer
---@param col_end integer
local function add_failure_diagnostic(bufnr, ns_id, case, line, col, col_end)
    local diagnostics = vim.diagnostic.get(bufnr, { namespace = ns_id })
    local diagnostic = {
        bufnr = bufnr,
        lnum = line,
        message = case.content,
        col = col,
        end_col = col_end,
        severity = vim.diagnostic.severity.ERROR,
        source = 'Java Test',
        namespace = ns_id,
    }
    table.insert(diagnostics, diagnostic)
    vim.diagnostic.set(ns_id, bufnr, diagnostics)
end

---@param status testsuite
---@param node TSNode
---@param bufnr integer
---@param ns_id integer
local function add_class_mark(status, node, bufnr, ns_id)
    local line, _, _ = node:start()
    local errors = tonumber(status.errors)
    local failed = tonumber(status.failures)
    local passed = (errors == 0 and failed == 0)
    local symbols = get_symbols()
    local icon = passed and symbols.passed or symbols.failed
    local time = tonumber(status.time)

    vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
        virt_text = {
            {
                icon,
                passed and 'TestPassed' or 'TestFailed',
            },
            {
                string.format(' (%.3f s)', time),
                'Comment',
            },
        },
        virt_text_pos = 'eol',
        hl_mode = 'combine',
    })
end

---@param case testcase
---@param node TSNode
---@param bufnr integer
---@param ns_id integer
local function add_method_mark(case, node, bufnr, ns_id)
    local line, col, _ = node:start()
    local _, col_end, _ = node:end_()
    local time = tonumber(case.time) or 0
    local status = get_test_result_status(case)
    local text = build_method_virt_text(status, time)

    if status == 'failed' then
        add_failure_diagnostic(bufnr, ns_id, case, line, col, col_end)
    end

    vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
        virt_text = text,
        virt_text_pos = 'eol',
        hl_mode = 'combine',
    })
end

---@param testcases testcase[]
---@param method_name string
---@return testcase|nil
local function find_matching_testcase(testcases, method_name)
    return vim.tbl_filter(function(testcase)
        return testcase.name:match(method_name .. '%(%)') ~= nil
            or testcase.name:match('^' .. method_name .. '$') ~= nil
    end, testcases)[1]
end

---@param data testsuite
---@param nodes parsed_document
---@param bufnr integer
---@param ns integer
local function process_report_json(data, nodes, bufnr, ns)
    vim.schedule(function()
        if not nodes.class_declaration then
            return
        end
        if not nodes.method_declaration then
            return
        end
        local class_node = nodes.class_declaration.node
        pcall(add_class_mark, data, class_node, bufnr, ns)
        local done = {}
        for _, method in pairs(nodes.method_declaration) do
            local method_name = method.text
            if done[method_name] == nil then
                if not data.testcases then
                    return
                end
                local case = find_matching_testcase(data.testcases, method_name)
                if case ~= nil then
                    pcall(add_method_mark, case, method.node, bufnr, ns)
                end
                done[method_name] = 'ok'
            end
        end
    end)
end

---@param file string
---@param nodes parsed_document
---@param bufnr integer
---@param ns integer
local function parse_report_xml(file, nodes, bufnr, ns)
    local ok, data = pcall(parse_xml_to_json, file)
    if not ok then
        return
    end
    pcall(process_report_json, data, nodes, bufnr, ns)
end

---@param callback fun(mode: 'run'|'debug'|nil)
M.prompt_run_mode = function(callback)
    -- Only offer Debug when nvim-dap is installed AND a Java adapter is configured.
    local dap_ok, dap = pcall(require, 'dap')
    local java_adapter_ready = dap_ok
        and dap.adapters ~= nil
        and dap.adapters['java'] ~= nil

    local choices = java_adapter_ready
        and { 'Run', 'Debug', 'Skip' }
        or  { 'Run', 'Skip' }

    vim.ui.select(choices, {
        prompt = 'Select test mode:',
    }, function(choice)
        if choice == 'Run' then
            callback('run')
        elseif choice == 'Debug' then
            callback('debug')
        else
            -- 'Skip' or nil (user dismissed)
            callback(nil)
        end
    end)
end

---@param methods string[]
---@param callback fun(method: string|nil)
M.prompt_test_method = function(methods, callback)
    vim.ui.select(methods, {
        prompt = 'Select test method:',
    }, function(choice)
        callback(choice)
    end)
end

M.list_java_tests = function()
    local nodes = parse_document()
    local class_declaration = nodes.class_declaration
    if class_declaration == nil then
        return
    end
    local class_declaration_node = class_declaration.node
    if class_declaration_node == nil then
        return
    end
    local bufnr = vim.api.nvim_get_current_buf()
    local buf_name = vim.api.nvim_buf_get_name(bufnr)
    local fname = vim.fn.fnamemodify(vim.fs.basename(buf_name), ':t:r')
    local test_dir = get_test_dir(buf_name)
    local clients = vim.lsp.get_clients({ name = 'jdtls', bufnr = bufnr })
    if #clients > 0 then
        local x, y = class_declaration_node:start()
        local client = clients[1]
        local params = {
            context = { includeDeclaration = true },
            position = { character = y, line = x },
            textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        }
        client:request('textDocument/references', params, function(_, result)
            local list = {}
            local done = {}
            local items = vim.lsp.util.locations_to_items(
                result or {},
                client.offset_encoding
            )
            for _, item in ipairs(items) do
                local filename = item.filename
                if filename ~= nil then
                    if done[filename] == nil and filename:match(test_dir) then
                        table.insert(list, item)
                    end
                end
            end
            vim.fn.setqflist({}, ' ', {
                items = list,
                title = string.format('Tests for %s', fname),
            })
            vim.cmd('copen')
        end, bufnr)
    end
end

local function get_build(bufnr)
    local file = vim.api.nvim_buf_get_name(bufnr)
    local cwd = vim.fs.dirname(file)
    local build = vim.fs.find({ 'pom.xml', 'build.gradle' }, {
        path = cwd,
        upward = true,
    })[1]
    return vim.fs.dirname(build)
end

local function get_wrapper(bufnr)
    local file = vim.api.nvim_buf_get_name(bufnr)
    local cwd = vim.fs.dirname(file)
    local wrapper = vim.fs.find({ 'gradlew', 'mvnw' }, {
        path = cwd,
        upward = true,
    })[1]
    return wrapper
end

---@param wrapper string
---@param project_name string
---@param test_class string
---@param method_name? string
---@param debug boolean
---@return string[]
local function build_test_command(
    wrapper,
    project_name,
    test_class,
    method_name,
    debug
)
    local wrapper_name = vim.fs.basename(wrapper)
    local cmd = { wrapper }

    if wrapper_name == 'gradlew' then
        local test_filter = test_class
        if method_name then
            test_filter = string.format('%s.%s', test_class, method_name)
        end

        table.insert(cmd, 'clean')
        table.insert(cmd, string.format(':%s:test', project_name))
        if debug then
            table.insert(cmd, '--debug-jvm')
        end
        table.insert(cmd, '--continue')
        table.insert(cmd, '--tests')
        table.insert(cmd, '--rerun-tasks')
        table.insert(cmd, test_filter)
    else
        local test_filter = test_class
        if method_name then
            test_filter = string.format('%s#%s', test_class, method_name)
        end

        table.insert(cmd, '-am')
        table.insert(cmd, 'test')
        if debug then
            table.insert(cmd, '-Dmaven.surefire.debug')
        end
        table.insert(cmd, string.format('-Dtest=%s', test_filter))
    end

    return cmd
end

---@param output string
---@return boolean
local function is_test_environment_ready(output)
    local up  = output:upper()
    local low = output:lower()
    return up:match('T E S T S') ~= nil           -- Gradle & Maven Surefire banner
        or low:match('listening') ~= nil           -- debug: waiting for DAP (both)
        -- Gradle-specific
        or low:match('0 tests completed') ~= nil
        -- Maven Surefire-specific
        or output:match('Running ') ~= nil         -- "Running com.example.TestClass"
        or low:match('tests run:') ~= nil          -- per-class summary line
        or low:match('no tests were executed') ~= nil
end

---@return fun(config: table): table
local function create_dap_before_hook()
    return function(config)
        local final = vim.deepcopy(config)
        final.steppingGranularity = 'statement'
        final.exceptionBreakpoints = { 'uncaught', 'caught' }
        local root = vim.fs.root(0, {
            'build.gradle',
            'pom.xml',
        })
        local project_name = vim.fs.basename(root)
        local test_class = vim.fn.expand('%:t:r')
        local method_name = nil
        final.mainClass = project_name .. '.' .. test_class
        final.projectName = project_name
        final.args = method_name and { '--tests', method_name } or {}
        final.classPaths = final.classPaths or {}
        final.modulePaths = final.modulePaths or {}
        final.request = 'launch'
        final.type = 'java'
        final.console = 'internalConsole'
        final.stopOnEntry = false
        return final
    end
end

---@param options TestRunOptions
M.run_test = function(options)
    local bufnr = options.bufnr
    local debug = options.debug
    local method_name = options.method_name

    local notification_id = notification('Preparing test run...')

    local buf_name = vim.api.nvim_buf_get_name(bufnr)
    local wrapper = get_wrapper(bufnr)
    if not wrapper then
        notification('No build wrapper found', notification_id, true)
        return
    end

    local build_dir = get_build(bufnr)
    local project_name = vim.fs.basename(build_dir)
    local test_class = vim.fn.fnamemodify(buf_name, ':t:r')

    local cmd = build_test_command(
        wrapper,
        project_name,
        test_class,
        method_name,
        debug
    )

    local test_results_dir = vim.fs.joinpath(build_dir, 'target', 'surefire-reports')
    if vim.fs.basename(wrapper) == 'gradlew' then
        test_results_dir = vim.fs.joinpath(build_dir, 'build', 'test-results', 'test')
    end

    local function find_latest_report()
        local reports = vim.fn.glob(
            vim.fs.joinpath(test_results_dir, 'TEST-*.xml'),
            false,
            true
        )
        if #reports == 0 then
            return nil
        end
        table.sort(reports, function(a, b)
            return vim.fn.getftime(a) > vim.fn.getftime(b)
        end)
        return reports[1]
    end

    local function on_exit(_, code)
        notification('Test run completed', notification_id, true)
        local report = find_latest_report()
        if report then
            local nodes = parse_document()
            local ns = vim.api.nvim_create_namespace('java_test_results')
            vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
            parse_report_xml(report, nodes, bufnr, ns)
        end
    end

    local function on_stdout(_, data)
        local output = table.concat(data, '\n')
        if is_test_environment_ready(output) then
            notification('Running tests...', notification_id)
        end
    end

    if debug then
        local dap_ok, dap = pcall(require, 'dap')
        if not dap_ok then
            notification('nvim-dap is not installed — cannot debug', notification_id, true)
            return
        end
        notification('Starting debug session...', notification_id)
        local dap_config = {
            type = 'java',
            request = 'launch',
            name = 'Debug Java Test',
            mainClass = project_name .. '.' .. test_class,
            projectName = project_name,
            args = method_name and { '--tests', method_name } or {},
            before = create_dap_before_hook(),
        }
        dap.run(dap_config)
        return
    end

    notification('Starting test run...', notification_id)
    vim.fn.jobstart(cmd, {
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = on_stdout,
        on_stderr = on_stdout,
        on_exit = on_exit,
        cwd = build_dir,
    })
end

---@param bufnr integer
M.load_existing_report = function(bufnr)
    local cfg = config.get()
    if not cfg.test_runner.auto_run_on_save then
        return
    end
    
    local buf_name = vim.api.nvim_buf_get_name(bufnr)
    local build_dir = get_build(bufnr)
    local test_results_dir
    
    if vim.fs.basename(get_wrapper(bufnr)) == 'gradlew' then
        test_results_dir = vim.fs.joinpath(build_dir, 'build', 'test-results', 'test')
    else
        test_results_dir = vim.fs.joinpath(build_dir, 'target', 'surefire-reports')
    end

    local reports = vim.fn.glob(
        vim.fs.joinpath(test_results_dir, 'TEST-*.xml'),
        false,
        true
    )
    if #reports == 0 then
        return
    end

    table.sort(reports, function(a, b)
        return vim.fn.getftime(a) > vim.fn.getftime(b)
    end)

    local latest_report = reports[1]
    local test_class = vim.fn.fnamemodify(buf_name, ':t:r')
    local report_class = vim.fn.fnamemodify(latest_report, ':t:r'):sub(6) -- Remove 'TEST-' prefix

    if test_class == report_class then
        local nodes = parse_document()
        local ns = vim.api.nvim_create_namespace('java_test_results')
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        parse_report_xml(latest_report, nodes, bufnr, ns)
    end
end

-- API Functions
M.setup_highlights = setup_highlights
M.get_symbols = get_symbols
M.parse_document = parse_document
M.parse_xml_to_json = parse_xml_to_json

return M