local M = {}
local config = require('java-utils.config')

local function get_root()
    return vim.fs.dirname(
        vim.fs.find({ 'gradlew', 'mvnw', '.git' }, { upward = true })[1]
    ) or vim.uv.cwd()
end

local function get_current_file_package()
    local bufnr = vim.api.nvim_get_current_buf()
    local content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content_str = table.concat(content, '\n')
    
    -- Parse package declaration using treesitter
    local parser = vim.treesitter.get_string_parser(content_str, 'java')
    if not parser then return nil end
    
    local tree = parser:parse()[1]
    local root = tree:root()
    
    local query = vim.treesitter.query.parse('java', [[
        (package_declaration
            (scoped_identifier) @package_name)
    ]])
    
    for _, match, _ in query:iter_matches(root, content_str) do
        for id, node in pairs(match) do
            local capture_name = query.captures[id]
            if capture_name == 'package_name' then
                local package_name = vim.treesitter.get_node_text(node, content_str)
                parser:invalidate()
                return package_name
            end
        end
    end
    
    parser:invalidate()
    return nil
end

local function list_java_packages()
    local packages = {}
    local java_root = vim.fn.expand(get_root() .. '**/src/main/java')
    
    -- Check if directory exists
    local ok, result = pcall(vim.fs.dir, java_root, { depth = math.huge })
    if not ok then return packages end
    
    for name, type in result do
        if type == 'directory' then
            local package_path = name:match('^(.+)$')
            if package_path then
                local package_name = package_path:gsub('/', '.')
                table.insert(packages, package_name)
            end
        end
    end
    return packages
end

local function list_java_files()
    local java_files =
        vim.fn.expand(get_root() .. '**/src/main/java/**/*.java', true, true)
    return vim.tbl_map(function(file)
        local package_path = file:match('src/main/java/(.+)%.java$')
        if package_path then
            return package_path:gsub('/', '.')
        end
        return nil
    end, java_files)
end



local function prompt_for_kind(callback)
    local cfg = config.get()
    local kinds = cfg.file_creator.file_types
    
    vim.ui.select(kinds, {
        prompt = 'Select Kind:',
    }, function(choice)
        if choice then
            callback(choice)
        end
    end)
end

local function prompt_for_packages(callback)
    local packages = list_java_packages()
    local current_package = get_current_file_package()
    local cfg = config.get()
    
    -- Use current file package as default if configured
    local default_package = current_package
    if cfg.file_creator.default_package then
        if type(cfg.file_creator.default_package) == 'function' then
            default_package = cfg.file_creator.default_package() or current_package
        else
            default_package = cfg.file_creator.default_package
        end
    end
    
    -- Use vim.fn.input with completion as the primary method
    local final_package
    if cfg.file_creator.package_completion and #packages > 0 then
        -- Use vim.fn.input with custom completion
        final_package = vim.fn.input({
            prompt = 'Package name: ',
            default = default_package or '',
            completion = 'customlist,v:lua.require("java-utils.file_creator")._package_completion',
        })
    else
        -- Fallback to simple input with default
        final_package = vim.fn.input({
            prompt = 'Package name: ',
            default = default_package or '',
        })
    end
    
    -- Use the input result or fall back to default
    if final_package and final_package ~= '' then
        callback(final_package)
    elseif default_package then
        callback(default_package)
    end
end

local function prompt_for_relationship(kind, callback)
    local relationships = { 'Standalone' }
    if kind == 'interface' or kind == 'class' then
        table.insert(relationships, 'Superclass')
    end
    if kind ~= 'interface' then
        table.insert(relationships, 'Interface')
    end

    -- Use vim.fn.input with completion for relationship selection
    local relationship_str = table.concat(relationships, ', ')
    local relation = vim.fn.input({
        prompt = 'Select Relationship (' .. relationship_str .. '): ',
        default = 'Standalone',
        completion = 'customlist,v:lua.require("java-utils.file_creator")._relationship_completion',
    })
    
    if not relation or relation == '' then
        return
    end

    if relation == 'Standalone' then
        callback({})
        return
    end

    local files = list_java_files()
    local prompt_text = relation == 'Superclass' and 'Extends: ' or 'Implements: '

    -- Use vim.fn.input with completion for base type selection
    local base_type = vim.fn.input({
        prompt = prompt_text,
        completion = 'customlist,v:lua.require("java-utils.file_creator")._base_type_completion',
    })
    
    if base_type and base_type ~= '' then
        if relation == 'Superclass' then
            callback({ extends = base_type })
        else
            callback({ implements = base_type })
        end
    end
