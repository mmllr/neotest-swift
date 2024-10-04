local create_adapter = require("neotest-swift.adapter")
local Path = require("plenary.path")

local function is_test_file(file_path)
	if not vim.endswith(file_path, ".swift") then
		return false
	end
	local elems = vim.split(file_path, Path.path.sep)
	local file_name = elems[#elems]
	return vim.endswith(file_name, "Test.swift") or vim.endswith(file_name, "Tests.swift")
end

---@class neotest-swift.AdapterConfig
---@param config neotest-swift.AdapterConfig
local augment_config = function(config)
	---@type neotest-swift._AdapterConfig
	return {
		is_test_file = config.is_test_file or is_test_file,
	}
end

local adapter = create_adapter(augment_config({}))

setmetatable(adapter, {
	__call = function(_, config)
		return create_adapter(augment_config(config))
	end,
})

return adapter
