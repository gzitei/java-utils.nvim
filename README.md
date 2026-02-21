# java-utils.nvim

A Neovim plugin for Java development with intelligent file creation and test running.

## Features

### 🚀 File Creation
- **Smart Package Detection**: Detects the current file's package and uses it as default
- **Package Completion**: Tab completion for package names
- **Configurable Defaults**: Static package string or dynamic `function() → string`
- **Multiple File Types**: `class`, `interface`, `enum`, `record`
- **Inheritance Support**: `extends` and `implements` prompts built-in

### 🧪 Test Runner
- **JUnit Test Discovery**: Finds `@Test` methods via Tree-sitter
- **Method-Level Testing**: Run a whole class or pick one method
- **Debug Support**: Integrated with [nvim-dap](https://github.com/mfussenegger/nvim-dap) *(optional — Debug option hidden when dap is not installed)*
- **Visual Feedback**: Results shown inline as virtual text + diagnostics
- **Auto-run on Save**: Optional prompt after saving a test file

### ⚙️ Configuration
- Sensible defaults, works out of the box
- Full LSP integration with [jdtls](https://github.com/mfussenegger/nvim-jdtls)

## Requirements

- Neovim ≥ 0.9.0
- [nvim-notify](https://github.com/rcarriga/nvim-notify) (for notifications)
- Java Development Kit (JDK)
- Gradle (`gradlew`) or Maven (`mvnw`) build wrapper in the project root
- **Optional:** [nvim-dap](https://github.com/mfussenegger/nvim-dap) + [nvim-dap-java](https://github.com/mfussenegger/nvim-dap) for debug mode

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'gzitei/java-utils.nvim',
  ft = 'java',
  dependencies = {
    'rcarriga/nvim-notify',
    -- optional: for debug support
    'mfussenegger/nvim-dap',
  },
  opts = {},
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'gzitei/java-utils.nvim',
  ft = 'java',
  requires = { 'rcarriga/nvim-notify' },
  config = function()
    require('java-utils').setup()
  end,
}
```

## Configuration

```lua
require('java-utils').setup({
  debug = false, -- log setup steps

  file_creator = {
    -- nil  → use current file's package
    -- string → always use that package
    -- function → called each time; return value used
    default_package = nil,

    package_completion = true,        -- <Tab> completion in package prompt
    use_current_file_package = true,  -- pre-fill prompt with current package

    file_types = { 'class', 'enum', 'interface', 'record' },
  },

  test_runner = {
    auto_run_on_save    = false,              -- prompt after BufWritePost on test files
    show_notifications  = true,
    test_patterns       = { '*Test.java', '*IT.java' },

    -- Nerd Font symbols
    symbols = {
      passed  = ' ',
      error   = ' ',
      failed  = ' ',
      skipped = ' ',
    },

    highlight_groups = {
      TestPassed  = { fg = '#00FF00' },
      TestFailed  = { fg = '#FF0000' },
      TestSkipped = { fg = '#FFFF00' },
    },
  },
})
```

### Dynamic default package

```lua
require('java-utils').setup({
  file_creator = {
    default_package = function()
      local branch = vim.fn.system('git branch --show-current'):gsub('\n', '')
      return 'com.company.feature.' .. branch:gsub('-', '')
    end,
  },
})
```

### Custom symbols

```lua
require('java-utils').setup({
  test_runner = {
    symbols = {
      passed  = '✓',
      error   = '⚠',
      failed  = '✗',
      skipped = '⊘',
    },
  },
})
```

## Commands

| Command | Description |
|---|---|
| `:JavaNew` | Create a new Java file interactively |
| `:JavaRunTest` | Run all tests in the current test class |
| `:JavaPickTest` | Pick a specific `@Test` method to run |
| `:JavaFindTest` | Open quickfix with tests for the current class (requires jdtls) |

All test commands prompt **Run / Debug / Skip** — the **Debug** option only appears when `nvim-dap` is installed.

### `:JavaNew` workflow

1. Select file type (`class`, `interface`, `enum`, `record`)
2. Enter / confirm package name (Tab completion available)
3. Select relationship (`Standalone`, `Superclass`, `Interface`)
4. Enter class name → file created and opened

### Suggested keymaps

```lua
vim.keymap.set('n', '<leader>jc', ':JavaNew<CR>',      { desc = 'Create Java file' })
vim.keymap.set('n', '<leader>jt', ':JavaRunTest<CR>',  { desc = 'Run Java tests' })
vim.keymap.set('n', '<leader>jp', ':JavaPickTest<CR>', { desc = 'Pick Java test' })
vim.keymap.set('n', '<leader>jf', ':JavaFindTest<CR>', { desc = 'Find Java tests' })
```

## API

```lua
local java_utils = require('java-utils')

java_utils.setup(opts)           -- initialize plugin
java_utils.get_config()          -- return current config table
java_utils.create_file(opts)     -- create file (nil = interactive)
java_utils.get_test_methods()    -- return list of @Test method names
java_utils.run_test(opts)        -- run test (opts: {bufnr, debug, method_name?})
java_utils.list_java_tests()     -- open quickfix with LSP references
```

**Programmatic file creation:**
```lua
require('java-utils').create_file({
  kind       = 'class',
  package    = 'com.example.service',
  class_name = 'UserService',
  implements = 'com.example.service.IUserService',
})
```

## Troubleshooting

### Package completion not working

Ensure your project has a standard Maven/Gradle layout:
```
project/
├── src/main/java/com/example/
├── src/test/java/com/example/
└── gradlew  (or  mvnw)
```

### Tests not discovered

- Test files must match `*Test.java` or `*IT.java` (configurable via `test_patterns`)
- Test methods must have the `@Test` annotation
- A build wrapper (`gradlew` / `mvnw`) must be present in the project tree

### Debug not available

Ensure [nvim-dap](https://github.com/mfussenegger/nvim-dap) is installed. When dap is missing the **Debug** option is automatically hidden from all prompts.

## Testing

```bash
make test         # run all specs with busted
make test-file FILE=spec/java_utils_spec.lua  # run a single spec
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Add tests in `spec/`
4. Run `make test` to verify
5. Open a Pull Request