end

local function prompt_for_class_name(callback)
    local class_name = vim.fn.input({
        prompt = 'Class name: ',
        default = '',
    })
    if class_name and class_name ~= '' then
        callback(class_name)
    end
end

local function _create_file(options)
    local root = get_root()
    local package_path = options.package:gsub('%.', '/')
    local java_dir = vim.fn.expand(root .. '/*/src/main/java')
    local dir_path = java_dir .. '/' .. package_path

    vim.fn.mkdir(dir_path, 'p')

    local class_name = options.class_name

    local file_path = dir_path .. '/' .. class_name .. '.java'

    local lines = {}

    if options.package and options.package ~= '' then
        table.insert(lines, 'package ' .. options.package .. ';')
        table.insert(lines, '')
    end

    local declaration = 'public ' .. options.kind .. ' ' .. class_name

    local imports = {}

    if options.extends and options.extends ~= '' then
        local extends_package = options.extends:match('(.+)%.[^.]+$')
        local extends_class = options.extends:match('([^.]+)$')
        if extends_package and extends_package ~= options.package then
            table.insert(imports, 'import ' .. options.extends .. ';')
        end
        declaration = declaration .. ' extends ' .. extends_class
    end

    if options.implements and options.implements ~= '' then
        local implements_package = options.implements:match('(.+)%.[^.]+$')
        local implements_class = options.implements:match('([^.]+)$')
        if implements_package and implements_package ~= options.package then
            table.insert(imports, 'import ' .. options.implements .. ';')
        end
        declaration = declaration .. ' implements ' .. implements_class
    end

    if #imports > 0 then
        for _, import_stmt in ipairs(imports) do
            table.insert(lines, import_stmt)
        end
        table.insert(lines, '')
    end

    declaration = declaration .. ' {'
    table.insert(lines, declaration)
    table.insert(lines, '\t')
    table.insert(lines, '}')

    local file = io.open(file_path, 'w')
    if file then
        file:write(table.concat(lines, '\n'))
        file:close()
        vim.notify('Created: ' .. file_path, vim.log.levels.INFO)
        vim.cmd('edit ' .. file_path)
    else
        vim.notify('Failed to create file: ' .. file_path, vim.log.levels.ERROR)
    end
end

local function create_file(opts)
    opts = opts or {}
    
    -- Allow direct options for programmatic use
    if opts.kind and opts.package and opts.class_name then
        _create_file(opts)
        return
    end
    
    prompt_for_kind(function(kind)
        prompt_for_packages(function(package)
            prompt_for_relationship(kind, function(relationship)
                prompt_for_class_name(function(class_name)
                    local options = vim.tbl_extend('force', {
                        kind = kind,
                        package = package,
                        class_name = class_name,
                    }, relationship)
                    _create_file(options)
                end)
            end)
        end)
    end)
end

-- Completion functions for vim.fn.input
function M._package_completion(ArgLead, CmdLine, CursorPos)
    local packages = list_java_packages()
    local matches = {}
    
    for _, package in ipairs(packages) do
        if package:match('^' .. ArgLead) then
            table.insert(matches, package)
        end
    end
    
    return matches
end

function M._relationship_completion(ArgLead, CmdLine, CursorPos)
    local relationships = { 'Standalone', 'Superclass', 'Implements' }
    local matches = {}
    
    for _, relationship in ipairs(relationships) do
        if relationship:match('^' .. ArgLead) then
            table.insert(matches, relationship)
        end
    end
    
    return matches
end

function M._base_type_completion(ArgLead, CmdLine, CursorPos)
    local files = list_java_files()
    local matches = {}
    
    for _, file in ipairs(files) do
        if file:match('^' .. ArgLead) then
            table.insert(matches, file)
        end
    end
    
    return matches
end

M.create_file = create_file
M._create_file = _create_file
M.get_current_file_package = get_current_file_package
M.list_java_packages = list_java_packages

return M