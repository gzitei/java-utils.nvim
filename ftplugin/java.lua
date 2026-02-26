-- Check if we're in a Java file
if vim.bo.filetype ~= 'java' then
  return
end

-- Prevent double loading
if vim.b.java_utils_loaded then
  return
end
vim.b.java_utils_loaded = true

-- Load the plugin
local java_utils = require('java-utils')

-- Buffer-local commands (these override the global ones when in a Java buffer)
vim.api.nvim_buf_create_user_command(0, 'JavaFindTest', function()
  java_utils.list_java_tests()
end, {
  desc = 'Find tests for Java Class or Method',
})

vim.api.nvim_buf_create_user_command(0, 'JavaRunTest', function()
  java_utils.run_test({
    bufnr = vim.api.nvim_get_current_buf(),
    debug = false,
    method_name = nil,
  })
end, {
  desc = 'Run Java test class',
})

vim.api.nvim_buf_create_user_command(0, 'JavaPickTest', function(opts)
  local methods = java_utils.get_test_methods()
  local method_arg = vim.trim(opts.args or '')

  if #methods == 0 then
    vim.notify('No @Test methods found in current buffer', vim.log.levels.WARN)
    return
  end

  if method_arg ~= '' then
    java_utils.run_test({
      bufnr = vim.api.nvim_get_current_buf(),
      debug = false,
      method_name = method_arg,
    })
    return
  end
  
  vim.ui.select(methods, {
    prompt = 'Select test method:',
  }, function(method)
    if method then
      java_utils.run_test({
        bufnr = vim.api.nvim_get_current_buf(),
        debug = false,
        method_name = method,
      })
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
  desc = 'Pick and run a specific Java test method',
})

-- Setup buffer-local autocommands
local group = vim.api.nvim_create_augroup('JavaUtilsBufferGroup', { clear = true })

vim.api.nvim_create_autocmd('BufWritePost', {
  group = group,
  buffer = 0,
  callback = function()
    local cfg = java_utils.get_config()
    if not cfg.test_runner.auto_run_on_save then
      return
    end
    
    vim.ui.select({ 'Run', 'Debug', 'Don\'t run' }, {
      prompt = 'Run Java Test?',
    }, function(choice)
      if choice == 'Run' then
        java_utils.run_test({
          bufnr = vim.api.nvim_get_current_buf(),
          debug = false,
          method_name = nil,
        })
      elseif choice == 'Debug' then
        java_utils.run_test({
          bufnr = vim.api.nvim_get_current_buf(),
          debug = true,
          method_name = nil,
        })
      end
    end)
  end,
})
