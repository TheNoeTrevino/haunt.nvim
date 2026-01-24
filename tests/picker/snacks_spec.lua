---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.picker.snacks", function()
	local snacks_picker
	local api
	local haunt

	-- Mock Snacks.nvim picker
	local mock_snacks

	-- Mock vim functions
	local original_notify
	local original_input
	local notifications

	-- Create mock Snacks picker
	local function create_mock_snacks()
		local mock = {
			picker_called = false,
			picker_config = nil,
			picker_instance = {
				closed = false,
				refreshed = false,
				close = function(self)
					self.closed = true
				end,
				refresh = function(self)
					self.refreshed = true
				end,
			},
		}
		-- Picker is called as Snacks.picker(...) not Snacks:picker(...)
		mock.picker = function(config)
			mock.picker_called = true
			mock.picker_config = config
			return mock.picker_instance
		end
		return mock
	end

	-- Helper to execute a captured action
	local function execute_action(config, action_name, item)
		if config and config.actions and config.actions[action_name] then
			return config.actions[action_name](mock_snacks.picker_instance, item)
		end
	end

	-- Helper to execute confirm action
	local function execute_confirm(config, item)
		if config and config.confirm then
			return config.confirm(mock_snacks.picker_instance, item)
		end
	end

	-- Helper to execute finder
	local function execute_finder(config)
		if config and config.finder then
			return config.finder()
		end
		return {}
	end

	before_each(function()
		helpers.reset_modules()
		package.loaded["snacks"] = nil

		-- Setup mocks
		mock_snacks = create_mock_snacks()
		notifications = {}

		-- Mock Snacks by pre-loading it into package.loaded
		package.loaded["snacks"] = mock_snacks

		-- Mock vim.notify to capture notifications
		original_notify = vim.notify
		vim.notify = function(msg, level)
			table.insert(notifications, { msg = msg, level = level })
		end

		-- Mock vim.fn.input
		original_input = vim.fn.input
		vim.fn.input = function(opts)
			return opts.default or ""
		end

		-- Initialize modules
		haunt = require("haunt")
		haunt.setup()
		api = require("haunt.api")
		api._reset_for_testing()
		snacks_picker = require("haunt.picker.snacks")
	end)

	after_each(function()
		vim.notify = original_notify
		vim.fn.input = original_input
		package.loaded["snacks"] = nil
	end)

	describe("is_available()", function()
		it("returns true when Snacks is installed", function()
			assert.is_true(snacks_picker.is_available())
		end)

		it("returns false when Snacks is not installed", function()
			package.loaded["snacks"] = nil
			package.loaded["haunt.picker.snacks"] = nil
			snacks_picker = require("haunt.picker.snacks")

			assert.is_false(snacks_picker.is_available())

			-- Restore
			package.loaded["snacks"] = mock_snacks
		end)
	end)

	describe("show()", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("returns false when Snacks is not available", function()
			package.loaded["snacks"] = nil
			package.loaded["haunt.picker.snacks"] = nil
			snacks_picker = require("haunt.picker.snacks")

			local result = snacks_picker.show()
			assert.is_false(result)

			-- Restore
			package.loaded["snacks"] = mock_snacks
		end)

		it("returns true and notifies when no bookmarks exist", function()
			local result = snacks_picker.show()

			assert.is_true(result)
			assert.is_false(mock_snacks.picker_called)
			assert.are.equal(1, #notifications)
			assert.is_truthy(notifications[1].msg:match("No bookmarks found"))
		end)

		it("calls Snacks.picker when bookmarks exist", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test bookmark")

			snacks_picker.show()

			assert.is_true(mock_snacks.picker_called)
			assert.is_not_nil(mock_snacks.picker_config)
		end)

		it("applies custom keybindings from config", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			snacks_picker.show()

			local config = mock_snacks.picker_config
			assert.is_not_nil(config.win)
			assert.is_not_nil(config.win.input)
			assert.is_not_nil(config.win.input.keys)
			assert.is_not_nil(config.win.list)
			assert.is_not_nil(config.win.list.keys)
		end)

		it("merges opts into Snacks.picker config", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			local custom_opts = {
				title = "Custom Title",
				layout = { preset = "vscode" },
			}

			snacks_picker.show(custom_opts)

			local config = mock_snacks.picker_config
			assert.are.equal("Custom Title", config.title)
			assert.are.equal("vscode", config.layout.preset)
		end)
	end)

	describe("finder function", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("returns items with all required fields", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test note")

			snacks_picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			assert.are.equal(1, #items)
			local item = items[1]
			assert.is_not_nil(item.idx)
			assert.is_not_nil(item.file)
			assert.is_not_nil(item.pos)
			assert.is_not_nil(item.id)
			assert.is_not_nil(item.line)
		end)
	end)

	describe("confirm action", function()
		local bufnr1, test_file1, bufnr2, test_file2

		before_each(function()
			bufnr1, test_file1 = helpers.create_test_buffer({ "File1 Line 1", "File1 Line 2", "File1 Line 3" })
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("Bookmark in file 1")

			bufnr2, test_file2 = helpers.create_test_buffer({ "File2 Line 1", "File2 Line 2" })
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Bookmark in file 2")
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr1, test_file1)
			helpers.cleanup_buffer(bufnr2, test_file2)
		end)

		it("switches to loaded file buffer", function()
			vim.api.nvim_set_current_buf(bufnr2)
			snacks_picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			-- Find item for file 1
			local item = nil
			for _, i in ipairs(items) do
				if i.file == test_file1 then
					item = i
					break
				end
			end

			execute_confirm(mock_snacks.picker_config, item)

			assert.are.equal(bufnr1, vim.api.nvim_get_current_buf())
		end)

		it("closes picker after selection", function()
			snacks_picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			execute_confirm(mock_snacks.picker_config, items[1])

			assert.is_true(mock_snacks.picker_instance.closed)
		end)

		it("handles nil item gracefully", function()
			snacks_picker.show()
			local ok = pcall(execute_confirm, mock_snacks.picker_config, nil)
			assert.is_true(ok)
		end)
	end)

	describe("delete action", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("First")
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			api.annotate("Second")
			vim.api.nvim_win_set_cursor(0, { 3, 0 })
			api.annotate("Third")
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("deletes bookmark by ID", function()
			snacks_picker.show()
			local items = execute_finder(mock_snacks.picker_config)
			local item_to_delete = items[2]

			assert.are.equal(3, #api.get_bookmarks())

			execute_action(mock_snacks.picker_config, "delete", item_to_delete)

			assert.are.equal(2, #api.get_bookmarks())
		end)

		it("refreshes picker after delete", function()
			snacks_picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			execute_action(mock_snacks.picker_config, "delete", items[1])

			assert.is_true(mock_snacks.picker_instance.refreshed)
		end)

		it("closes picker when no bookmarks remain", function()
			snacks_picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			-- Delete all bookmarks
			execute_action(mock_snacks.picker_config, "delete", items[1])
			mock_snacks.picker_instance.refreshed = false

			execute_action(mock_snacks.picker_config, "delete", items[2])
			mock_snacks.picker_instance.refreshed = false

			execute_action(mock_snacks.picker_config, "delete", items[3])

			assert.is_true(mock_snacks.picker_instance.closed)
		end)

		it("handles nil item gracefully", function()
			snacks_picker.show()
			local ok = pcall(execute_action, mock_snacks.picker_config, "delete", nil)
			assert.is_true(ok)
			assert.are.equal(3, #api.get_bookmarks())
		end)
	end)

	describe("edit_annotation action", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Original note")

			vim.fn.input = function(opts)
				return opts.default or ""
			end
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("prompts with existing annotation as default", function()
			local prompted_default = nil
			vim.fn.input = function(opts)
				prompted_default = opts.default
				return "Updated note"
			end

			-- Set parent module for reopen
			snacks_picker.set_picker_module({ show = function() end })

			snacks_picker.show()
			local items = execute_finder(mock_snacks.picker_config)
			execute_action(mock_snacks.picker_config, "edit_annotation", items[1])

			assert.are.equal("Original note", prompted_default)
		end)

		it("updates annotation successfully", function()
			vim.fn.input = function()
				return "Updated note"
			end

			-- Set parent module for reopen
			snacks_picker.set_picker_module({ show = function() end })

			snacks_picker.show()
			local items = execute_finder(mock_snacks.picker_config)
			execute_action(mock_snacks.picker_config, "edit_annotation", items[1])

			local bookmarks = api.get_bookmarks()
			assert.are.equal("Updated note", bookmarks[1].note)
		end)

		it("closes picker before prompting", function()
			vim.fn.input = function()
				-- Check if picker was closed when input is called
				assert.is_true(mock_snacks.picker_instance.closed)
				return "New note"
			end

			-- Set parent module for reopen
			snacks_picker.set_picker_module({ show = function() end })

			snacks_picker.show()
			local items = execute_finder(mock_snacks.picker_config)

			mock_snacks.picker_instance.closed = false
			execute_action(mock_snacks.picker_config, "edit_annotation", items[1])
		end)

		it("handles nil item gracefully", function()
			snacks_picker.show()
			local ok = pcall(execute_action, mock_snacks.picker_config, "edit_annotation", nil)
			assert.is_true(ok)
		end)
	end)
end)
