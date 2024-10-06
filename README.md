## neotest-swift

This is a basic [neotest](https://github.com/nvim-neotest/neotest) adapter that allows running tests using the `swift test` command.

![screenshot](images/neotest-swift.png)

### Features

- [x] Running a single test case, all the tests in a file, all the tests in a target or all the tests in a project
- [x] Test watching
- [x] Virtual text showing test failure messages
- [x] Displaying full and short test output
- [x] DAP support


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

#### Neotest

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

#### nvim-dap

Requires:
* [nvim-dap](https://github.com/mfussenegger/nvim-dap)
* [codelldb](https://github.com/vadimcn/codelldb)
  * I installed it with [Mason](https://github.com/williamboman/mason.nvim)
* (Optional) [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui)


```lua
local dap = require("dap")

local dapui = require("dapui")
dapui.setup()

-- Automatically attach and detach from DAPUI
dap.listeners.before.attach.dapui_config = function()
	dapui.open()
end
dap.listeners.before.launch.dapui_config = function()
	dapui.open()
end
dap.listeners.before.event_terminated.dapui_config = function()
	dapui.close()
end
dap.listeners.before.event_exited.dapui_config = function()
	dapui.close()
end

-- Use swift's LLDB
local libLLDB = "/Applications/Xcode.app/Contents/SharedFrameworks/LLDB.framework/Versions/A/LLDB"

dap.adapters.swift = {
	type = "server",
	port = "${port}",
	executable = {
		command = "/Users/emmet/.local/share/nvim/mason/bin/codelldb", -- Use your exectuable I got this from Mason
		args = { "--liblldb", libLLDB, "--port", "${port}" },
	},
}

dap.configurations.swift = {
	{
		name = "Launch file",
		type = "swift",
		request = "launch",
		program = function()
			return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
		end,
		cwd = "${workspaceFolder}",
		stopOnEntry = false,
	},
}
```


### Helpful Keybindings

```lua
-- Neotest
vim.keymap.set("n", "<Leader>tr", function() require("neotest").run.run() end, { desc = 'Run nearest test' })
vim.keymap.set("n", "<Leader>tf", function() require("neotest").run.run(vim.fn.expand("%")) end, { desc = 'Run all tests in file' })
vim.keymap.set("n", "<Leader>ta", function() require("neotest").run.run({ suite = true }) end, { desc = 'Run all tests in project' })
vim.keymap.set("n", "<Leader>tt", function() require("neotest").run.run({ suite = true, extra_args = { target = true } }) end, { desc = 'Run all tests in target (swift).' })
vim.keymap.set("n", "<Leader>tw", function() require("neotest").watch.toggle() end, { silent = true, desc = 'Watch test' })
vim.keymap.set("n", "<Leader>ts", function() require("neotest").summary.toggle() end, { silent = true, desc = 'Test summary' })
vim.keymap.set("n", "<Leader>to", function() require("neotest").output.open({ short = true, enter = true }) end, { silent = true, desc = 'Open test output' })
vim.keymap.set("n", "<Leader>tp", function() require("neotest").output_panel.toggle() end, { silent = true, desc = 'Toggle test output pane' })

-- nvim-dap
vim.keymap.set("n", "<Leader>et", function() require("neotest").run.run({ strategy = "dap" }) end, { desc = 'Debug nearest test' })
vim.keymap.set("n", "<Leader>eb", function() require("dap").toggle_breakpoint() end, { desc = "Debug set breakpoint" })
vim.keymap.set("n", "<leader>ee", function() require("dapui").eval() end, { desc = "Debug evaluate" })
vim.keymap.set("n", "<Leader>ec", function() require("dap").continue() end, { desc = "Debug continue" })
vim.keymap.set("n", "<Leader>eo", function() require("dap").over() end, { desc = "Debug step over" })
vim.keymap.set("n", "<Leader>ei", function() require("dap").into() end, { desc = "Debug step into" })
vim.keymap.set("n", "<Leader>er", function() require("dap").repl.open() end, { desc = "Debug run repl" })

vim.api.nvim_create_user_command("DAPUI", function() require("dapui").toggle() end, { desc = "Open DAPUI" })
```

