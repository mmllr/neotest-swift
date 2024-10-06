local logger = require("neotest-swift.logging")
local lib = require("neotest.lib")
local async = require("neotest.async")
local nio = require("nio")

--- @class TestData
--- @field pos_id string
--- @field status neotest.ResultStatus
--- @field short? string Shortened output string
--- @field errors? neotest.Error[]
--- @field neotest_data neotest.Position
--- @field swifttest_data SwiftTestData
--- @field duplicate_test_detected boolean
---
--- @class SwiftTestData
--- @field name string Test name.
--- @field class string Class name.
--- @field output? string[] Test output.
---
--- @class RunspecContext
--- @field pos_id string Neotest tree position id.
--- @field errors? table<string> Non-test errors to show in the final output.
--- @field is_dap_active boolean? If true, parsing of test output will occur.
---
---@class neotest.SwiftTestRunArgs
---@field tree neotest.Tree
---@field extra_args? string[]
---@field strategy string
---@field runTarget boolean?

local treesitter_queries = [[
    ;; Tests classes
    ((class_declaration
      name: (type_identifier) @namespace.name
      (#match? @namespace.name ".*Tests$"))
    ) @namespace.definition

    ;; Test classes
    ((class_declaration
      name: (type_identifier) @namespace.name
      (#match? @namespace.name ".*Test$"))
    ) @namespace.definition

    ;; Test functions
    ((function_declaration
      name: (simple_identifier) @test.name
      (#match? @test.name "^test.*")
    )) @test.definition
  ]]

local get_root = lib.files.match_root_pattern("Package.swift")

--- @param test_name string
--- @param dap_args? table
--- @param program string
--- @return table | nil
local function get_dap_config(test_name, dap_args, program)
	-- :help dap-configuration
	return vim.tbl_extend("force", {
		type = "swift",
		name = "Neotest-swift",
		request = "launch",
		mode = "test",
		program = program,
		args = { "--filter", test_name },
	}, dap_args or {})
end

-- @return vim.SystemObj
local function swift_test_list()
	local list_cmd = { "swift", "test", "list", "--skip-build" }
	local list_cmd_string = table.concat(list_cmd, " ")
	logger.debug("Running swift list: " .. list_cmd_string)
	local result = vim.system(list_cmd, { text = true }):wait()

	local err = nil
	if result.code == 1 then
		err = "swift list:"
		if result.stdout ~= nil and result.stdout ~= "" then
			err = err .. " " .. result.stdout
		end
		if result.stdout ~= nil and result.stderr ~= "" then
			err = err .. " " .. result.stderr
		end
		logger.error({ "Swift list error: ", err })
	end
	return result
end

---@param result neotest.StrategyResult
---@param tree neotest.Tree
local function parse_test_result_output(result, tree)
	--- Internal data structure to store test result data.
	--- @type table<string, TestData>
	local res = {}

	--- Table storing the name of the test (position.id) and the number of times
	--- it was found in the tree.
	--- @type table<string, number>
	local dupes = {}

	for _, node in tree:iter_nodes() do
		local child = node:data()
		logger.info("Node info: " .. child.id .. " - " .. child.type)
		if child.type == "test" then
			-- id pattern /Users/emmet/projects/hello/Tests/AppTests/fileName.swift::className::testName
			local class_name, test_name = string.match(child.id, "[:][:]([%w_-]+)[:][:]([%w_-]+)")
			if class_name and test_name then
				local simple_name = class_name .. "/" .. test_name
				logger.info("Setting simple name " .. simple_name)
				res[simple_name] = {
					pos_id = child.id,
					status = "skipped",
					errors = {},
					neotest_data = child,
					swifttest_data = {
						name = test_name,
						class = class_name,
						output = {},
					},
					duplicate_test_detected = false,
				}

				-- detect duplicate test names
				if dupes[simple_name] == nil then
					dupes[simple_name] = 1
				else
					dupes[simple_name] = dupes[child.id] + 1
					res[simple_name].duplicate_test_detected = true
				end
			end
		end
	end

	local raw_output = async.fn.readfile(result.output)

	local simple_name = ""
	local test_lines = {}
	local errors = {}
	for _, line in ipairs(raw_output) do
		if line:match("^Test Case") then
			-- Capture the suite_name, class name, test name, and status (passed/failed/skipped/started)
			-- Test Case '-[CommonTests.DTO_UserLoginTests testInit]' passed (0.000 seconds).
			local _, class_name, test_name, status =
				string.match(line, "[%s%w]*'-%[([%w_-]+)%.([%w_-]+)%s+([%w_-]+)%]'%s+(%w+)")
			if status == "started" then
				simple_name = class_name .. "/" .. test_name
				table.insert(test_lines, line)
			elseif status == "failed" and res[simple_name] then
				table.insert(test_lines, line)
				res[simple_name]["status"] = status
				res[simple_name]["errors"] = vim.deepcopy(errors)
				res[simple_name]["short"] = table.concat(test_lines, "\n")
				simple_name = ""
				test_lines = {}
				errors = {}
			elseif res[simple_name] then
				table.insert(test_lines, line)
				res[simple_name]["status"] = status
				res[simple_name]["short"] = table.concat(test_lines, "\n")
				simple_name = ""
				test_lines = {}
				errors = {}
			end
		elseif simple_name ~= "" then
			-- Example:
			-- /Users/emmet/projects/test-project/Tests/DTOTests/UserStatusRequestDTOTests.swift:12: error: -[CommonTests.DTO_UserStatusRequestTests testInit] : XCTAssertEqual failed: ("123") is not equal to ("124")
			table.insert(test_lines, line)
			local line_number, error_message = string.match(line, ":(%d+):[^:]+[:][^:]+:(.+)")
			if line_number and error_message then
				table.insert(errors, { message = error_message, line = tonumber(line_number) })
			else
				table.insert(errors, { message = line })
			end
		end
	end

	local neotest_output = {}
	for _, output in pairs(res) do
		neotest_output[output.pos_id] = output
	end
	return neotest_output
end

---@class neotest-swift._AdapterConfig
---@field is_test_file? fun(file_path: string):boolean
---@field dap_args? table
---@param config neotest-swift._AdapterConfig
---@return neotest.Adapter
return function(config)
	---@type neotest.Adapter
	return {
		name = "neotest-swift",
		root = get_root,
		filter_dir = function(name)
			local ignore_dirs = { ".git", "node_modules", ".venv", "venv" }
			for _, ignore in ipairs(ignore_dirs) do
				if name == ignore then
					return false
				end
			end
			return true
		end,
		is_test_file = config.is_test_file,
		discover_positions = function(path)
			return lib.treesitter.parse_positions(path, treesitter_queries, {
				require_namespaces = false,
				nested_tests = true,
			})
		end,
		---@param args neotest.RunArgs
		---@return neotest.RunSpec | neotest.RunSpec[] | nil
		build_spec = function(args)
			--- The tree object, describing the AST-detected tests and their positions.
			--- @type neotest.Tree
			local tree = args.tree

			--- The position object, describing the current directory, file or test.
			--- @type neotest.Position
			local pos = args.tree:data() -- NOTE: causes <file> is not accessible by the current user!

			if not tree then
				logger.error("Unexpectedly did not receive a neotest.Tree.")
				return
			end

			local context = {
				pos_id = pos.id,
			}

			local strategy_config = nil
			if args.strategy == "dap" then
				-- id pattern /Users/emmet/projects/hello/Tests/AppTests/fileName.swift::className::testName
				local class_name, test_name = string.match(pos.id, "[:][:]([%w_-]+)[:][:]([%w_-]+)")
				local list_result = swift_test_list()
                local output = list_result.stdout or ""
                local program = ""
				for line in output:gmatch("[^\r\n]+") do
					local suite, namespace, test = string.match(line, "([%w-_]+)%.([%w-_]+)%/([%w-_]+)")
					if suite and namespace == class_name and test == test_name then
                        program = get_root(pos.path) .. ".build/debug/" .. suite .. ".build/"
					end
				end

                if program == "" then
                    logger.error("Failed to find debug program.")
                end

				strategy_config = get_dap_config(class_name .. "/" .. test_name, config.dap_args or {}, program)
				logger.debug("DAP strategy used: " .. vim.inspect(strategy_config))
				return {
					command = { "swift", "test" },
					cwd = get_root(pos.path),
					context = context,
					strategy = strategy_config,
				}
			end

			-- Below is the main logic of figuring out how to execute tests. In short,
			-- a "runspec" is defined for each command to execute.
			-- Neotest also distinguishes between different "position types":
			-- - "dir": A directory of tests
			-- - "file": A single test file
			-- - "namespace": A set of tests, collected under the same namespace
			-- - "test": A single test
			--
			-- If a valid runspec is built and returned from this function, it will be
			-- executed by Neotest. But if, for some reason, this function returns nil,
			-- Neotest will call this function again, but using the next position type
			-- (in this order: dir, file, namespace, test). This gives the ability to
			-- have fallbacks.
			-- For example, if a runspec cannot be built for a file of tests, we can
			-- instead try to build a runspec for each individual test file. The end
			-- result would in this case produce multiple commands to execute (for each
			-- test) rather than one command for the file.
			-- The idea here is not to have such fallbacks take place in the future, but
			-- while this adapter is being developed, it can be useful to have such
			-- functionality.

			if pos.type == "dir" then
				-- A runspec is to be created, based on running all tests in the given
				-- directory.
				local cmd = { "swift", "test" }

				if args.extra_args and args.extra_args.target then
					local list_result = swift_test_list()
					local output = list_result.stdout or ""
					local suites = {}
					for line in output:gmatch("[^\r\n]+") do
						local suite, namespace, test = string.match(line, "([%w-_]+)%.([%w-_]+)%/([%w-_]+)")
						if suite and namespace and test then
							table.insert(suites, suite)
						end
					end
					for _, suite in ipairs(suites) do
						if string.find(vim.fn.expand("%"), suite) then
							table.insert(cmd, "--filter")
							table.insert(cmd, suite)
							return {
								command = cmd,
								cwd = get_root(pos.path),
								context = context,
							}
						end
					end
				end

				--- @type neotest.RunSpec
				local run_spec = {
					command = cmd,
					cwd = get_root(pos.path),
					context = context,
					strategy = strategy_config,
				}

				logger.debug({ "RunSpec:", run_spec })
				return run_spec
			elseif pos.type == "file" or pos.type == "namespace" then
				local classes = {}
				for line in io.lines(pos.path) do
					if line:match("class") then
						local class_name = line:match("class%s+([%w_]+)%s*[:{]")
						table.insert(classes, class_name)
					end
				end

				local cmd = { "swift", "test" }
				for _, class in ipairs(classes) do
					table.insert(cmd, "--filter")
					table.insert(cmd, class)
				end

				--- @type neotest.RunSpec
				local run_spec = {
					command = cmd,
					cwd = get_root(pos.path),
					context = context,
					strategy = strategy_config,
				}

				logger.debug({ "RunSpec:", run_spec })
				return run_spec
			elseif pos.type == "test" then
				local tests = {}
				local class_name = ""
				for line in io.lines(pos.path) do
					if line:match("class") then
						class_name = line:match("class%s+([%w_]+)%s*[:{]")
					elseif line:match("func") and line:match("private") == nil then
						local function_name = line:match("%w*%s*func%s+([%w_]+)%s*%(")
						if function_name:match(pos.name) then
							table.insert(tests, class_name .. "/" .. function_name)
						end
					end
				end

				local cmd = { "swift", "test" }
				for _, test in ipairs(tests) do
					table.insert(cmd, "--filter")
					table.insert(cmd, test)
				end

				--- @type neotest.RunSpec
				local run_spec = {
					command = cmd,
					cwd = get_root(pos.path),
					context = context,
					strategy = strategy_config,
				}

				logger.debug({ "RunSpec:", run_spec })
				return run_spec
			end

			logger.error("Unknown Neotest position type, " .. "cannot build runspec with position type: " .. pos.type)
		end,
		---@param spec neotest.RunSpec
		---@param result neotest.StrategyResult
		---@param tree neotest.Tree
		---@return table<string, neotest.Result>
		results = function(spec, result, tree)
			--- The Neotest position tree node for this execution.
			--- @type neotest.Position
			local pos = tree:data()

			--- Test command (e.g. 'swift test') status.
			--- @type neotest.ResultStatus
			local result_status = nil

			-- @type RunspecContext
			local context = spec.context

			if context and context.is_dap_active and context.pos_id then
				local neotest_result = {}
				-- return early if test result processing is not desired.
				neotest_result[context.pos_id] = {
					status = "skipped",
				}
				return neotest_result
			end

			-- if neotest_result[pos.id] and neotest_result[pos.id].status == "skipped" then
			-- keep the status if it was already decided to be skipped.
			-- result_status = "skipped"
			if spec.context.errors ~= nil and #spec.context.errors > 0 then
				-- mark as failed if a non-test error occurred.
				result_status = "failed"
			elseif result.code > 0 then
				-- mark as failed if the test command failed.
				result_status = "failed"
			elseif result.code == 0 then
				-- mark as passed if the 'test' command passed.
				result_status = "passed"
			else
				logger.error("Unexpected state when determining test status. Exit code was: " .. result.code)
			end

			local neotest_result = parse_test_result_output(result, tree)
			if neotest_result[pos.id] then
				neotest_result[pos.id]["status"] = result_status
				neotest_result[pos.id]["output"] = result.output
			else
				neotest_result[pos.id] = {
					status = result_status,
					output = result.output,
				}
			end
			return neotest_result
		end,
	}
end
