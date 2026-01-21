---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.sidekick", function()
	local sidekick
	local api
	local cwd

	before_each(function()
		helpers.reset_modules()
		sidekick = require("haunt.sidekick")
		api = require("haunt.api")
		cwd = vim.fn.getcwd()
	end)

	describe("get_locations", function()
		it("returns empty string when no bookmarks exist", function()
			local original_get_bookmarks = api.get_bookmarks
			api.get_bookmarks = function()
				return {}
			end

			local result = sidekick.get_locations()

			api.get_bookmarks = original_get_bookmarks

			assert.are.equal("", result)
		end)

		it("formats output with correct prefix and line numbers", function()
			local mock_bookmarks = {
				{
					file = cwd .. "/lua/haunt/api.lua",
					line = 793,
					note = "Important function",
					id = "test1",
				},
				{
					file = cwd .. "/lua/haunt/config.lua",
					line = 42,
					note = nil,
					id = "test2",
				},
				{
					file = cwd .. "/lua/haunt/display.lua",
					line = 100,
					note = "Check this later",
					id = "test3",
				},
			}

			local original_get_bookmarks = api.get_bookmarks
			api.get_bookmarks = function()
				return vim.deepcopy(mock_bookmarks)
			end

			local result = sidekick.get_locations()

			api.get_bookmarks = original_get_bookmarks

			assert.is_not_nil(result)
			assert.are_not.equal("", result)

			-- Check each line has correct format
			for line in result:gmatch("[^\n]+") do
				assert.is_truthy(line:match("^%- @/"), "line should start with '- @/'")
				assert.is_truthy(line:match(":L%d+"), "line should contain :L{number}")
			end
		end)

		it("includes annotations when append_annotations=true", function()
			local mock_bookmarks = {
				{
					file = cwd .. "/test.lua",
					line = 10,
					note = "My annotation",
					id = "test1",
				},
				{
					file = cwd .. "/test2.lua",
					line = 20,
					note = nil,
					id = "test2",
				},
			}

			local original_get_bookmarks = api.get_bookmarks
			api.get_bookmarks = function()
				return vim.deepcopy(mock_bookmarks)
			end

			local result = sidekick.get_locations({ append_annotations = true })

			api.get_bookmarks = original_get_bookmarks

			assert.is_truthy(result:match('- "My annotation"'))
		end)

		it("excludes annotations when append_annotations=false", function()
			local mock_bookmarks = {
				{
					file = cwd .. "/test.lua",
					line = 10,
					note = "My annotation",
					id = "test1",
				},
			}

			local original_get_bookmarks = api.get_bookmarks
			api.get_bookmarks = function()
				return vim.deepcopy(mock_bookmarks)
			end

			local result = sidekick.get_locations({ append_annotations = false })

			api.get_bookmarks = original_get_bookmarks

			assert.is_falsy(result:match('"My annotation"'))
			assert.is_truthy(result:match("@/test%.lua :L10"))
		end)

		it("filters to current buffer when current_buffer=true", function()
			local current_file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")

			local mock_bookmarks = {
				{
					file = current_file,
					line = 10,
					note = "Current buffer bookmark",
					id = "test1",
				},
				{
					file = cwd .. "/some/other/file.lua",
					line = 20,
					note = "Other file bookmark",
					id = "test2",
				},
				{
					file = current_file,
					line = 30,
					note = "Another current buffer bookmark",
					id = "test3",
				},
			}

			local original_get_bookmarks = api.get_bookmarks
			api.get_bookmarks = function()
				return vim.deepcopy(mock_bookmarks)
			end

			local result_all = sidekick.get_locations({ current_buffer = false })
			local result_current = sidekick.get_locations({ current_buffer = true })

			api.get_bookmarks = original_get_bookmarks

			-- Count lines
			local count_all = 0
			for _ in result_all:gmatch("[^\n]+") do
				count_all = count_all + 1
			end

			local count_current = 0
			for _ in result_current:gmatch("[^\n]+") do
				count_current = count_current + 1
			end

			assert.are.equal(3, count_all)
			assert.are.equal(2, count_current)
			assert.is_falsy(result_current:match("other/file%.lua"))
		end)

		it("sorts bookmarks by file path then line number", function()
			local mock_bookmarks = {
				{
					file = cwd .. "/z_file.lua",
					line = 50,
					note = nil,
					id = "test1",
				},
				{
					file = cwd .. "/a_file.lua",
					line = 30,
					note = nil,
					id = "test2",
				},
				{
					file = cwd .. "/a_file.lua",
					line = 10,
					note = nil,
					id = "test3",
				},
				{
					file = cwd .. "/m_file.lua",
					line = 20,
					note = nil,
					id = "test4",
				},
			}

			local original_get_bookmarks = api.get_bookmarks
			api.get_bookmarks = function()
				return vim.deepcopy(mock_bookmarks)
			end

			local result = sidekick.get_locations({ append_annotations = false })

			api.get_bookmarks = original_get_bookmarks

			local lines = {}
			for line in result:gmatch("[^\n]+") do
				table.insert(lines, line)
			end

			assert.is_truthy(lines[1]:match("a_file%.lua :L10"))
			assert.is_truthy(lines[2]:match("a_file%.lua :L30"))
			assert.is_truthy(lines[3]:match("m_file%.lua :L20"))
			assert.is_truthy(lines[4]:match("z_file%.lua :L50"))
		end)

		it("uses relative paths with @/ prefix", function()
			local mock_bookmarks = {
				{
					file = cwd .. "/lua/haunt/sidekick.lua",
					line = 42,
					note = nil,
					id = "test1",
				},
			}

			local original_get_bookmarks = api.get_bookmarks
			api.get_bookmarks = function()
				return vim.deepcopy(mock_bookmarks)
			end

			local result = sidekick.get_locations({ append_annotations = false })

			api.get_bookmarks = original_get_bookmarks

			assert.is_falsy(result:match(vim.pesc(cwd)))
			assert.is_truthy(result:match("@/lua/haunt/sidekick%.lua"))
		end)

		it("handles special characters in notes", function()
			local mock_bookmarks = {
				{
					file = cwd .. "/test.lua",
					line = 10,
					note = 'Note with "quotes" and special chars: <>&',
					id = "test1",
				},
			}

			local original_get_bookmarks = api.get_bookmarks
			api.get_bookmarks = function()
				return vim.deepcopy(mock_bookmarks)
			end

			local result = sidekick.get_locations({ append_annotations = true })

			api.get_bookmarks = original_get_bookmarks

			assert.is_truthy(type(result) == "string")
			assert.is_truthy(result:match("test%.lua :L10"))
		end)
	end)
end)
