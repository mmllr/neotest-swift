## neotest-swift

This is a basic [neotest](https://github.com/nvim-neotest/neotest) adapter that allows running tests using the `swift test` command.

![screenshot](images/neotest-swift.png)

### Features

- [x] Running a single test case, all the tests in a file, or all the tests in a project
- [x] Test watching
- [x] Virtual text showing test failure messages
- [x] Displaying full and short test output
- DAP support


### Installation

[packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "nvim-neotest/neotest",
  requires = {
    "nvim-neotest/nvim-nio",
    "nvim-lua/plenary.nvim",
    "antoinemadec/FixCursorHold.nvim",
    "nvim-treesitter/nvim-treesitter",
    "ehmurray8/neotest-swift"
  }
}
```


### Configuration

Provide your adapters and other config to the setup function.

```lua
require("neotest").setup({
	adapters = {
		require("neotest-swift")({ }),
	},
    output = {
        enabled = true,
        open_on_run = false
    }
})
```

### Helpful Keybindings

```lua
-- Neotest
vim.keymap.set("n", "<Leader>tr", function() require("neotest").run.run() end, { desc = 'Run nearest test' })
vim.keymap.set("n", "<Leader>tf", function() require("neotest").run.run(vim.fn.expand("%")) end, { desc = 'Run all tests in file' })
vim.keymap.set("n", "<Leader>ta", function() require("neotest").run.run({ suite = true }) end, { desc = 'Run all tests in project' })
vim.keymap.set("n", "<Leader>tw", function() require("neotest").watch.toggle() end, { silent = true, desc = 'Watch test' })
vim.keymap.set("n", "<Leader>ts", function() require("neotest").summary.toggle() end, { silent = true, desc = 'Test summary' })
vim.keymap.set("n", "<Leader>to", function() require("neotest").output.open({ short = true, enter = true }) end, { silent = true, desc = 'Open test output' })
vim.keymap.set("n", "<Leader>tp", function() require("neotest").output_panel.toggle() end, { silent = true, desc = 'Toggle test output pane' })
```

