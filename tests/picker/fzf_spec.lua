---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.picker.fzf", function()
	local fzf_picker
	local api
	local haunt

	-- Mock vim functions
	local original_notify
	local notifications

	before_each(function()
		helpers.reset_modules()
		package.loaded["fzf-lua"] = nil
		notifications = {}

		-- Mock vim.notify to capture notifications
		original_notify = vim.notify
		vim.notify = function(msg, level)
			table.insert(notifications, { msg = msg, level = level })
		end

		-- Initialize modules
		haunt = require("haunt")
		haunt.setup()
		api = require("haunt.api")
		api._reset_for_testing()
		fzf_picker = require("haunt.picker.fzf")
	end)

	after_each(function()
		vim.notify = original_notify
		package.loaded["fzf-lua"] = nil
	end)

	describe("is_available()", function()
		it("returns false when fzf-lua is not installed", function()
			assert.is_false(fzf_picker.is_available())
		end)

		-- Note: Testing with real fzf-lua would require installing it
		-- These tests focus on the unavailable case
	end)

	describe("show()", function()
		local bufnr, test_file

		before_each(function()
			bufnr, test_file = helpers.create_test_buffer()
		end)

		after_each(function()
			helpers.cleanup_buffer(bufnr, test_file)
		end)

		it("returns false when fzf-lua is not available", function()
			local result = fzf_picker.show()
			assert.is_false(result)
		end)

		it("does not notify when fzf-lua is not available", function()
			-- The show() function just returns false, doesn't notify
			-- Notification is handled by the parent picker module
			fzf_picker.show()
			assert.are.equal(0, #notifications)
		end)
	end)

	describe("set_picker_module()", function()
		it("accepts a module reference without error", function()
			local ok = pcall(fzf_picker.set_picker_module, { show = function() end })
			assert.is_true(ok)
		end)
	end)
end)

-- Integration tests with mock fzf-lua
describe("haunt.picker.fzf with mock", function()
	local fzf_picker
	local api
	local haunt

	-- Mock fzf-lua
	local mock_fzf

	-- Mock vim functions
	local original_notify
	local original_input
	local notifications

	-- Create mock fzf-lua
	local function create_mock_fzf()
		local mock = {
			fzf_exec_called = false,
			fzf_exec_items = nil,
			fzf_exec_opts = nil,
		}
		mock.fzf_exec = function(items, opts)
			mock.fzf_exec_called = true
			mock.fzf_exec_items = items
			mock.fzf_exec_opts = opts
		end
		return mock
	end

	-- Helper to execute an action
	local function execute_action(opts, action_name, selected)
		if opts and opts.actions and opts.actions[action_name] then
			return opts.actions[action_name](selected)
		end
	end

	before_each(function()
		helpers.reset_modules()
		package.loaded["fzf-lua"] = nil

		-- Setup mocks
		mock_fzf = create_mock_fzf()
		notifications = {}

		-- Mock fzf-lua by pre-loading it into package.loaded
		package.loaded["fzf-lua"] = mock_fzf

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
		fzf_picker = require("haunt.picker.fzf")
	end)

	after_each(function()
		vim.notify = original_notify
		vim.fn.input = original_input
		package.loaded["fzf-lua"] = nil
	end)

	describe("is_available()", function()
		it("returns true when fzf-lua is installed", function()
			assert.is_true(fzf_picker.is_available())
		end)

		it("returns false when fzf-lua is not installed", function()
			package.loaded["fzf-lua"] = nil
			package.loaded["haunt.picker.fzf"] = nil
			fzf_picker = require("haunt.picker.fzf")

			assert.is_false(fzf_picker.is_available())

			-- Restore
			package.loaded["fzf-lua"] = mock_fzf
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

		it("returns false when fzf-lua is not available", function()
			package.loaded["fzf-lua"] = nil
			package.loaded["haunt.picker.fzf"] = nil
			fzf_picker = require("haunt.picker.fzf")

			local result = fzf_picker.show()
			assert.is_false(result)

			-- Restore
			package.loaded["fzf-lua"] = mock_fzf
		end)

		it("returns true and notifies when no bookmarks exist", function()
			local result = fzf_picker.show()

			assert.is_true(result)
			assert.is_false(mock_fzf.fzf_exec_called)
			assert.are.equal(1, #notifications)
			assert.is_truthy(notifications[1].msg:match("No bookmarks found"))
		end)

		it("calls fzf.fzf_exec when bookmarks exist", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test bookmark")

			fzf_picker.show()

			assert.is_true(mock_fzf.fzf_exec_called)
			assert.is_not_nil(mock_fzf.fzf_exec_items)
			assert.is_not_nil(mock_fzf.fzf_exec_opts)
		end)

		it("builds display list with correct format", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test note")

			fzf_picker.show()

			assert.are.equal(1, #mock_fzf.fzf_exec_items)
			local item = mock_fzf.fzf_exec_items[1]
			-- Should contain file:line:col format
			assert.is_truthy(item:match(":%d+:%d+"))
			-- Should contain the note
			assert.is_truthy(item:match("Test note"))
		end)

		it("merges opts into fzf config", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			local custom_opts = {
				prompt = "Custom Prompt> ",
				previewer = false,
			}

			fzf_picker.show(custom_opts)

			local opts = mock_fzf.fzf_exec_opts
			assert.are.equal("Custom Prompt> ", opts.prompt)
			assert.are.equal(false, opts.previewer)
		end)

		it("configures default action for selection", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			fzf_picker.show()

			local opts = mock_fzf.fzf_exec_opts
			assert.is_not_nil(opts.actions)
			assert.is_not_nil(opts.actions["default"])
		end)

		it("configures delete action with configured key", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			fzf_picker.show()

			local opts = mock_fzf.fzf_exec_opts
			assert.is_not_nil(opts.actions)
			-- Default delete key is "d"
			assert.is_not_nil(opts.actions["d"])
		end)

		it("configures edit_annotation action with configured key", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			api.annotate("Test")

			fzf_picker.show()

			local opts = mock_fzf.fzf_exec_opts
			assert.is_not_nil(opts.actions)
			-- Default edit_annotation key is "a"
			assert.is_not_nil(opts.actions["a"])
		end)
	end)

	describe("default action", function()
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

		it("switches to selected file buffer", function()
			vim.api.nvim_set_current_buf(bufnr2)
			fzf_picker.show()

			-- Find the display item for file 1
			local file1_item = nil
			for _, item in ipairs(mock_fzf.fzf_exec_items) do
				if item:match(vim.fn.fnamemodify(test_file1, ":t")) then
					file1_item = item
					break
				end
			end

			execute_action(mock_fzf.fzf_exec_opts, "default", { file1_item })

			assert.are.equal(bufnr1, vim.api.nvim_get_current_buf())
		end)

		it("handles empty selection gracefully", function()
			fzf_picker.show()
			local ok = pcall(execute_action, mock_fzf.fzf_exec_opts, "default", {})
			assert.is_true(ok)
		end)

		it("handles nil selection gracefully", function()
			fzf_picker.show()
			local ok = pcall(execute_action, mock_fzf.fzf_exec_opts, "default", nil)
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
			fzf_picker.show()
			local item_to_delete = mock_fzf.fzf_exec_items[2]

			assert.are.equal(3, #api.get_bookmarks())

			execute_action(mock_fzf.fzf_exec_opts, "d", { item_to_delete })

			assert.are.equal(2, #api.get_bookmarks())
		end)

		it("notifies when no bookmarks remain after delete", function()
			-- Delete all but one bookmark first
			api.delete_by_id(api.get_bookmarks()[1].id)
			api.delete_by_id(api.get_bookmarks()[1].id)

			fzf_picker.show()
			local last_item = mock_fzf.fzf_exec_items[1]
			notifications = {} -- Clear previous notifications

			execute_action(mock_fzf.fzf_exec_opts, "d", { last_item })

			local has_notification = false
			for _, notif in ipairs(notifications) do
				if notif.msg:match("No bookmarks remaining") then
					has_notification = true
					break
				end
			end
			assert.is_true(has_notification)
		end)

		it("handles empty selection gracefully", function()
			fzf_picker.show()
			local ok = pcall(execute_action, mock_fzf.fzf_exec_opts, "d", {})
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
			fzf_picker.set_picker_module({ show = function() end })

			fzf_picker.show()
			local item = mock_fzf.fzf_exec_items[1]
			execute_action(mock_fzf.fzf_exec_opts, "a", { item })

			assert.are.equal("Original note", prompted_default)
		end)

		it("updates annotation successfully", function()
			vim.fn.input = function()
				return "Updated note"
			end

			-- Set parent module for reopen
			fzf_picker.set_picker_module({ show = function() end })

			fzf_picker.show()
			local item = mock_fzf.fzf_exec_items[1]
			execute_action(mock_fzf.fzf_exec_opts, "a", { item })

			local bookmarks = api.get_bookmarks()
			assert.are.equal("Updated note", bookmarks[1].note)
		end)

		it("handles empty selection gracefully", function()
			fzf_picker.show()
			local ok = pcall(execute_action, mock_fzf.fzf_exec_opts, "a", {})
			assert.is_true(ok)
		end)
	end)
end)
